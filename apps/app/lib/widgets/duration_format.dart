import '../l10n/app_localizations.dart';

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

/// `1h 52m` si dura una hora o más, `42 min` si no — duración editorial de
/// la ficha VOD (§2.6, S6.5 paso 7, frame Figma `43:2`: "1h 52m", no
/// "180 min" como antes del rediseño). Distinto de [formatDurationShort]:
/// ese formatea *posición de reproducción* (mm:ss), este formatea
/// *duración total* como la vería un usuario en una ficha.
String formatDurationHoursMinutes(AppLocalizations l10n, Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  return hours > 0
      ? l10n.vodDetailDurationHoursMinutes(hours, minutes)
      : l10n.vodDetailDurationMinutes(minutes);
}
