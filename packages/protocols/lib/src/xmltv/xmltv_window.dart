/// Ventana temporal aplicada **durante** el parseo XMLTV (T1.3, tasks.md):
/// un programa fuera de rango se descarta al vuelo y solo incrementa un
/// contador (`XmltvImportReport.outOfWindowProgrammes`), nunca entra en
/// una lista — con un XMLTV de cientos de MB, una lista de "todo lo que
/// cayó fuera de ventana" sería justo el problema de memoria que esta
/// tarea existe para evitar.
final class XmltvWindow {
  const XmltvWindow({required this.from, required this.to});

  /// Ventana por defecto del producto: [now−1d, now+7d] (spec HU-03 /
  /// tasks.md T1.3 — "Ventana y purga EPG" corrige el borrador inicial de
  /// −6h a −1d). Inyectable a propósito: el parser nunca llama a
  /// `DateTime.now()` por su cuenta, para que un test pueda fijar una
  /// ventana determinista.
  factory XmltvWindow.around(DateTime now) => XmltvWindow(
    from: now.subtract(const Duration(days: 1)),
    to: now.add(const Duration(days: 7)),
  );

  final DateTime from;
  final DateTime to;

  /// Un programa [start, stop) se conserva si solapa la ventana
  /// [from, to). Los bordes son excluyentes por ambos lados: un programa
  /// que termina exactamente en `from` ya pasó del todo, y uno que
  /// empieza exactamente en `to` todavía no ha llegado.
  bool overlaps({required DateTime start, required DateTime stop}) =>
      stop.isAfter(from) && start.isBefore(to);
}
