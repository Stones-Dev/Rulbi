/// Abstracción de reproducción (P6, ui-spec §2.13): el dominio y la UI
/// hablan con [PlayerPort], nunca con media3/libmpv/AVPlayer/webOS
/// directamente. La única implementación real vive en `packages/player`
/// (`MediaKitPlayer`, S6) — este archivo es Dart puro, sin un solo tipo de
/// Flutter, para que `core` siga sin conocer al reproductor.
library;

/// Estado grueso de la reproducción — suficiente para que el overlay
/// (ui-spec §2.13: "estado de buffer") decida qué pintar sin tener que
/// inferirlo combinando varios booleanos sueltos.
enum PlaybackStatus {
  /// Sin nada abierto todavía (antes del primer `open`, o tras `stop`).
  idle,

  /// `open` en curso: aún no hay el primer frame.
  opening,

  /// Reproduciendo, pero sin buffer suficiente para avanzar — motivo
  /// distinto de `paused` (el usuario no lo pidió).
  buffering,

  playing,
  paused,

  /// Llegó al final del contenido (VOD/episodio) — un directo normalmente
  /// no alcanza este estado salvo corte de stream.
  ended,

  /// `errorMessage` de [PlaybackState] trae el motivo. Ningún otro campo
  /// del estado es fiable en este status.
  failed,
}

/// Una pista de audio o de subtítulos, tal como la reporta el motor
/// nativo. [id] es opaco (lo que el motor use internamente para
/// seleccionarla) — [PlayerPort] nunca intenta interpretarlo, solo lo
/// devuelve tal cual a `setAudioTrack`/`setSubtitleTrack`.
final class PlayerTrack {
  const PlayerTrack({required this.id, this.title, this.language});

  final String id;
  final String? title;
  final String? language;

  @override
  bool operator ==(Object other) =>
      other is PlayerTrack &&
      other.id == id &&
      other.title == title &&
      other.language == language;

  @override
  int get hashCode => Object.hash(id, title, language);

  @override
  String toString() => 'PlayerTrack($id, ${title ?? language ?? "?"})';
}

/// Snapshot de las pistas disponibles + cuál está activa ahora mismo
/// (ui-spec §2.13: "selector de pista de audio y subtítulos"). Emitido de
/// nuevo cada vez que el motor descubre o cambia de pistas — típicamente
/// una vez tras `open`, y de nuevo tras cada `setAudioTrack`/
/// `setSubtitleTrack`.
final class PlayerTracks {
  const PlayerTracks({
    this.audio = const [],
    this.subtitle = const [],
    this.selectedAudioId,
    this.selectedSubtitleId,
  });

  final List<PlayerTrack> audio;
  final List<PlayerTrack> subtitle;

  /// `null` = ninguna pista de audio seleccionada (motor sin abrir, o sin
  /// pistas de audio en el contenido).
  final String? selectedAudioId;

  /// `null` = subtítulos desactivados (nunca "sin pistas disponibles" —
  /// eso es `subtitle.isEmpty`).
  final String? selectedSubtitleId;

  static const empty = PlayerTracks();
}

/// Estado completo de la reproducción en un instante — lo que el overlay
/// necesita para pintarse sin consultar nada más. `buffered` es una cota
/// superior de `position` (cuánto se ha descargado, no cuánto se ha
/// reproducido) — `Duration.zero` si el motor no la reporta.
final class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.volume = 1.0,
    this.muted = false,
    this.errorMessage,
  });

  final PlaybackStatus status;
  final Duration position;

  /// `Duration.zero` para directo (mismo criterio que `WatchState
  /// .duration`, `core/entities/watch_state.dart`) — no hay "cuánto dura"
  /// que mostrar.
  final Duration duration;
  final Duration buffered;

  /// `[0, 1]`.
  final double volume;
  final bool muted;

  /// Solo significativo cuando `status == PlaybackStatus.failed`.
  final String? errorMessage;

  static const idle = PlaybackState();

  @override
  String toString() =>
      'PlaybackState($status, $position/$duration, vol: $volume${muted ? " (muted)" : ""})';
}

/// Puerto de reproducción (P6). Una instancia por reproducción activa —
/// quien la construye (`packages/app`, vía el adapter real de
/// `packages/player`) es también quien la cierra con [dispose]; el puerto
/// no se reutiliza entre dos aperturas de contenido distintas con `open`
/// repetido — cada `PlayerScreen` construye la suya.
abstract interface class PlayerPort {
  /// Emite un nuevo [PlaybackState] en cada cambio observable (posición,
  /// buffer, status, volumen). No es necesariamente periódico — depende de
  /// cómo el motor real reporte progreso.
  Stream<PlaybackState> get state;

  /// Emite un nuevo snapshot cuando el motor descubre o cambia las pistas
  /// disponibles/activas.
  Stream<PlayerTracks> get tracks;

  /// Lectura síncrona del último [PlaybackState] conocido — para pintar el
  /// overlay en el primer frame sin esperar al primer evento de [state].
  PlaybackState get currentState;

  /// Abre [url] y arranca la reproducción. [startAt] posiciona el
  /// contenido (VOD/episodio con progreso guardado, ui-spec §2.6/§2.7:
  /// "Continuar (mm:ss)") — se ignora en directo. [headers] cubre paneles
  /// que exigen `User-Agent`/cabeceras propias (ui-spec §2.8, campo
  /// avanzado de la fuente M3U); vacío por defecto.
  Future<void> open(
    Uri url, {
    Duration startAt = Duration.zero,
    Map<String, String> headers = const {},
  });

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();

  /// Ignorado en directo sin *time-shift* — el motor real decide si un
  /// `seek` sobre un stream sin buffer hacia atrás es un no-op o un error
  /// silencioso; [PlayerPort] no impone la regla.
  Future<void> seek(Duration position);

  Future<void> setVolume(double volume);
  Future<void> setMuted(bool muted);

  /// [trackId] debe venir de un [PlayerTrack.id] ya visto en [tracks].
  Future<void> setAudioTrack(String trackId);

  /// `null` desactiva los subtítulos.
  Future<void> setSubtitleTrack(String? trackId);

  Future<void> stop();

  /// Libera los recursos del motor nativo. Tras llamarlo, ningún otro
  /// método de este puerto debe invocarse.
  Future<void> dispose();
}
