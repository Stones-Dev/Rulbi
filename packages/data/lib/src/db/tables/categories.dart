import 'package:drift/drift.dart';

/// Espejo de `Category` (`iptv_core`). No lleva tombstone: se deriva de
/// la fuente en cada refresco (T1.5, plan §4.2).
// `CategoryRow`, no `Category`: evita colisión con la entidad
// `Category` de iptv_core.
@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text()();
  TextColumn get contentType => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
