import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_core/iptv_core.dart' as core;
import 'package:iptv_playback/iptv_playback.dart';
import 'package:video_player/video_player.dart';

class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController(super.url) : super.networkUrl();

  bool playCalled = false;
  bool pauseCalled = false;
  Duration? seekTarget;
  double? lastVolume;
  String? selectedTrack;
  bool throwOnInitialize = false;

  @override
  Future<void> initialize() async {
    if (throwOnInitialize) {
      throw Exception('Network error');
    }
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 120),
      position: Duration.zero,
    );
  }

  @override
  Future<void> play() async {
    playCalled = true;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekTarget = position;
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    lastVolume = volume;
    value = value.copyWith(volume: volume);
  }

  @override
  bool isAudioTrackSupportAvailable() => true;

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() async {
    return [
      VideoAudioTrack(
        id: '1',
        isSelected: selectedTrack == null || selectedTrack == '1',
        label: 'Spanish',
        language: 'es',
      ),
      VideoAudioTrack(
        id: '2',
        isSelected: selectedTrack == '2',
        label: 'English',
        language: 'en',
      ),
    ];
  }

  @override
  Future<void> selectAudioTrack(String trackId) async {
    selectedTrack = trackId;
  }
}

void main() {
  group('AndroidMedia3Player', () {
    late _FakeVideoPlayerController fakeController;
    late AndroidMedia3Player player;

    setUp(() {
      player = AndroidMedia3Player(
        controllerFactory: (url, headers) {
          fakeController = _FakeVideoPlayerController(url);
          return fakeController;
        },
      );
    });

    tearDown(() async {
      await player.dispose();
    });

    test('arranca en estado idle', () {
      expect(player.currentState.status, core.PlaybackStatus.idle);
      expect(player.currentState.position, Duration.zero);
      expect(player.currentState.duration, Duration.zero);
    });

    test('open abre el stream, arranca playback y emite estados', () async {
      final states = <core.PlaybackState>[];
      final sub = player.state.listen(states.add);

      await player.open(
        Uri.parse('http://example.com/stream.m3u8'),
        headers: {'User-Agent': 'CustomAgent'},
      );

      await Future<void>.delayed(Duration.zero);

      expect(fakeController.playCalled, isTrue);
      expect(player.currentState.status, core.PlaybackStatus.playing);
      expect(player.currentState.duration, const Duration(seconds: 120));

      expect(states.any((s) => s.status == core.PlaybackStatus.opening), isTrue);
      expect(states.any((s) => s.status == core.PlaybackStatus.playing), isTrue);

      await sub.cancel();
    });

    test('open con startAt hace seek nativo a la posición de reanudación', () async {
      const resume = Duration(seconds: 45);
      await player.open(
        Uri.parse('http://example.com/movie.mp4'),
        startAt: resume,
      );

      expect(fakeController.seekTarget, resume);
      expect(player.currentState.position, resume);
    });

    test('play, pause y togglePlayPause controlan el reproductor', () async {
      await player.open(Uri.parse('http://example.com/live.ts'));

      expect(player.currentState.status, core.PlaybackStatus.playing);

      await player.pause();
      expect(fakeController.pauseCalled, isTrue);
      expect(player.currentState.status, core.PlaybackStatus.paused);

      await player.togglePlayPause();
      expect(player.currentState.status, core.PlaybackStatus.playing);

      await player.togglePlayPause();
      expect(player.currentState.status, core.PlaybackStatus.paused);
    });

    test('seek cambia la posición del contenido', () async {
      await player.open(Uri.parse('http://example.com/vod.mkv'));

      const target = Duration(seconds: 30);
      await player.seek(target);

      expect(fakeController.seekTarget, target);
      expect(player.currentState.position, target);
    });

    test('setVolume y setMuted controlan el volumen correctamente', () async {
      await player.open(Uri.parse('http://example.com/stream.m3u8'));

      await player.setVolume(0.75);
      expect(fakeController.lastVolume, 0.75);
      expect(player.currentState.volume, 0.75);
      expect(player.currentState.muted, isFalse);

      await player.setMuted(true);
      expect(fakeController.lastVolume, 0.0);
      expect(player.currentState.muted, isTrue);

      await player.setMuted(false);
      expect(fakeController.lastVolume, 0.75);
      expect(player.currentState.muted, isFalse);
    });

    test('sync y selección de pistas de audio', () async {
      await player.open(Uri.parse('http://example.com/stream.m3u8'));

      expect(player.currentTracks.audio.length, 2);
      expect(player.currentTracks.selectedAudioId, '1');

      await player.setAudioTrack('2');
      expect(fakeController.selectedTrack, '2');
      expect(player.currentTracks.selectedAudioId, '2');
    });

    test('error de inicialización emite failed con mensaje', () async {
      final failPlayer = AndroidMedia3Player(
        controllerFactory: (url, headers) {
          final ctrl = _FakeVideoPlayerController(url);
          ctrl.throwOnInitialize = true;
          return ctrl;
        },
      );

      await failPlayer.open(Uri.parse('http://invalid.url'));

      expect(failPlayer.currentState.status, core.PlaybackStatus.failed);
      expect(failPlayer.currentState.errorMessage, isNotNull);

      await failPlayer.dispose();
    });
  });
}
