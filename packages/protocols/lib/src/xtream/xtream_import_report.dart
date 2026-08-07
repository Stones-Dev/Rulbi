/// Informe de tolerancia de `XtreamClient.importChannels()` (T1.9,
/// extendido a Xtream en T1.4): mismo espíritu que `ImportReport` (M3U) y
/// `XmltvImportReport` (XMLTV) — nunca se lanza una excepción por una
/// action que falla o vuelve vacía, se cuenta y se reporta. No reutiliza
/// las clases de M3U/XMLTV a propósito (P6: cada capa de protocolo
/// describe sus propios fallos; `core` no conoce ninguna de las tres).
///
/// **Alcance de `discarded`**: solo cubre fallos a nivel de *acción*
/// (`liveCategories()`/`vodCategories()`/`liveStreams()`/`vodStreams()`
/// devolviendo `XtreamErr`, p. ej. un 500 a mitad de import) — no entradas
/// individuales dentro de una lista ya bien formada. Los 9 fixtures
/// reales de T1.1 y la batería de dialectos de T1.4 ya verifican que
/// `XtreamLiveStream.fromJson`/`XtreamVodStream.fromJson` nunca lanzan y
/// siempre producen un valor con sus propios defaults tolerantes; la única
/// entrada que de verdad se pierde sin dejar rastro es un elemento del
/// array que no sea un objeto JSON (`{}`/`[]` anidado donde se esperaba un
/// stream) — no observado en ningún panel real ni documentado como
/// dialecto conocido. Si algún día aparece, entra por P7: fixture primero.
final class XtreamImportReport {
  const XtreamImportReport({
    required this.parsedLive,
    required this.parsedVod,
    required this.parsedSeries,
    required this.discardedCount,
    required this.discarded,
  });

  /// Número de `Channel(type: live)` emitidos con éxito.
  final int parsedLive;

  /// Número de `Channel(type: vod)` emitidos con éxito.
  final int parsedVod;

  /// Número de `Channel(type: series)` del **catálogo** emitidos con éxito
  /// (S5.5, Bloque C) — series sin expandir (sin temporadas/episodios, ver
  /// `XtreamMapper.seriesToChannel`). Los episodios individuales, pedidos
  /// bajo demanda vía `seriesInfo()`, no entran en ningún import completo
  /// y por tanto no cuentan aquí.
  final int parsedSeries;

  /// Total real de acciones que fallaron, incluso si supera el tamaño de
  /// [discarded] (mismo criterio de cap que `XmltvImportReport`).
  final int discardedCount;

  final List<XtreamDiscard> discarded;

  static const int discardedCap = 1000;

  /// Serialización estable (T1.9): claves en orden fijo. `kind: 'xtream'`
  /// es el tercer discriminador del sobre compuesto, junto a `m3u` y
  /// `xmltv` (`docs/import-report-schema.md`).
  Map<String, Object?> toJson() => {
    'kind': 'xtream',
    'parsedLive': parsedLive,
    'parsedVod': parsedVod,
    'parsedSeries': parsedSeries,
    'discardedCount': discardedCount,
    'discarded': [for (final d in discarded) d.toJson()],
  };

  factory XtreamImportReport.fromJson(Map<String, Object?> json) => XtreamImportReport(
    parsedLive: json['parsedLive'] as int,
    parsedVod: json['parsedVod'] as int,
    parsedSeries: json['parsedSeries'] as int,
    discardedCount: json['discardedCount'] as int,
    discarded: [
      for (final entry in json['discarded'] as List)
        XtreamDiscard.fromJson(entry as Map<String, Object?>),
    ],
  );

  @override
  String toString() =>
      'XtreamImportReport(live: $parsedLive, vod: $parsedVod, series: $parsedSeries, '
      'discarded: $discardedCount)';
}

/// Una acción de `importChannels()` que falló por completo (a diferencia
/// de un campo individual tolerado dentro de un `fromJson`).
final class XtreamDiscard {
  const XtreamDiscard({required this.action, required this.reason});

  /// Nombre de la action de `player_api.php` que falló
  /// (`get_live_categories`, `get_live_streams`, ...).
  final String action;
  final String reason;

  Map<String, Object?> toJson() => {'action': action, 'reason': reason};

  factory XtreamDiscard.fromJson(Map<String, Object?> json) =>
      XtreamDiscard(action: json['action'] as String, reason: json['reason'] as String);

  @override
  String toString() => 'XtreamDiscard($action: $reason)';
}
