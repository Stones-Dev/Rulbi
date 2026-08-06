import 'package:iptv_app/features/sources/import_controller.dart';
import 'package:iptv_app/features/sources/m3u_probe.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/xtream_probe.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

/// Dobles compartidos entre `save_source_test.dart` y los tests de los dos
/// formularios (M3U/Xtream) — S4 · Ola 2. Viven en `_helpers/` (prefijo
/// `_`, como ya hace `packages/protocols` con sus núcleos internos) para
/// que ningún test los confunda con un archivo de casos.

/// [SourceRepository] en memoria. `upsert` puede configurarse para fallar
/// (`failUpsert`) — necesario para probar la compensación de
/// `SaveSource` cuando el guardado del secreto ya tuvo éxito.
final class FakeSourceRepository implements SourceRepository {
  final Map<String, Source> _byId = {};
  bool failUpsert = false;

  List<Source> get savedSources => _byId.values.toList();

  @override
  Future<List<Source>> getAll() async => _byId.values.toList();

  @override
  Future<Source?> getById(String id) async => _byId[id];

  @override
  Future<void> upsert(Source source) async {
    if (failUpsert) {
      throw StateError('upsert forzado a fallar (fixture de test)');
    }
    _byId[source.id] = source;
  }

  @override
  Stream<List<Source>> watchAll() => Stream.value(_byId.values.toList());
}

/// [SecureCredentialStore] en memoria. `failSave`/`failDelete` permiten
/// forzar cada rama de error que `SaveSource` debe manejar.
final class FakeSecureCredentialStore implements SecureCredentialStore {
  final Map<String, String> _secrets = {};
  bool failSave = false;

  Map<String, String> get secrets => Map.unmodifiable(_secrets);

  @override
  Future<void> save(String sourceId, String secret) async {
    if (failSave) {
      throw StateError('save forzado a fallar (fixture de test)');
    }
    _secrets[sourceId] = secret;
  }

  @override
  Future<String?> read(String sourceId) async => _secrets[sourceId];

  @override
  Future<void> delete(String sourceId) async {
    _secrets.remove(sourceId);
  }
}

/// [Clock] fijo y determinista, con `id` inyectable para no depender de
/// `Uuid` real en los tests (aserciones exactas sobre el `Source`
/// construido).
final class FixedClock implements Clock {
  const FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

/// [M3uProbe] con resultado fijo, inyectable por test — evita red real y
/// permite forzar tanto el camino de éxito como cada motivo de fallo.
final class FakeM3uProbe implements M3uProbe {
  FakeM3uProbe(this.result);
  final ProbeResult<M3uProbeSummary> result;

  Uri? lastProbedUrl;
  String? lastUserAgent;
  String? lastProbedFilePath;

  @override
  Future<ProbeResult<M3uProbeSummary>> probeUrl(Uri url, {String? userAgent}) async {
    lastProbedUrl = url;
    lastUserAgent = userAgent;
    return result;
  }

  @override
  Future<ProbeResult<M3uProbeSummary>> probeFile(String filePath) async {
    lastProbedFilePath = filePath;
    return result;
  }
}

/// [XtreamProbe] con resultado fijo, inyectable por test.
final class FakeXtreamProbe implements XtreamProbe {
  FakeXtreamProbe(this.result);
  final ProbeResult<XtreamProbeSummary> result;

  Uri? lastHost;
  String? lastUsername;
  String? lastPassword;

  @override
  Future<ProbeResult<XtreamProbeSummary>> probe({
    required Uri host,
    required String username,
    required String password,
  }) async {
    lastHost = host;
    lastUsername = username;
    lastPassword = password;
    return result;
  }
}

/// [ChannelRepository] en memoria para `ImportController` (S4 · Ola 3): un
/// `await for` real sobre el stream que le pasa `ManageSources`, así que
/// propaga sus errores exactamente igual que `DriftChannelRepository`. Solo
/// "confirma" en [importedChannels] si el stream termina sin error —
/// mismo criterio de todo-o-nada que la transacción real de drift
/// (`_db.transaction()`, ver `packages/data/.../channel_repository.dart`):
/// un error a mitad de stream no debe dejar canales a medias persistidos.
final class FakeChannelRepository implements ChannelRepository {
  final List<Channel> importedChannels = [];
  int importCalls = 0;

  @override
  Future<SourceImportStats> importSourceContent(
    String sourceId,
    Stream<Channel> channels, {
    required DateTime now,
  }) async {
    importCalls++;
    final buffer = <Channel>[];
    await for (final channel in channels) {
      buffer.add(channel);
    }
    importedChannels.addAll(buffer); // "commit": solo si el stream no falló
    return SourceImportStats(
      inserted: buffer.length,
      updated: 0,
      unchanged: 0,
      tombstoned: 0,
      resurrected: 0,
      duplicateRefs: 0,
    );
  }

  @override
  Future<List<Category>> categoriesFor(String sourceId) async => const [];

  @override
  Stream<List<Channel>> watchChannels({required String categoryId}) =>
      const Stream.empty();

  @override
  Future<int> countBySource(String sourceId) async =>
      importedChannels.length;

  @override
  Future<int> purgeOrphanTombstones({required DateTime deletedBefore}) async =>
      0;
}

/// [ImportChannelSource] con stream/informe fijos, inyectable por test —
/// evita red/isolate real y permite forzar tanto el camino de éxito como
/// un stream que falla a mitad de emisión.
final class FakeImportChannelSource implements ImportChannelSource {
  FakeImportChannelSource({required this.channels, ImportSummary? summary})
    : summary = summary ?? const M3uImportSummary(ImportReport(parsed: 0, discarded: []));

  final Stream<Channel> channels;
  final ImportSummary summary;

  Source? lastSource;
  String? lastPassword;

  @override
  ImportChannels channelsFor(Source source, {String? password}) {
    lastSource = source;
    lastPassword = password;
    return ImportChannels(channels: channels, summary: Future.value(summary));
  }
}
