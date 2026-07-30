/// Informe de tolerancia de una importación XMLTV (P7): nunca se lanza una
/// excepción por una entrada rota — se cuenta y se reporta al final. No
/// reutiliza `ImportReport`/`DiscardedLine` de M3U a propósito (ver diseño
/// de T1.3): un parser de eventos por chunks no puede dar un número de
/// línea honesto, y XMLTV necesita contadores (fuera de ventana, refs de
/// canal desconocidas) que en la forma de lista de M3U reventarían la
/// memoria con un XMLTV real de cientos de MB — que es precisamente el
/// problema que esta tarea existe para evitar.
final class XmltvImportReport {
  const XmltvImportReport({
    required this.parsedChannels,
    required this.parsedProgrammes,
    required this.outOfWindowProgrammes,
    required this.assumedUtcDates,
    required this.unknownChannelRefs,
    required this.unknownTags,
    required this.discardedCount,
    required this.discarded,
    required this.discardedTruncated,
  });

  /// Número de `<channel>` emitidos con éxito.
  final int parsedChannels;

  /// Número de `<programme>` emitidos con éxito (dentro de ventana).
  final int parsedProgrammes;

  /// Programas bien formados pero fuera de [XmltvWindow] — no son un
  /// descarte (P7: no hay nada "malo" en ellos), por eso es un contador
  /// y no una lista: con un XMLTV real, casi todo el archivo cae aquí.
  final int outOfWindowProgrammes;

  /// Programas emitidos cuya fecha no traía offset horario (se asumió
  /// UTC). Se emiten igual — el dato es útil aunque incompleto — pero se
  /// cuenta para que quien revise el informe sepa que hay incertidumbre.
  final int assumedUtcDates;

  /// `channel` de un `<programme>` que no aparece declarado en ningún
  /// `<channel>` del propio XMLTV. El programa se emite igual: el join
  /// real de producción es contra los `tvg-id` del M3U, no contra esta
  /// lista — un XMLTV parcial o desordenado no debería perder datos por
  /// esto. Clave = id de canal, valor = nº de programas afectados.
  final Map<String, int> unknownChannelRefs;

  /// Etiquetas `#EXT*`-equivalentes de XMLTV (hijos de `<tv>` que no son
  /// `<channel>` ni `<programme>`, o hijos desconocidos dentro de uno de
  /// esos dos) que se ignoraron. Clave = nombre de la etiqueta.
  final Map<String, int> unknownTags;

  /// Total real de entradas descartadas (mal formadas), incluso si
  /// supera el tamaño de [discarded].
  final int discardedCount;

  /// Los primeros [XmltvImportReport.discardedCap] descartes, en el orden
  /// en que aparecieron. A diferencia de [outOfWindowProgrammes], esto sí
  /// son fallos reales de parseo — se espera que sean pocos, así que una
  /// lista acotada es segura.
  final List<XmltvDiscard> discarded;

  /// `true` si [discardedCount] superó el tamaño de [discarded].
  final bool discardedTruncated;

  static const int discardedCap = 1000;

  @override
  String toString() =>
      'XmltvImportReport(channels: $parsedChannels, '
      'programmes: $parsedProgrammes, outOfWindow: $outOfWindowProgrammes, '
      'discarded: $discardedCount)';
}

/// Una entrada (`<channel>` o `<programme>`) que no se pudo emitir.
final class XmltvDiscard {
  const XmltvDiscard({
    required this.entryIndex,
    required this.reason,
    this.charOffset,
    this.channelId,
    this.rawSnippet = '',
  });

  /// Ordinal 0-based del `<channel>`/`<programme>` dentro del documento
  /// (no un número de línea: un parser de eventos por chunks no puede dar
  /// uno honesto). Reproducible entre corridas del mismo archivo.
  final int entryIndex;

  /// Offset de carácter en el documento decodificado, si `withLocation`
  /// lo proporcionó para este evento.
  final int? charOffset;

  final String? channelId;

  /// Recorte del contenido crudo relevante, acotado a un tamaño legible.
  final String rawSnippet;

  final String reason;

  @override
  String toString() => 'XmltvDiscard(#$entryIndex: $reason)';
}
