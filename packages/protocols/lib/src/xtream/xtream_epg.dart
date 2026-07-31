import 'dart:convert';

import 'xtream_json.dart';

/// Una entrada de EPG del panel (`get_short_epg`/`get_simple_data_table`)
/// — no capturada en los 9 fixtures reales de T1.1 (esas dos actions no
/// estaban entre las pedidas), cubierta aquí con fixtures sintéticos
/// documentados contra la forma pública de la API (`xtream-ui.org`, ver
/// `test/fixtures/xtream/synthetic/README.md`).
final class XtreamEpgListing {
  const XtreamEpgListing({
    required this.id,
    required this.title,
    this.streamId,
    this.description,
    this.start,
    this.end,
  });

  final String id;
  final int? streamId;
  final String title;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  static XtreamEpgListing fromJson(Map<String, Object?> json) => XtreamEpgListing(
    id: asFlexibleString(json['id']) ?? asFlexibleString(json['epg_id']) ?? '',
    streamId: asFlexibleIntOrNull(json['stream_id']) ?? asFlexibleIntOrNull(json['channel_id']),
    title: _decodeMaybeBase64(asFlexibleString(json['title']) ?? ''),
    description: _decodeMaybeBase64OrNull(asFlexibleString(json['description'])),
    start: _parseTimestamp(json['start'], json['start_timestamp']),
    end: _parseTimestamp(json['end'], json['stop_timestamp'] ?? json['end_timestamp']),
  );

  @override
  String toString() => 'XtreamEpgListing($id, $title)';
}

/// Xtream Codes documenta `title`/`description` de `get_short_epg` en
/// base64 (`xtream-ui.org`), pero no todos los paneles lo respetan —
/// algunos mandan texto plano. Se intenta decodificar y, si falla en
/// cualquier paso (caracteres fuera del alfabeto base64, o bytes que no
/// forman UTF-8 válido tras decodificar), se emite el texto crudo tal
/// cual: nunca se lanza una excepción por un campo de EPG mal codificado
/// (P7).
String _decodeMaybeBase64(String raw) {
  if (raw.isEmpty) return raw;
  try {
    final normalized = raw.length % 4 == 0 ? raw : raw.padRight(raw.length + (4 - raw.length % 4), '=');
    return utf8.decode(base64.decode(normalized));
  } on FormatException {
    return raw;
  }
}

String? _decodeMaybeBase64OrNull(String? raw) => raw == null ? null : _decodeMaybeBase64(raw);

/// `start`/`end` como `"YYYY-MM-DD HH:mm:ss"` (forma documentada) con
/// `start_timestamp`/`stop_timestamp` (epoch, string) como respaldo si el
/// primero no parsea — algunos paneles solo mandan uno de los dos.
DateTime? _parseTimestamp(Object? textField, Object? epochField) {
  final text = asFlexibleString(textField);
  if (text != null && text.isNotEmpty) {
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed != null) return parsed;
  }
  final epoch = asFlexibleIntOrNull(epochField);
  if (epoch != null) return DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  return null;
}
