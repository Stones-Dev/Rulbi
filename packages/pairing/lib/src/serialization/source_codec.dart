import 'package:iptv_core/iptv_core.dart';

/// Lanzada al leer un `SourceConfig` con un `kind` que esta versión de la
/// app no reconoce (una versión futura habrá añadido un tipo de fuente
/// nuevo). Distinto de un campo desconocido *dentro* de un `kind`
/// conocido — eso se ignora sin más, como el resto del paquete.
final class UnknownSourceKindException implements Exception {
  UnknownSourceKindException(this.kind);
  final String kind;

  @override
  String toString() => 'Tipo de fuente desconocido: "$kind"';
}

extension SourceConfigCodec on SourceConfig {
  Map<String, Object?> toJson() => switch (this) {
        M3uFileSourceConfig(:final filePath, :final epgUrl) => {
            'kind': 'm3uFile',
            'filePath': filePath,
            'epgUrl': ?epgUrl?.toString(),
          },
        M3uUrlSourceConfig(:final url, :final epgUrl, :final userAgent) => {
            'kind': 'm3uUrl',
            'url': url.toString(),
            'epgUrl': ?epgUrl?.toString(),
            'userAgent': ?userAgent,
          },
        XtreamSourceConfig(:final host, :final username) => {
            'kind': 'xtream',
            'host': host.toString(),
            'username': username,
          },
      };
}

SourceConfig sourceConfigFromJson(Map<String, Object?> json) {
  final kind = json['kind'] as String?;
  return switch (kind) {
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
    _ => throw UnknownSourceKindException(kind ?? '<null>'),
  };
}

extension SourceCodec on Source {
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        if (lastRefresh != null) 'lastRefresh': lastRefresh!.toIso8601String(),
        'refreshPolicy': refreshPolicy.name,
        'updatedAt': updatedAt.toIso8601String(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toIso8601String(),
        'config': config.toJson(),
      };
}

Source sourceFromJson(Map<String, Object?> json) => Source(
      id: json['id'] as String,
      name: json['name'] as String,
      enabled: json['enabled'] as bool? ?? true,
      lastRefresh: _dateOrNull(json['lastRefresh']),
      refreshPolicy: SourceRefreshPolicy.values.byName(
        json['refreshPolicy'] as String? ?? 'manual',
      ),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: _dateOrNull(json['deletedAt']),
      config: sourceConfigFromJson(json['config'] as Map<String, Object?>),
    );

Uri? _uriOrNull(Object? value) => value == null ? null : Uri.parse(value as String);

DateTime? _dateOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
