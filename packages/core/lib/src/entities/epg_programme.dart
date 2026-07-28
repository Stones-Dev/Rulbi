/// Un programa de la guía EPG (plan §4.2). No implementa [Syncable]: es
/// contenido de solo lectura importado de una fuente XMLTV o del panel
/// Xtream, con purga automática por ventana temporal (T1.3).
final class EpgProgramme {
  const EpgProgramme({
    required this.tvgId,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
  });

  final String tvgId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;

  bool isAiringAt(DateTime instant) =>
      !instant.isBefore(start) && instant.isBefore(stop);

  @override
  bool operator ==(Object other) =>
      other is EpgProgramme &&
      other.tvgId == tvgId &&
      other.start == start &&
      other.stop == stop &&
      other.title == title &&
      other.description == description;

  @override
  int get hashCode => Object.hash(tvgId, start, stop, title, description);

  @override
  String toString() => 'EpgProgramme($title, $tvgId, $start–$stop)';
}
