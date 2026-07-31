import 'xtream_json.dart';

/// Un canal live crudo de `get_live_streams` — DTO de protocolo. La
/// conversión a `core.Channel` (que necesita `sourceId` y la URL canónica
/// de ADR-006) vive en `XtreamMapper.liveStreamToChannel`.
final class XtreamLiveStream {
  const XtreamLiveStream({
    required this.streamId,
    required this.name,
    required this.categoryId,
    this.epgChannelId,
    this.streamIcon,
    this.hasTvArchive = false,
  });

  /// `stream_id` — estable dentro de un panel (no global, ver
  /// `ChannelRef`/ADR-003), siempre entero en los fixtures observados.
  final int streamId;
  final String name;
  final String? categoryId;

  /// `epg_channel_id` — el `tvg-id` equivalente de Xtream; primera
  /// prioridad de la cascada de `ChannelRef.derive` cuando no está vacío.
  final String? epgChannelId;

  /// `stream_icon` — `null`/ausente/`""` son formas reales observadas en
  /// el mismo fixture (T1.1: dos canales, uno con icono y otro sin).
  final String? streamIcon;

  final bool hasTvArchive;

  static XtreamLiveStream fromJson(Map<String, Object?> json) => XtreamLiveStream(
    streamId: asFlexibleInt(json['stream_id']),
    name: asFlexibleString(json['name']) ?? '',
    categoryId: asFlexibleString(json['category_id']),
    epgChannelId: nonEmptyOrNull(asFlexibleString(json['epg_channel_id'])),
    streamIcon: nonEmptyOrNull(asFlexibleString(json['stream_icon'])),
    hasTvArchive: asFlexibleBool(json['tv_archive']),
  );

  @override
  String toString() => 'XtreamLiveStream($streamId, $name)';
}

/// `null`/`""` se tratan igual en la mayoría de campos opcionales de
/// Xtream (icono, epg id, extensión de contenedor) — un panel que manda
/// cadena vacía en vez de omitir el campo es un dialecto real, no una
/// excepción (fixture de T1.1: `stream_icon: null` en un canal,
/// simplemente ausente sería equivalente).
String? nonEmptyOrNull(String? value) => (value == null || value.isEmpty) ? null : value;
