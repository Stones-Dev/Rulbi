/// `h:mm:ss` si dura una hora o más, `mm:ss` si no — compartido por el
/// overlay del reproductor (§2.13: reloj/posición) y las fichas VOD/Serie
/// (§2.6/§2.7: "Continuar (mm:ss)"/duración de episodio), para no
/// triplicar el mismo formateo en tres sitios (S6).
String formatDurationShort(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
