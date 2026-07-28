import '../entities/source.dart';

abstract interface class SourceRepository {
  Future<List<Source>> getAll();
  Future<Source?> getById(String id);

  /// Inserta o reemplaza por completo. Quien construye el [Source] decide
  /// `updatedAt`/`deletedAt` (normalmente vía [Clock]) — el repositorio no
  /// añade lógica de negocio, solo persiste.
  Future<void> upsert(Source source);

  Stream<List<Source>> watchAll();
}
