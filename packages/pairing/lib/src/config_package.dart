import 'package:iptv_core/iptv_core.dart';

import 'serialization/favorite_codec.dart';
import 'serialization/source_codec.dart';
import 'serialization/watch_state_codec.dart';

/// Una fuente lista para viajar en el paquete de configuración: el
/// [Source] de dominio más su secreto (contraseña Xtream, etc.), si lo
/// tiene. Quien arma el paquete lo recoge de `SecureCredentialStore` —
/// `pairing` no sabe nada del almacén seguro (ese puerto vive en `core`,
/// la implementación en `data`, P5).
final class SourceExport {
  const SourceExport({required this.source, this.secret});

  final Source source;
  final String? secret;
}

/// Lanzada al leer un paquete de una versión futura de la app que este
/// dispositivo no sabe interpretar. Un campo *desconocido* dentro de la
/// versión actual se ignora sin más; una versión *mayor* que la propia,
/// no — silenciosamente perder datos sería peor que fallar con claridad.
final class UnsupportedConfigVersionException implements Exception {
  UnsupportedConfigVersionException(this.foundVersion, this.supportedVersion);

  final int foundVersion;
  final int supportedVersion;

  @override
  String toString() =>
      'Paquete de configuración v$foundVersion; esta app solo entiende '
      'hasta v$supportedVersion. Actualiza la app para poder recibirlo.';
}

/// El paquete que viaja por el canal local cifrado en un emparejamiento
/// (ui-spec §3.2, HU-08) y que además es la unidad de merge de la sync
/// automática (HU-09, ADR-002/003).
final class ConfigPackage {
  const ConfigPackage({
    this.sources = const [],
    this.favorites = const [],
    this.watchState = const [],
    this.settings = const {},
  });

  static const currentVersion = 1;

  final List<SourceExport> sources;
  final List<Favorite> favorites;
  final List<WatchState> watchState;
  final Map<String, Object?> settings;

  /// Serialización para el canal WebSocket local cifrado (P5): la única
  /// que incluye los secretos de [sources]. Deliberadamente no existe un
  /// `toJson({includeSecrets})` genérico — un booleano invita a pasar el
  /// valor equivocado; dos métodos con nombre explícito no.
  Map<String, Object?> toJsonForSecureChannel() =>
      _toJson(includeSecrets: true);

  /// Serialización para la exportación manual a archivo (ui-spec §2.15,
  /// el "backup" serverless): nunca lleva secretos. Cifrar ese archivo o
  /// no es una decisión del flujo de exportación, no de este paquete.
  Map<String, Object?> toJsonForFileExport() => _toJson(includeSecrets: false);

  Map<String, Object?> _toJson({required bool includeSecrets}) => {
    'v': currentVersion,
    'sources': [
      for (final export in sources)
        {
          ...export.source.toJson(),
          if (includeSecrets && export.secret != null) 'secret': export.secret,
        },
    ],
    'favorites': [for (final favorite in favorites) favorite.toJson()],
    'watch_state': [for (final state in watchState) state.toJson()],
    'settings': settings,
  };

  /// Reconstruye el paquete. Tolerante a campos desconocidos (una
  /// versión futura pudo añadir claves que esta no entiende pero puede
  /// ignorar sin más); intransigente con `v` mayor que [currentVersion].
  factory ConfigPackage.fromJson(Map<String, Object?> json) {
    final version = json['v'] as int? ?? 1;
    if (version > currentVersion) {
      throw UnsupportedConfigVersionException(version, currentVersion);
    }

    final rawSources = (json['sources'] as List?) ?? const [];
    final rawFavorites = (json['favorites'] as List?) ?? const [];
    final rawWatchState = (json['watch_state'] as List?) ?? const [];
    final rawSettings = (json['settings'] as Map?) ?? const {};

    return ConfigPackage(
      sources: [
        for (final raw in rawSources)
          _sourceExportFromJson(raw as Map<String, Object?>),
      ],
      favorites: [
        for (final raw in rawFavorites)
          favoriteFromJson(raw as Map<String, Object?>),
      ],
      watchState: [
        for (final raw in rawWatchState)
          watchStateFromJson(raw as Map<String, Object?>),
      ],
      settings: Map<String, Object?>.from(rawSettings),
    );
  }
}

SourceExport _sourceExportFromJson(Map<String, Object?> json) => SourceExport(
  source: sourceFromJson(json),
  secret: json['secret'] as String?,
);
