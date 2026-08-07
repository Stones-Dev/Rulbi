import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import 'probe_result.dart';
import 'source_providers.dart';

/// Estado ok/error del último import de esta *sesión de app* — deuda de
/// persistencia documentada y aceptada (D-plan-gestión, S4 · Ola 3): no
/// hay columna en `sources` para esto todavía, así que se pierde al cerrar
/// la app. [ImportController] lo actualiza al terminar cada import
/// (Done/Failed); [ImportCancelled] no lo toca — cancelar no es un juicio
/// sobre la fuente.
final lastImportStatusProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

/// Informe de tolerancia de una importación (S4 · Ola 3, ui-spec §2.14):
/// envuelve `ImportReport` (M3U) o `XtreamImportReport` (Xtream) sin
/// reinventar sus campos (P6 — cada capa de protocolo describe sus
/// propios fallos, `core`/`app` no los reinterpretan). `sealed` para que
/// la UI pueda hacer `switch` exhaustivo sobre las dos formas reales.
sealed class ImportSummary {
  const ImportSummary();
  int get discardedCount;
}

final class M3uImportSummary extends ImportSummary {
  const M3uImportSummary(this.report);
  final ImportReport report;

  @override
  int get discardedCount => report.discarded.length;
}

final class XtreamImportSummary extends ImportSummary {
  const XtreamImportSummary(this.report);
  final XtreamImportReport report;

  @override
  int get discardedCount => report.discardedCount;
}

/// Resultado de [ImportChannelSource.channelsFor]: mismo espíritu que
/// `M3uParseOutcome`/`XtreamImportOutcome` de `protocols` — el stream de
/// canales, tal cual se le pasa a `ManageSources`, y el informe una vez
/// que termina de emitir.
final class ImportChannels {
  const ImportChannels({required this.channels, required this.summary});
  final Stream<Channel> channels;
  final Future<ImportSummary> summary;
}

/// Puerto que produce el `Stream<Channel>` de una fuente para importar.
/// Dos implementaciones reales (M3U/Xtream) que reutilizan tal cual
/// `parseM3u`/`XtreamClient.importChannels()` — no reimplementan nada del
/// parseo. [ImportController] usa un fake de este puerto en sus tests, sin
/// red ni isolates reales.
abstract interface class ImportChannelSource {
  /// [password] solo lo usa la implementación Xtream (ya leída del
  /// almacén seguro por el llamador — este puerto no conoce
  /// `SecureCredentialStore`, misma separación que ya sigue
  /// `XtreamClientProbe`, P5/P6).
  ImportChannels channelsFor(Source source, {String? password});
}

/// M3U real: URL vía `http` en streaming completo (sin el tope de 256 KiB
/// de `HttpM3uProbe` — esto es el import de verdad, no una muestra) o
/// archivo local vía `File.openRead()`, hacia `parseM3u` (API pública de
/// `packages/protocols`).
final class M3uImportChannelSource implements ImportChannelSource {
  M3uImportChannelSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  ImportChannels channelsFor(Source source, {String? password}) {
    final config = source.config;
    final Stream<List<int>> bytes = switch (config) {
      M3uUrlSourceConfig(:final url, :final userAgent) => _fetchUrl(url, userAgent),
      M3uFileSourceConfig(:final filePath) => File(filePath).openRead(),
      XtreamSourceConfig() => throw ArgumentError(
        'M3uImportChannelSource recibió una XtreamSourceConfig — bug de '
        'orquestación en ImportController.',
      ),
    };

    final outcome = parseM3u(bytes: bytes, sourceId: source.id);
    return ImportChannels(
      channels: outcome.channels,
      summary: outcome.report.then(M3uImportSummary.new),
    );
  }

  Stream<List<int>> _fetchUrl(Uri url, String? userAgent) async* {
    final request = http.Request('GET', url);
    if (userAgent != null && userAgent.trim().isNotEmpty) {
      request.headers['User-Agent'] = userAgent.trim();
    }
    final streamed = await _client.send(request);
    if (streamed.statusCode >= 400) {
      throw HttpException('HTTP ${streamed.statusCode}', uri: url);
    }
    yield* streamed.stream;
  }
}

