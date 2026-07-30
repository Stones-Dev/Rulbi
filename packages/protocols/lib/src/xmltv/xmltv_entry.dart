import 'package:iptv_core/iptv_core.dart';

/// Un elemento emitido por [parseXmltv]: o bien un canal declarado en la
/// guía, o bien un programa dentro de la ventana temporal. Un solo stream
/// entrelazado (no dos streams separados) para que exista un único camino
/// de backpressure — con un solo productor (el isolate worker) dos streams
/// independientes obligarían al consumidor a drenar ambos a la vez o
/// arriesgarse a bufferizar sin límite el que no está escuchando.
sealed class XmltvEntry {
  const XmltvEntry();
}

final class XmltvChannelEntry extends XmltvEntry {
  const XmltvChannelEntry(this.channel);
  final XmltvChannel channel;
}

final class XmltvProgrammeEntry extends XmltvEntry {
  const XmltvProgrammeEntry(this.programme);
  final EpgProgramme programme;
}

/// Metadatos de un `<channel>` de XMLTV: vive en `protocols`, no en
/// `core` — a diferencia de [EpgProgramme] (contenido de guía, reutilizado
/// tal cual), esto no es reproducible ni `Syncable`, es vocabulario propio
/// del formato de guía (misma extensión de P6 que `ImportReport`).
final class XmltvChannel {
  const XmltvChannel({
    required this.id,
    required this.displayNames,
    this.icon,
    this.urls = const [],
  });

  /// El `id` crudo del atributo `<channel id="...">`, **sin normalizar**
  /// (ver justificación en el diseño de T1.3): es la clave de join con
  /// `Channel.tvgId`, que tampoco se normaliza.
  final String id;

  /// En el orden en que aparecen; puede haber varios `<display-name>`
  /// (uno por idioma). El primero es el que se usaría como nombre por
  /// defecto si hiciera falta mostrar uno solo.
  final List<String> displayNames;

  final Uri? icon;
  final List<Uri> urls;

  @override
  String toString() => 'XmltvChannel($id, $displayNames)';
}
