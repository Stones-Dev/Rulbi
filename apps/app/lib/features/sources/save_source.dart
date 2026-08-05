import 'package:iptv_core/iptv_core.dart';
import 'package:uuid/uuid.dart';

/// Resultado tipado de [SaveSource.call] — mismo espíritu que
/// `ProbeResult`: nunca se construye una cadena de usuario aquí, la UI
/// traduce [SaveSourceFailureReason] vía `AppLocalizations`.
sealed class SaveSourceResult {
  const SaveSourceResult();
}

final class SaveSourceOk extends SaveSourceResult {
  const SaveSourceOk(this.source);
  final Source source;
}

enum SaveSourceFailureReason { duplicateName, secretStoreFailed, persistFailed }

final class SaveSourceFailed extends SaveSourceResult {
  const SaveSourceFailed(this.reason);
  final SaveSourceFailureReason reason;
}

/// Orquesta el alta de una fuente nueva (S4 · Ola 2: Formularios M3U y
/// Xtream). Deliberadamente **no** llama a `ManageSources.addSource` — ese
/// caso de uso exige un `Stream<Channel>` real, que es la importación
/// completa (Ola 3, "UI de importación"). Aquí solo se registra la fuente
/// con `lastRefresh == null` ("nunca actualizada"), el estado exacto que
/// la pantalla de Ola 3 usará para saber que toca importar.
///
/// Orden de escritura para Xtream (con [secret] no nulo): el secreto va al
/// almacén seguro **antes** que el upsert de la fuente — si el upsert
/// falla después, se compensa borrando el secreto recién guardado, para
/// no dejar contraseñas huérfanas sin ninguna fuente que las referencie
/// (P5). La contraseña nunca entra en [Source]/`XtreamSourceConfig`
/// (ADR-006) — solo se recibe aquí para pasarla al almacén seguro.
final class SaveSource {
  SaveSource({
    required this.sources,
    required this.secureStore,
    required this.clock,
    this._generateId = _defaultGenerateId,
  });

  final SourceRepository sources;
  final SecureCredentialStore secureStore;
  final Clock clock;
  final String Function() _generateId;

  static const Uuid _uuid = Uuid();
  static String _defaultGenerateId() => _uuid.v4();

  Future<SaveSourceResult> call({
    required String name,
    required SourceConfig config,
    required SourceRefreshPolicy refreshPolicy,
    String? secret,
  }) async {
    if (await _hasDuplicateName(name)) {
      return const SaveSourceFailed(SaveSourceFailureReason.duplicateName);
    }

    final id = _generateId();

    if (secret != null) {
      try {
        await secureStore.save(id, secret);
      } catch (_) {
        return const SaveSourceFailed(SaveSourceFailureReason.secretStoreFailed);
      }
    }

    final source = Source(
      id: id,
      config: config,
      name: name,
      updatedAt: clock.now(),
      refreshPolicy: refreshPolicy,
    );

    try {
      await sources.upsert(source);
    } catch (_) {
      if (secret != null) {
        await secureStore.delete(id);
      }
      return const SaveSourceFailed(SaveSourceFailureReason.persistFailed);
    }

    return SaveSourceOk(source);
  }

  Future<bool> _hasDuplicateName(String name) async {
    final normalized = normalizeForMatching(name);
    final existing = await sources.getAll();
    return existing.any(
      (s) => !s.isDeleted && normalizeForMatching(s.name) == normalized,
    );
  }
}
