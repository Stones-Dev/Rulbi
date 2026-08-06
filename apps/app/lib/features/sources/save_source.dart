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

/// Orquesta el alta **y la edición** de una fuente (alta: S4 · Ola 2;
/// edición: S4 · Ola 3, Gestión de fuentes). Deliberadamente **no** llama
/// a `ManageSources.addSource`/`refreshSource` — esos casos de uso exigen
/// un `Stream<Channel>` real, que es la importación completa (Ola 3, "UI
/// de importación", `ImportController`). Aquí solo se registra la fuente;
/// en alta queda con `lastRefresh == null` ("nunca actualizada"), el
/// estado exacto que la UI de importación usa para saber que toca
/// importar.
///
/// Orden de escritura para Xtream (con [secret] no nulo): el secreto va al
/// almacén seguro **antes** que el upsert de la fuente — si el upsert
/// falla después, se compensa (en alta, borrando el secreto recién
/// guardado; en edición, restaurando el que había antes) para no dejar
/// contraseñas huérfanas ni corrompidas (P5). La contraseña nunca entra en
/// [Source]/`XtreamSourceConfig` (ADR-006) — solo se recibe aquí para
/// pasarla al almacén seguro.
///
/// **Edición, P5**: se pasa [existing] para editar una fuente ya creada.
/// `secret == null` en modo edición significa "sin cambios" — el almacén
/// seguro **no se toca**, igual que el patrón estándar de "campo de
/// contraseña vacío = no reemplazar" que usa `XtreamSourceForm` (nunca se
/// lee la contraseña del almacén para precargarla en el campo). `id`,
/// `enabled` y `lastRefresh` de [existing] se conservan; solo cambian
/// `config`/`name`/`refreshPolicy` (los campos que el formulario edita) y
/// `updatedAt` (el reloj de esta escritura).
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
    Source? existing,
  }) async {
    if (await _hasDuplicateName(name, excludingId: existing?.id)) {
      return const SaveSourceFailed(SaveSourceFailureReason.duplicateName);
    }

    final id = existing?.id ?? _generateId();

    // Solo en edición hace falta poder restaurar: en alta no había nada
    // que perder si el upsert falla (la compensación es simplemente
    // borrar lo recién escrito).
    String? previousSecret;
    if (secret != null) {
      if (existing != null) {
        previousSecret = await secureStore.read(id);
      }
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
      enabled: existing?.enabled ?? true,
      lastRefresh: existing?.lastRefresh,
      refreshPolicy: refreshPolicy,
    );

    try {
      await sources.upsert(source);
    } catch (_) {
      if (secret != null) {
        if (existing != null && previousSecret != null) {
          await secureStore.save(id, previousSecret);
        } else {
          await secureStore.delete(id);
        }
      }
      return const SaveSourceFailed(SaveSourceFailureReason.persistFailed);
    }

    return SaveSourceOk(source);
  }

  Future<bool> _hasDuplicateName(String name, {String? excludingId}) async {
    final normalized = normalizeForMatching(name);
    final existing = await sources.getAll();
    return existing.any(
      (s) =>
          !s.isDeleted &&
          s.id != excludingId &&
          normalizeForMatching(s.name) == normalized,
    );
  }
}