/// Xtream real, sobre `XtreamClient.importChannels()` (T1.4) — el mismo
/// par de transporte que ya usa `xtreamProbeProvider`
/// (`RetryingXtreamTransport(HttpXtreamTransport())`), construido de
/// nuevo en cada import para partir de un transporte limpio.
final class XtreamImportChannelSource implements ImportChannelSource {
  XtreamImportChannelSource({required this.transportFactory});

  final XtreamTransport Function() transportFactory;

  @override
  ImportChannels channelsFor(Source source, {String? password}) {
    final config = source.config;
    if (config is! XtreamSourceConfig) {
      throw ArgumentError(
        'XtreamImportChannelSource recibió una config no-Xtream — bug de '
        'orquestación en ImportController.',
      );
    }
    if (password == null) {
      throw StateError(
        'No hay contraseña en el almacén seguro para la fuente '
        '"${source.id}" — no se puede importar.',
      );
    }

    final client = XtreamClient(
      host: config.host,
      username: config.username,
      password: password,
      transport: transportFactory(),
    );
    final outcome = client.importChannels(sourceId: source.id);
    return ImportChannels(
      channels: outcome.channels,
      summary: outcome.report.then(XtreamImportSummary.new),
    );
  }
}

/// Estado de la importación en curso (ui-spec §2.14, "estado transversal"
/// — sobrevive a la navegación, ver [importControllerProvider]).
sealed class ImportState {
  const ImportState();
}

final class ImportIdle extends ImportState {
  const ImportIdle();
}

/// Fase de un [ImportRunning] (S5 · Ola 2, ADR-008): la importación de
/// canales siempre corre primero; la de guía EPG es una segunda fase
/// opcional (solo si la fuente tiene `epgUrl`, ver [EpgSource]) — sin
/// señal de progreso incremental propia (el escritor no expone avance
/// parcial), así que la UI la distingue por fase, no por un contador.
enum ImportPhase { channels, epg }

final class ImportRunning extends ImportState {
  const ImportRunning({
    required this.sourceId,
    required this.sourceName,
    required this.channelsSeen,
    this.phase = ImportPhase.channels,
  });
  final String sourceId;
  final String sourceName;
  final int channelsSeen;
  final ImportPhase phase;
}

final class ImportDone extends ImportState {
  const ImportDone({
    required this.sourceId,
    required this.sourceName,
    required this.stats,
    required this.summary,
    this.epgStats,
    this.epgReport,
    this.epgFailureReason,
  });
  final String sourceId;
  final String sourceName;
  final SourceImportStats stats;
  final ImportSummary summary;

  /// Los tres campos de EPG solo se completan cuando la fuente tiene
  /// `epgUrl` (`EpgSource.epgFor` devolvió algo que consumir) — si no,
  /// los tres quedan `null` sin más: la fuente sencillamente no tiene
  /// guía, no es un fallo de nada.
  ///
  /// Con `epgUrl` presente, [epgStats]/[epgReport] y [epgFailureReason]
  /// son mutuamente excluyentes: éxito rellena los dos primeros, fallo
  /// rellena solo el tercero — nunca los tres a la vez. Un fallo de EPG
  /// no convierte el import en [ImportFailed] (los canales ya se
  /// importaron bien, ver política de fallo en
  /// [ImportController._runEpgPhase]); [epgFailureReason] es cómo la UI
  /// sabe que hubo un intento y no salió bien, reutilizando el mismo
  /// `ProbeFailureReason`/`probeFailureReasonLabel` que ya usan las sondas
  /// M3U/Xtream y [ImportFailed], en vez de inventar una taxonomía de
  /// error propia para EPG.
  final EpgImportStats? epgStats;
  final XmltvImportReport? epgReport;
  final ProbeFailureReason? epgFailureReason;
}

final class ImportFailed extends ImportState {
  const ImportFailed({
    required this.sourceId,
    required this.sourceName,
    required this.reason,
    required this.channelsSeen,
  });
  final String sourceId;
  final String sourceName;
  final ProbeFailureReason reason;
  final int channelsSeen;
}

final class ImportCancelled extends ImportState {
  const ImportCancelled({
    required this.sourceId,
    required this.sourceName,
    required this.channelsSeen,
  });
  final String sourceId;
  final String sourceName;
  final int channelsSeen;
}

