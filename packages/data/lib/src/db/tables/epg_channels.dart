import 'package:drift/drift.dart';

/// `<channel>` de una guía XMLTV (ADR-008 §Decisión 2): display-names,
/// icono y URLs propios del proveedor de guía — pueden diferir de los del
/// canal importado por M3U/Xtream (`Channels`), así que se conservan
/// aparte en vez de asumir que son intercambiables. Contenido de solo
/// lectura, igual que `EpgProgrammes`: lo puebla el escritor XMLTV→drift,
/// nunca el usuario.
// `EpgChannelRow`, no `EpgChannel`: evita colisión con `XmltvChannel`
// (`packages/protocols`, vocabulario del formato de origen, P6) y con un
// futuro tipo de dominio si `core` llegara a necesitar uno.
@DataClassName('EpgChannelRow')
class EpgChannels extends Table {
  /// PK simple (no compuesta): a diferencia de `EpgProgrammes`
  /// `(tvgId, start)`, aquí `tvgId` ya identifica la fila — un `<channel>`
  /// por id de guía. Una PK no-`INTEGER` en SQLite ya crea su índice único
  /// (ADR-008: "indexada por tvgId"), así que no hace falta un
  /// `@TableIndex` adicional.
  TextColumn get tvgId => text()();

  /// Lista de `<display-name>` en el orden en que aparecen en el XMLTV
  /// (puede haber varios, uno por idioma), serializada como JSON — se lee
  /// entera, nunca se consulta por elemento, así que una tabla hija sería
  /// coste sin beneficio (misma decisión que `Channels.metadataJson`).
  TextColumn get displayNamesJson => text()();

  TextColumn get icon => text().nullable()();

  /// Lista de URLs del `<channel>` (streams alternativos declarados en la
  /// guía), mismo criterio de serialización que [displayNamesJson].
  TextColumn get urlsJson => text()();

  @override
  Set<Column> get primaryKey => {tvgId};
}
