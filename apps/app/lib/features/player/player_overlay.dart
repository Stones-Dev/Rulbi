import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/duration_format.dart';
import '../epg/epg_providers.dart';
import 'player_controller.dart';

/// Overlay autoocultable del reproductor (ui-spec §2.13, S6, Bloque C):
/// nombre de canal/título, programa actual+siguiente (live) o barra de
/// progreso con seek (VOD/serie), reloj, estado de buffer, selector de
/// pista de audio/subtítulos, relación de aspecto.
///
/// Puramente de presentación — lee [playbackState]/[tracks] ya resueltos
/// por `PlayerScreen` (que escucha los streams de `PlayerPort`) y llama a
/// métodos de [controller] para actuar; no construye ningún provider ni
/// stream propio salvo el reloj de pared, que no tiene relación con
/// ningún dato de dominio.
class PlayerOverlay extends StatelessWidget {
  const PlayerOverlay({
    super.key,
    required this.controller,
    required this.playbackState,
    required this.tracks,
    required this.boxFit,
    required this.onBoxFitChanged,
    this.epgController,
  });

  final PlayerController controller;
  final PlaybackState playbackState;
  final PlayerTracks tracks;
  final BoxFit boxFit;
  final ValueChanged<BoxFit> onBoxFitChanged;

  /// `null` fuera de directo (VOD/serie) — sin EPG que mostrar.
  final EpgNowController? epgController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final channel = controller.currentChannel;
    final isLive = channel.type == ContentType.live;

    return IgnorePointer(
      ignoring: !controller.overlayVisible,
      child: AnimatedOpacity(
        opacity: controller.overlayVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          children: [
            if (controller.unplayable)
              Center(
                child: Text(
                  l10n.playerUnplayableMessage,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: IptvColors.textPrimary),
                ),
              ),
            if (playbackState.status == PlaybackStatus.buffering)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: IptvColors.accent),
                    const SizedBox(height: IptvSpacing.sm),
                    Text(l10n.playerBufferingLabel, style: const TextStyle(color: IptvColors.textPrimary)),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: _TopBar(
                controller: controller,
                channel: channel,
                isLive: isLive,
                epgController: epgController,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _BottomBar(
                controller: controller,
                playbackState: playbackState,
                tracks: tracks,
                isLive: isLive,
                boxFit: boxFit,
                onBoxFitChanged: onBoxFitChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.channel, required this.isLive, this.epgController});

  final PlayerController controller;
  final Channel channel;
  final bool isLive;
  final EpgNowController? epgController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.md, vertical: IptvSpacing.sm),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC0B0F14), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          if (!controller.isFullscreen)
            IconButton(
              key: const Key('playerOverlay.back'),
              tooltip: l10n.playerBackTooltip,
              icon: const Icon(Icons.arrow_back, color: IptvColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(color: IptvColors.textPrimary),
                ),
                if (isLive) _NowNext(channel: channel, epgController: epgController),
              ],
            ),
          ),
          const SizedBox(width: IptvSpacing.md),
          const _WallClock(),
        ],
      ),
    );
  }
}

/// "Programa actual y siguiente" (ui-spec §2.13, live). Reutiliza
/// `EpgNowController` tal cual (`request`/`nowAiring`/`nextUp`), mismo
/// patrón que `EpgProgressBar` — sin `ListenableBuilder` propio porque
/// `PlayerScreen` ya reconstruye este árbol en cada notificación del
/// controller de reproducción; encadenar otro `ListenableBuilder` aquí
/// solo duplicaría el listener sin ganar nada.
class _NowNext extends StatelessWidget {
  const _NowNext({required this.channel, required this.epgController});

  final Channel channel;
  final EpgNowController? epgController;