/// Motor de importación (S4 · Ola 3, ui-spec §2.14): conecta el
/// `Stream<Channel>` de [ImportChannelSource] con
/// `ManageSources.addSource`/`refreshSource` (T1.6b), publicando progreso
/// mientras el stream se consume.
///
/// **`NotifierProvider`, no `autoDispose`** (ver [importControllerProvider]
/// más abajo): el import sigue en curso aunque el usuario navegue fuera de
/// la pantalla de progreso (ui-spec §2.14, "en segundo plano").
///
/// **Cancelación**: [cancel] inyecta un error en el relay interpuesto
/// entre el parser y `ManageSources` — el `await for` de
/// `importSourceContent` (`packages/data`) lanza, la transacción de drift
/// hace rollback, y no queda nada del import a medias. Para una fuente
/// nueva, la fila `Source` ya se había insertado (fuera de esa
/// transacción, por `DefaultManageSources.addSource`) antes de cancelar
/// — queda con `lastRefresh == null`, el mismo estado que dejaba la Ola 2
/// al guardar sin importar.
class ImportController extends Notifier<ImportState> {
  ImportController({
    this.progressEvery = 250,
    this.progressInterval = const Duration(milliseconds: 100),
  });

  /// Cada cuántos canales forwardeados se publica progreso como mínimo
  /// (RNF-01: no reconstruir la UI en cada canal de un import de 100k).
  final int progressEvery;

  /// ...o cada cuánto tiempo, lo que llegue antes — para que un import
  /// lento (pocos canales, pero cada uno tarda) no se vea nunca avanzar.
  final Duration progressInterval;

  StreamSubscription<Channel>? _subscription;
  StreamController<Channel>? _relay;
  bool _cancelRequested = false;

  @override
  ImportState build() => const ImportIdle();

  Future<void> start(Source source) async {
    if (state is ImportRunning) return; // ya hay un import en curso

    _cancelRequested = false;
    state = ImportRunning(
      sourceId: source.id,
      sourceName: source.name,
      channelsSeen: 0,
    );

    final String? password;
    if (source.kind == SourceKind.xtream) {
      password = await ref.read(secureCredentialStoreProvider).read(source.id);
    } else {
      password = null;
    }

    final ImportChannelSource channelSource = source.kind == SourceKind.xtream
        ? ref.read(xtreamImportChannelSourceProvider)
        : ref.read(m3uImportChannelSourceProvider);

    final ImportChannels outcome;
    try {
      outcome = channelSource.channelsFor(source, password: password);
    } catch (error) {
      state = ImportFailed(
        sourceId: source.id,
        sourceName: source.name,
        reason: _mapImportError(error),
        channelsSeen: 0,
      );
      _markStatus(source.id, ok: false);
      return;
    }
    // `parseM3u`/`XtreamClient.importChannels()` completan su informe con
    // error también cuando el stream falla (mismo error que ya se reenvía
    // por `relay`) — si el import termina en `ImportFailed`, nunca se
    // llega a `await outcome.summary` más abajo, y ese futuro quedaría sin
    // observar. `.ignore()` silencia el aviso de "unhandled exception"
    // sin impedir que el `await` de la rama de éxito siga funcionando
    // (un `Future` admite más de un listener).
    outcome.summary.ignore();

    final relay = StreamController<Channel>();
    _relay = relay;
    var seen = 0;
    var lastPublished = DateTime.fromMillisecondsSinceEpoch(0);

    void publish() {
      lastPublished = DateTime.now();
      state = ImportRunning(
        sourceId: source.id,
        sourceName: source.name,
        channelsSeen: seen,
      );
    }

    _subscription = outcome.channels.listen(
      (channel) {
        if (_cancelRequested) return; // relay ya cerrado, no reenviar más
        seen++;
        relay.add(channel);
        if (seen % progressEvery == 0 ||
            DateTime.now().difference(lastPublished) > progressInterval) {
          publish();
        }
      },
      onError: relay.addError,
      onDone: relay.close,
      cancelOnError: false,
    );

    final manageSources = ref.read(manageSourcesProvider);
    final isNewSource = source.lastRefresh == null;

    try {
      final SourceImportStats stats = isNewSource
          ? (await manageSources.addSource(source, relay.stream)).$2
          : await manageSources.refreshSource(source.id, relay.stream);
      final summary = await outcome.summary;

      if (_cancelRequested) {
        state = ImportCancelled(
          sourceId: source.id,
          sourceName: source.name,
          channelsSeen: seen,
        );
      } else {
        final epgOutcome = await _runEpgPhase(source, channelsSeen: seen);
        state = ImportDone(
          sourceId: source.id,
          sourceName: source.name,
          stats: stats,
          summary: summary,
          epgStats: epgOutcome.$1,
          epgReport: epgOutcome.$2,
          epgFailureReason: epgOutcome.$3,
        );
        _markStatus(source.id, ok: true);
      }
    } catch (error) {
      if (_cancelRequested) {
        state = ImportCancelled(
          sourceId: source.id,
          sourceName: source.name,
          channelsSeen: seen,
        );
      } else {
        state = ImportFailed(
          sourceId: source.id,
          sourceName: source.name,
          reason: _mapImportError(error),
          channelsSeen: seen,
        );
        _markStatus(source.id, ok: false);
      }
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      _relay = null;
    }
  }

