import 'package:iptv_core/iptv_core.dart';

/// Resultado tipado de [DeleteSource.call] — mismo espíritu que
/// `SaveSourceResult`: nunca se construye una cadena de usuario aquí, la
/// UI traduce [DeleteSourceFailureReason] vía `AppLocalizations`.
sealed class DeleteSourceResult {
  const DeleteSourceResult();
}

final class DeleteSourceOk extends DeleteSourceResult {
  const DeleteSourceOk();
}

enum DeleteSourceFailureReason { notFound, persistFailed }

final class DeleteSourceFailed extends DeleteSourceResult {
  const DeleteSourceFailed(this.reason);
  final DeleteSourceFailureReason reason;
}

/// Borra una fuente (Gestión de fuentes, S4 · Ola 3, ui-spec §2.10):
/// tombstone (`Source.markDeleted`, ADR-003), **no** un `DELETE` — la
/// fuente sigue existiendo como registro tumbado para que el merge LWW de
/// `pairing` (F4) pueda propagar el borrado a otros dispositivos en vez de
/// que un dispositivo desactualizado la resucite sin querer.
///
/// **P5**: si la fuente es Xtream, borra también su secreto del almacén
/// seguro (`SecureCredentialStore.delete`) — sin esto quedaría una
/// contraseña huérfana sin ninguna fuente viva que la referencie. Para
/// M3U (sin secreto) no se toca el almacén.
final class DeleteSource {
  DeleteSource({
    required this.sources,
    required this.secureStore,
    required this.clock,
  });

  final SourceRepository sources;
  final SecureCredentialStore secureStore;
  final Clock clock;

  Future<DeleteSourceResult> call(String sourceId) async {
    final existing = await sources.getById(sourceId);
    if (existing == null || existing.isDeleted) {
      return const DeleteSourceFailed(DeleteSourceFailureReason.notFound);
    }

    try {
      await sources.upsert(existing.markDeleted(clock.now()));
    } catch (_) {
      return const DeleteSourceFailed(DeleteSourceFailureReason.persistFailed);
    }

    if (existing.kind == SourceKind.xtream) {
      await secureStore.delete(sourceId);
    }

    return const DeleteSourceOk();
  }
}
