import 'package:drift/drift.dart';

/// Espejo de `EpgProgramme` (`iptv_core`). Contenido de solo lectura
/// importado de XMLTV o del panel Xtream; purga automática por ventana
/// temporal (T1.3, fuera de este sprint — aquí solo el esquema y el
/// puerto de purga).
// `EpgProgrammeRow`, no `EpgProgramme`: evita colisión con la entidad
// homónima de iptv_core.
@DataClassName('EpgProgrammeRow')
@TableIndex(name: 'idx_epg_tvg_id_start', columns: {#tvgId, #start})
class EpgProgrammes extends Table {
  TextColumn get tvgId => text()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get stop => dateTime()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {tvgId, start};
}
