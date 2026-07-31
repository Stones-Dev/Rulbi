import 'xtream_json.dart';

/// Una categoría cruda de `get_live_categories`/`get_vod_categories`/
/// `get_series_categories` — DTO de protocolo, no `core.Category`: la
/// conversión (que necesita `sourceId` y un `ContentType`, ninguno de los
/// cuales conoce esta acción) vive en `XtreamMapper` (ver
/// `xtream_mapper.dart`), reutilizada por `importChannels()`.
final class XtreamCategory {
  const XtreamCategory({required this.id, required this.name, required this.parentId});

  /// `category_id` — string en todos los fixtures reales de T1.1, pero se
  /// tolera también numérico (dialecto observado en paneles de terceros).
  final String id;
  final String name;

  /// `parent_id` — `0` significa "sin padre" en Xtream (no hay `null`).
  /// Xtream Codes no anida categorías realmente en la práctica (el campo
  /// existe en la especificación pero ningún panel observado lo usa para
  /// jerarquías reales); se conserva tal cual, sin construir un árbol.
  final int parentId;

  static XtreamCategory fromJson(Map<String, Object?> json) => XtreamCategory(
    id: asFlexibleString(json['category_id']) ?? '',
    name: asFlexibleString(json['category_name']) ?? '',
    parentId: asFlexibleInt(json['parent_id']),
  );

  @override
  String toString() => 'XtreamCategory($id, $name)';
}
