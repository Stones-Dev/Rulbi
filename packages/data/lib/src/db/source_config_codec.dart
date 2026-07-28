import 'package:iptv_core/iptv_core.dart';

/// Serialización de `SourceConfig` para la columna `configJson` de
/// `Sources`. Independiente del codec homónimo de `packages/pairing`
/// (transporte) a propósito: son formatos con motivos de cambio
/// distintos (almacenamiento vs. transferencia) y `data` no depende de
/// `pairing` (regla de dependencias, CLAUDE.md). **Nunca** incluye el
/// secreto de una fuente Xtream (P5) — vive en el almacén seguro,
/// indexado por `Source.id` (S2, `SecureCredentialStore`).
Map<String, Object?> sourceConfigToJson(SourceConfig config) =>
    switch (config) {
      M3uFileSourceConfig(:final filePath, :final epgUrl) => {
        'filePath': filePath,
        'epgUrl': ?epgUrl?.toString(),
      },
      M3uUrlSourceConfig(:final url, :final epgUrl, :final userAgent) => {
        'url': url.toString(),
        'epgUrl': ?epgUrl?.toString(),
        'userAgent': ?userAgent,
      },
      XtreamSourceConfig(:final host, :final username) => {
        'host': host.toString(),
        'username': username,
      },
    };

SourceConfig sourceConfigFromJson(String kind, Map<String, Object?> json) =>
    switch (kind) {
      'm3uFile' => M3uFileSourceConfig(
        filePath: json['filePath'] as String,
        epgUrl: _uriOrNull(json['epgUrl']),
      ),
      'm3uUrl' => M3uUrlSourceConfig(
        url: Uri.parse(json['url'] as String),
        epgUrl: _uriOrNull(json['epgUrl']),
        userAgent: json['userAgent'] as String?,
      ),
      'xtream' => XtreamSourceConfig(
        host: Uri.parse(json['host'] as String),
        username: json['username'] as String,
      ),
      _ => throw StateError('Tipo de fuente desconocido en la BD: "$kind"'),
    };

Uri? _uriOrNull(Object? value) =>
    value == null ? null : Uri.parse(value as String);