  @override
  Widget build(BuildContext context) {
    final controller = epgController;
    final tvgId = channel.tvgId;
    if (controller == null || tvgId == null) return const SizedBox.shrink();

    final now = DateTime.now();
    controller.request(tvgId, now, channel: channel);
    final nowAiring = controller.nowAiring(tvgId);
    final nextUp = controller.nextUp(tvgId);
    if (nowAiring == null) return const SizedBox.shrink();

    final parts = [nowAiring.title, if (nextUp != null) '→ ${nextUp.title}'];
    return Text(
      parts.join('  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: IptvColors.textSecondary, fontSize: 12),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.playbackState,
    required this.tracks,
    required this.isLive,
    required this.boxFit,
    required this.onBoxFitChanged,
  });

  final PlayerController controller;
  final PlaybackState playbackState;
  final PlayerTracks tracks;
  final bool isLive;
  final BoxFit boxFit;
  final ValueChanged<BoxFit> onBoxFitChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.md, vertical: IptvSpacing.sm),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC0B0F14), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isLive) _SeekBar(controller: controller, playbackState: playbackState),
          Row(
            children: [
              IconButton(
                key: const Key('playerOverlay.previous'),
                tooltip: l10n.playerPreviousTooltip,
                icon: const Icon(Icons.skip_previous, color: IptvColors.textPrimary),
                onPressed: controller.canGoPrevious ? () => controller.previous() : null,
              ),
              IconButton(
                key: const Key('playerOverlay.playPause'),
                tooltip: playbackState.status == PlaybackStatus.playing
                    ? l10n.playerPauseTooltip
                    : l10n.playerPlayTooltip,
                icon: Icon(
                  playbackState.status == PlaybackStatus.playing ? Icons.pause : Icons.play_arrow,
                  color: IptvColors.textPrimary,
                ),
                onPressed: () => controller.togglePlayPause(),
              ),
              IconButton(
                key: const Key('playerOverlay.next'),
                tooltip: l10n.playerNextTooltip,
                icon: const Icon(Icons.skip_next, color: IptvColors.textPrimary),
                onPressed: controller.canGoNext ? () => controller.next() : null,
              ),
              IconButton(
                key: const Key('playerOverlay.mute'),
                tooltip: playbackState.muted ? l10n.playerUnmuteTooltip : l10n.playerMuteTooltip,
                icon: Icon(
                  playbackState.muted ? Icons.volume_off : Icons.volume_up,
                  color: IptvColors.textPrimary,
                ),
                onPressed: () => controller.setMuted(!playbackState.muted),
              ),
              if (!isLive)
                Text(
                  '${formatDurationShort(playbackState.position)} / ${formatDurationShort(playbackState.duration)}',
                  style: const TextStyle(color: IptvColors.textSecondary, fontSize: 12),
                ),
              const Spacer(),
              _TrackMenuButton(
                key: const Key('playerOverlay.audioTrack'),
                tooltip: l10n.playerAudioTrackTooltip,
                icon: Icons.audiotrack,
                selectedId: tracks.selectedAudioId,
                items: tracks.audio,
                allowOff: false,
                offLabel: l10n.playerSubtitlesOffOption,
                onSelected: (id) => controller.port.setAudioTrack(id!),
              ),
              _TrackMenuButton(
                key: const Key('playerOverlay.subtitleTrack'),
                tooltip: l10n.playerSubtitleTrackTooltip,
                icon: Icons.subtitles_outlined,
                selectedId: tracks.selectedSubtitleId,
                items: tracks.subtitle,
                allowOff: true,
                offLabel: l10n.playerSubtitlesOffOption,
                onSelected: (id) => controller.port.setSubtitleTrack(id),
              ),
              IconButton(
                key: const Key('playerOverlay.aspectRatio'),
                tooltip: l10n.playerAspectRatioTooltip,
                icon: const Icon(Icons.aspect_ratio, color: IptvColors.textPrimary),
                onPressed: () => onBoxFitChanged(_nextFit(boxFit)),
              ),
              IconButton(
                key: const Key('playerOverlay.fullscreen'),
                tooltip: controller.isFullscreen
                    ? l10n.playerExitFullscreenTooltip
                    : l10n.playerFullscreenTooltip,
                icon: Icon(
                  controller.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: IptvColors.textPrimary,
                ),
                onPressed: () => controller.toggleFullscreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static BoxFit _nextFit(BoxFit current) => switch (current) {
    BoxFit.contain => BoxFit.cover,
    BoxFit.cover => BoxFit.fill,
    _ => BoxFit.contain,
  };
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.controller, required this.playbackState});

  final PlayerController controller;
  final PlaybackState playbackState;

  @override
  Widget build(BuildContext context) {
    final duration = playbackState.duration;
    final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value = playbackState.position.inMilliseconds.toDouble().clamp(0.0, max);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: IptvColors.accent,
        inactiveTrackColor: IptvColors.border,
        thumbColor: IptvColors.accent,
        trackHeight: 3,
      ),
      child: Slider(
        key: const Key('playerOverlay.seekBar'),
        value: value,
        max: max,
        onChanged: duration.inMilliseconds > 0
            ? (next) => controller.port.seek(Duration(milliseconds: next.round()))
            : null,
      ),
    );
  }
}

class _TrackMenuButton extends StatelessWidget {
  const _TrackMenuButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.selectedId,
    required this.items,
    required this.allowOff,
    required this.offLabel,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final String? selectedId;
  final List<PlayerTrack> items;
  final bool allowOff;
  final String offLabel;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final enabled = items.isNotEmpty;
    return PopupMenuButton<String?>(
      key: key,
      tooltip: tooltip,
      enabled: enabled,
      icon: Icon(icon, color: enabled ? IptvColors.textPrimary : IptvColors.textSecondary),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (allowOff)
          CheckedPopupMenuItem<String?>(value: null, checked: selectedId == null, child: Text(offLabel)),
        for (final track in items)
          CheckedPopupMenuItem<String?>(
            value: track.id,
            checked: track.id == selectedId,
            child: Text(track.title ?? track.language ?? track.id),
          ),
      ],
    );
  }
}

/// Reloj de pared del overlay (ui-spec §2.13) — sin relación con ningún
/// dato de dominio, así que corre su propio `Timer` local en vez de
/// depender de `epgClockProvider` (ese existe para recalcular progreso
/// EPG cada 30 s, una granularidad demasiado gruesa para un reloj legible
/// minuto a minuto).
class _WallClock extends StatefulWidget {
  const _WallClock();

  @override
  State<_WallClock> createState() => _WallClockState();
}

class _WallClockState extends State<_WallClock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Text('$hh:$mm', style: const TextStyle(color: IptvColors.textSecondary));
  }
}
