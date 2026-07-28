/// Contrato de las entidades transferibles (plan §4.2): las únicas que
/// viajan en el paquete de configuración de `pairing` y que participan en
/// el merge last-write-wins de la sync automática (ADR-002 / ADR-003).
///
/// `Category`, `Channel` y `EpgProgramme` NO implementan esta interfaz:
/// se derivan de la fuente en cada refresco, así que no tiene sentido
/// resolver conflictos sobre ellas — se reconstruyen, no se fusionan.
///
/// Es un `mixin`, no una `interface class`: `implements` en Dart nunca
/// hereda código, solo la firma — así que la implementación por defecto
/// de [isDeleted] necesita que las entidades hagan `with Syncable` para
/// aprovecharla sin repetirla en cada clase.
mixin Syncable {
  /// Última modificación de este registro, en cualquier dispositivo que lo
  /// haya escrito. Es la base del criterio "last-write-wins".
  DateTime get updatedAt;

  /// `null` mientras el registro está vivo. No nulo marca un tombstone: un
  /// borrado que debe propagarse al resto de dispositivos emparejados en
  /// vez de simplemente desaparecer — que un merge interpretaría como
  /// "nunca existió" y lo resucitaría desde el otro lado.
  DateTime? get deletedAt;

  bool get isDeleted => deletedAt != null;
}