  /// Segunda fase, tras el import de canales (S5 · Ola 2, ADR-008): si
  /// [source] tiene `epgUrl` (`EpgSource.epgFor` no devuelve `null`),
  /// descarga y escribe su guía XMLTV. Devuelve `(null, null, null)` sin
  /// tocar nada más si la fuente no tiene guía.
  ///
  /// **Política de fallo**: un error aquí (red, parseo, escritura) nunca
  /// se propaga — los canales de [source] ya se importaron correctamente
  /// en la fase anterior, y tratar una guía rota como un fallo del import
  /// completo escondería un éxito real detrás de un error parcial. El
  /// tercer elemento de la tupla (`ProbeFailureReason?`) es cómo la UI se
  /// entera de que hubo un intento fallido, sin que eso mueva el estado a
  /// [ImportFailed] (ver [ImportDone.epgFailureReason]).
  ///
  /// No es cancelable a media fase (a diferencia de la importación de
  /// canales): para cuando esto arranca, los canales ya están confirmados
  /// en `data`, y [ImportController] no expone hoy un `cancel()` que
  /// alcance esta segunda fase — limitación conocida, no un descuido.
  Future<(EpgImportStats?, XmltvImportReport?, ProbeFailureReason?)>
  _runEpgPhase(Source source, {required int channelsSeen}) async {
    final XmltvParseOutcome? outcome;
    try {
      outcome = ref
          .read(epgSourceProvider)
          .epgFor(source, now: ref.read(clockProvider).now());
    } catch (error) {
      return (null, null, _mapImportError(error));
    }
    if (outcome == null) return (null, null, null);
    // Mismo motivo que `outcome.summary.ignore()` más arriba: si
    // `write()` falla porque `entries` mismo falló, `outcome.report`
    // completa con el mismo error y nunca se llega a `await`
    // lo más abajo — sin esto, Dart lo reporta como excepción sin
    // manejar aunque el catch de debajo ya lo está tratando.
    outcome.report.ignore();

    state = ImportRunning(
      sourceId: source.id,
      sourceName: source.name,
      channelsSeen: channelsSeen,
      phase: ImportPhase.epg,
    );

    try {
      final stats = await ref
          .read(xmltvEpgWriterProvider)
          .write(outcome.entries, now: ref.read(clockProvider).now());
      final report = await outcome.report;
      return (stats, report, null);
    } catch (error) {
      return (null, null, _mapImportError(error));
    }
  }

  /// Cancela el import en curso, si lo hay. No-op si no hay ninguno
  /// (`state` no es [ImportRunning]).
  void cancel() {
    final relay = _relay;
    if (relay == null) return;
    _cancelRequested = true;
    relay.addError(StateError('Import cancelado por el usuario.'));
    relay.close();
  }

  ProbeFailureReason _mapImportError(Object error) => switch (error) {
    TimeoutException() => ProbeFailureReason.timeout,
    SocketException() => ProbeFailureReason.network,
    http.ClientException() => ProbeFailureReason.network,
    FileSystemException() => ProbeFailureReason.notFound,
    HttpException() => ProbeFailureReason.malformed,
    _ => ProbeFailureReason.unknown,
  };

  /// Gestión de fuentes (ui-spec §2.10): registra el resultado ok/error del
  /// último import de esta sesión — deuda de persistencia documentada y
  /// aceptada, ver [lastImportStatusProvider].
  void _markStatus(String sourceId, {required bool ok}) {
    ref.read(lastImportStatusProvider.notifier).update(
      (map) => {...map, sourceId: ok},
    );
  }
}

final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
