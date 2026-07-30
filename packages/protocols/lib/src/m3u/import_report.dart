/// Resultado de tolerancia de una importación M3U (P7): nunca se lanza una
/// excepción por una línea rota — se cuenta y se reporta al final. Vive en
/// `protocols`, no en `core`: el dominio no tiene por qué conocer
/// vocabulario de fallos de parseo específico de M3U (extensión de P6).
final class ImportReport {
  const ImportReport({required this.parsed, required this.discarded});

  /// Número de canales emitidos con éxito.
  final int parsed;

  /// Líneas descartadas, en el orden en que aparecieron en el origen.
  final List<DiscardedLine> discarded;

  /// Serialización estable (T1.9): claves en orden fijo — no depende de
  /// `Map`/`hashCode` de ningún objeto Dart, así que el mismo informe
  /// produce siempre el mismo JSON entre corridas y versiones del SDK.
  /// `kind: 'm3u'` es el discriminador que la UI de Fase 2 usa para
  /// distinguir esta mitad del informe de la de `XmltvImportReport`
  /// dentro del sobre compuesto (`docs/import-report-schema.md`).
  Map<String, Object?> toJson() => {
    'kind': 'm3u',
    'parsed': parsed,
    'discardedCount': discarded.length,
    'discarded': [for (final line in discarded) line.toJson()],
  };

  factory ImportReport.fromJson(Map<String, Object?> json) => ImportReport(
    parsed: json['parsed'] as int,
    discarded: [
      for (final entry in json['discarded'] as List)
        DiscardedLine.fromJson(entry as Map<String, Object?>),
    ],
  );

  @override
  String toString() =>
      'ImportReport(parsed: $parsed, discarded: ${discarded.length})';
}

/// Una línea del M3U de origen que no se pudo asociar a ningún canal válido.
final class DiscardedLine {
  const DiscardedLine({
    required this.lineNumber,
    required this.rawLine,
    required this.reason,
  });

  /// 1-based, tal como aparece en el archivo de origen.
  final int lineNumber;
  final String rawLine;
  final String reason;

  Map<String, Object?> toJson() => {
    'lineNumber': lineNumber,
    'rawLine': rawLine,
    'reason': reason,
  };

  factory DiscardedLine.fromJson(Map<String, Object?> json) => DiscardedLine(
    lineNumber: json['lineNumber'] as int,
    rawLine: json['rawLine'] as String,
    reason: json['reason'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is DiscardedLine &&
      other.lineNumber == lineNumber &&
      other.rawLine == rawLine &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(lineNumber, rawLine, reason);

  @override
  String toString() => 'DiscardedLine(#$lineNumber: $reason)';
}
