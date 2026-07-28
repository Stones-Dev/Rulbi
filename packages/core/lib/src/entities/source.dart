import '../sync/syncable.dart';

/// Tipo de fuente (plan §3, tabla de stack). Determina qué [SourceConfig]
/// concreto lleva la fuente.
enum SourceKind { m3uFile, m3uUrl, xtream }

/// Cuándo se refresca una fuente automáticamente (ui-spec §2.8).
enum SourceRefreshPolicy { manual, onOpen, daily }

/// Configuración específica de cada tipo de fuente. `sealed`: el `switch`
/// sobre [SourceConfig] es exhaustivo en tiempo de compilación — si mañana
/// se añade un cuarto tipo de fuente, el analizador señala cada `switch`
/// que falta actualizar.
sealed class SourceConfig {
  const SourceConfig();
}

final class M3uFileSourceConfig extends SourceConfig {
  const M3uFileSourceConfig({required this.filePath, this.epgUrl});

  final String filePath;
  final Uri? epgUrl;

  @override
  bool operator ==(Object other) =>
      other is M3uFileSourceConfig &&
      other.filePath == filePath &&
      other.epgUrl == epgUrl;

  @override
  int get hashCode => Object.hash(filePath, epgUrl);
}

final class M3uUrlSourceConfig extends SourceConfig {
  const M3uUrlSourceConfig({required this.url, this.epgUrl, this.userAgent});

  final Uri url;
  final Uri? epgUrl;
  final String? userAgent;

  @override
  bool operator ==(Object other) =>
      other is M3uUrlSourceConfig &&
      other.url == url &&
      other.epgUrl == epgUrl &&
      other.userAgent == userAgent;

  @override
  int get hashCode => Object.hash(url, epgUrl, userAgent);
}

/// Configuración de una fuente Xtream. **Nunca lleva la contraseña**: se
/// recupera bajo demanda vía `SecureCredentialStore`, indexada por
/// `Source.id` (P5 — credenciales cifradas en el almacén seguro de la
/// plataforma, nunca en memoria como parte de una entidad de dominio que
/// se serializa, se loguea o se compara por igualdad).
final class XtreamSourceConfig extends SourceConfig {
  const XtreamSourceConfig({required this.host, required this.username});

  final Uri host;
  final String username;

  @override
  bool operator ==(Object other) =>
      other is XtreamSourceConfig &&
      other.host == host &&
      other.username == username;

  @override
  int get hashCode => Object.hash(host, username);
}

/// Una fuente de contenido del usuario (M3U o Xtream) — entidad
/// transferible: viaja en el paquete de configuración de `pairing` y
/// participa en el merge LWW (plan §4.2, §4.5).
final class Source with Syncable {
  const Source({
    required this.id,
    required this.config,
    required this.name,
    required this.updatedAt,
    this.enabled = true,
    this.lastRefresh,
    this.refreshPolicy = SourceRefreshPolicy.manual,
    this.deletedAt,
  });

  final String id;
  final SourceConfig config;
  final String name;
  final bool enabled;
  final DateTime? lastRefresh;
  final SourceRefreshPolicy refreshPolicy;

  @override
  final DateTime updatedAt;

  @override
  final DateTime? deletedAt;

  SourceKind get kind => switch (config) {
        M3uFileSourceConfig() => SourceKind.m3uFile,
        M3uUrlSourceConfig() => SourceKind.m3uUrl,
        XtreamSourceConfig() => SourceKind.xtream,
      };

  Source markDeleted(DateTime at) => Source(
        id: id,
        config: config,
        name: name,
        enabled: enabled,
        lastRefresh: lastRefresh,
        refreshPolicy: refreshPolicy,
        updatedAt: at,
        deletedAt: at,
      );

  Source withEnabled(bool value, DateTime at) => Source(
        id: id,
        config: config,
        name: name,
        enabled: value,
        lastRefresh: lastRefresh,
        refreshPolicy: refreshPolicy,
        updatedAt: at,
        deletedAt: deletedAt,
      );

  Source withRefreshed(DateTime at) => Source(
        id: id,
        config: config,
        name: name,
        enabled: enabled,
        lastRefresh: at,
        refreshPolicy: refreshPolicy,
        updatedAt: at,
        deletedAt: deletedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Source &&
      other.id == id &&
      other.config == config &&
      other.name == name &&
      other.enabled == enabled &&
      other.lastRefresh == lastRefresh &&
      other.refreshPolicy == refreshPolicy &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(
        id,
        config,
        name,
        enabled,
        lastRefresh,
        refreshPolicy,
        updatedAt,
        deletedAt,
      );

  @override
  String toString() => 'Source($id, $kind, $name)';
}
