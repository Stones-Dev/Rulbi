import 'package:iptv_app/features/sources/m3u_probe.dart';
import 'package:iptv_app/features/sources/probe_result.dart';
import 'package:iptv_app/features/sources/xtream_probe.dart';
import 'package:iptv_core/iptv_core.dart';

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
