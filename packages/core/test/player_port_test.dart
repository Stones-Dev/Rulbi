import 'dart:async';

import 'package:iptv_core/iptv_core.dart';
import 'package:test/test.dart';

/// Implementación de referencia de [PlayerPort] contra memoria pura, sin
/// ningún motor nativo — verifica el contrato del puerto en sí (S6, Bloque
/// A): cualquier adapter real (`MediaKitPlayer` en `packages/player`) debe
/// comportarse igual desde el punto de vista de quien lo usa. No simula
/// buffering/red: eso es responsabilidad del adapter real, fuera del
/// alcance de este contrato.
final class _FakePlayerPort implements PlayerPort {
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _tracksController = StreamController<PlayerTracks>.broadcast();

  PlaybackState _state = PlaybackState.idle;
  PlayerTracks _tracks = PlayerTracks.empty;

  /// Pistas que `open` deja disponibles — fijado por el test antes de
  /// llamar a `open`, igual que un adapter real las descubriría del
  /// contenido recién abierto.
  PlayerTracks tracksToDiscoverOnOpen = PlayerTracks.empty;

  bool disposed = false;

  void _emitState(PlaybackState next) {
    _state = next;
    _stateController.add(next);
  }

  void _emitTracks(PlayerTracks next) {
    _tracks = next;
    _tracksController.add(next);
  }

  @override
  Stream<PlaybackState> get state => _stateController.stream;

  @override
  Stream<PlayerTracks> get tracks => _tracksController.stream;

  @override
  PlaybackState get currentState => _state;

  @override
  Future<void> open(
    Uri url, {
    Duration startAt = Duration.zero,
    Map<String, String> headers = const {},
  }) async {
    _emitState(
      PlaybackState(
        status: PlaybackStatus.playing,
        position: startAt,
        duration: _state.duration,
      ),
    );
    _emitTracks(tracksToDiscoverOnOpen);
  }

  @override
  Future<void> play() async =>
      _emitState(_copyWith(status: PlaybackStatus.playing));

  @override
  Future<void> pause() async =>
      _emitState(_copyWith(status: PlaybackStatus.paused));

  @override
  Future<void> togglePlayPause() async {
    if (_state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _state.duration && _state.duration > Duration.zero
              ? _state.duration
              : position);
    _emitState(_copyWith(position: clamped));
  }

  @override
  Future<void> setVolume(double volume) async =>
      _emitState(_copyWith(volume: volume));

  @override
  Future<void> setMuted(bool muted) async => _emitState(_copyWith(muted: muted));

  @override
  Future<void> setAudioTrack(String trackId) async =>
      _emitTracks(
        PlayerTracks(
          audio: _tracks.audio,
          subtitle: _tracks.subtitle,
          selectedAudioId: trackId,
          selectedSubtitleId: _tracks.selectedSubtitleId,
        ),
      );

  @override
  Future<void> setSubtitleTrack(String? trackId) async => _emitTracks(
    PlayerTracks(
      audio: _tracks.audio,
      subtitle: _tracks.subtitle,
      selectedAudioId: _tracks.selectedAudioId,
      selectedSubtitleId: trackId,
    ),
  );

  @override
  Future<void> stop() async => _emitState(PlaybackState.idle);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stateController.close();
    await _tracksController.close();
  }

  PlaybackState _copyWith({
    PlaybackStatus? status,
    Duration? position,
    double? volume,
    bool? muted,
  }) => PlaybackState(
    status: status ?? _state.status,
    position: position ?? _state.position,
    duration: _state.duration,
    buffered: _state.buffered,
    volume: volume ?? _state.volume,
    muted: muted ?? _state.muted,
  );
}

void main() {
  group('PlayerPort (contrato, S6 · Bloque A)', () {
    late _FakePlayerPort player;

    setUp(() => player = _FakePlayerPort());

    test('open deja status playing y position en startAt', () async {
      await player.open(
        Uri.parse('http://example.com/movie.mp4'),
        startAt: const Duration(minutes: 5),
      );

      expect(player.currentState.status, PlaybackStatus.playing);
      expect(player.currentState.position, const Duration(minutes: 5));
    });

    test('togglePlayPause alterna entre playing y paused', () async {
      await player.open(Uri.parse('http://example.com/live.ts'));
      expect(player.currentState.status, PlaybackStatus.playing);

      await player.togglePlayPause();
      expect(player.currentState.status, PlaybackStatus.paused);

      await player.togglePlayPause();
      expect(player.currentState.status, PlaybackStatus.playing);
    });

    test('seek mueve position y respeta los límites de duration', () async {
      await player.open(Uri.parse('http://example.com/movie.mp4'));
      // duration por defecto es Duration.zero en el fake tras `open` (no
      // se fija explícitamente) — se prueba el clamp inferior, que no
      // depende de duration > 0.
      await player.seek(const Duration(seconds: -5));
      expect(player.currentState.position, Duration.zero);

      await player.seek(const Duration(minutes: 3));
      expect(player.currentState.position, const Duration(minutes: 3));
    });

    test('setAudioTrack cambia selectedAudioId y emite en tracks', () async {
      player.tracksToDiscoverOnOpen = const PlayerTracks(
        audio: [
          PlayerTrack(id: 'a1', language: 'es'),
          PlayerTrack(id: 'a2', language: 'en'),
        ],
      );
      await player.open(Uri.parse('http://example.com/movie.mp4'));

      final future = player.tracks.first;
      await player.setAudioTrack('a2');
      final emitted = await future;

      expect(emitted.selectedAudioId, 'a2');
    });

    test('setSubtitleTrack cambia selectedSubtitleId', () async {
      player.tracksToDiscoverOnOpen = const PlayerTracks(
        subtitle: [PlayerTrack(id: 's1', language: 'es')],
      );
      await player.open(Uri.parse('http://example.com/movie.mp4'));

      final future = player.tracks.first;
      await player.setSubtitleTrack('s1');
      expect((await future).selectedSubtitleId, 's1');
    });

    test('setSubtitleTrack(null) desactiva los subtítulos', () async {
      player.tracksToDiscoverOnOpen = const PlayerTracks(
        subtitle: [PlayerTrack(id: 's1')],
      );
      await player.open(Uri.parse('http://example.com/movie.mp4'));
      await player.setSubtitleTrack('s1');

      final future = player.tracks.first;
      await player.setSubtitleTrack(null);

      expect((await future).selectedSubtitleId, isNull);
    });

    test('dispose marca el puerto como liberado', () async {
      await player.open(Uri.parse('http://example.com/movie.mp4'));
      await player.dispose();
      expect(player.disposed, isTrue);
    });
  });
}
