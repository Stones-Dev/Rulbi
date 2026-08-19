import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/duration_format.dart';
import '../epg/epg_providers.dart';
import 'player_controller.dart';

/// Overlay autoocultable del reproductor (ui-spec §2.13, S6, Bloque C;
/// rediseñado S6.5 paso 6 sobre los frames Figma `42:2` DIRECTO / `45:2`
/// VOD): nombre de canal/título, programa actual+siguiente (live) o barra
/// de progreso con seek (VOD/serie), reloj, estado de buffer, selector de
/// pista de audio/subtítulos, relación de aspecto.
///
/// Puramente de presentación — lee [playbackState]/[tracks] ya resueltos
/// por `PlayerScreen` (que escucha los streams de `PlayerPort`) y llama a
/// métodos de [controller] para actuar; no construye ningún provider ni
/// stream propio salvo el reloj de pared, que no tiene relación con
/// ningún dato de dominio.
///
/// Controles del rediseño S6.5: `42:2`/`45:2` fijan el *tratamiento
/// visual* (scrims, tipografía, iconografía), no un inventario cerrado de
/// controles — decisión tomada con el usuario al planificar el paso 6.
/// Volver, zapping anterior/siguiente y el selector de pista de audio
/// (separado de subtítulos) no están dibujados en esos frames pero se
/// conservan porque `ui-spec §2.13` los exige y esa fuente manda sobre
/// Figma para el *qué* (jerarquía de fuentes, CLAUDE.md).
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
    final visible = controller.overlayVisible;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        // Motion nodo Figma `42:25` ("Overlay show/hide"): fade de todo el
        // overlay. `ui-spec §5.5` prohíbe promover esto a un token
        // `IptvMotion` global — el motion se documenta pantalla a pantalla
        // en Figma, así que la duración/curva viven aquí como constantes
        // del fichero, no en `packages/tokens`.
        opacity: visible ? 1 : 0,
        duration: _overlayFadeDuration,
        curve: _overlayFadeCurve,
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
              _BufferingIndicator(label: l10n.playerBufferingLabel),
            Align(
              alignment: Alignment.topCenter,
              child: _TopBar(controller: controller, channel: channel, isLive: isLive),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                // Segunda mitad de `42:25`: la barra de controles además
                // se desplaza 24px al ocultarse. `AnimatedSlide` anima en
                // fracciones del tamaño del propio hijo, no en píxeles —
                // de ahí `_bottomBarSlideFraction`, derivada de la altura
                // real del `BottomScrim` medida en Figma.
                offset: Offset(0, visible ? 0 : _bottomBarSlideFraction),
                duration: _overlayFadeDuration,
                curve: _overlayFadeCurve,
                child: _BottomBar(
                  controller: controller,
                  playbackState: playbackState,
                  tracks: tracks,
                  isLive: isLive,
                  channel: channel,
                  epgController: epgController,
                  boxFit: boxFit,
                  onBoxFitChanged: onBoxFitChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Motion — constantes documentadas por el nodo de Figma del que salen
// (ui-spec §5.5: sin token global, se documenta pantalla a pantalla).

const _overlayFadeDuration = Duration(milliseconds: 200); // 42:25
const _overlayFadeCurve = Curves.easeOut; // 42:25

/// Altura del `BottomScrim` en `42:2`/`45:2` (32+30+44+... hasta 140) —
/// base para expresar el desplazamiento de 24px de `AnimatedSlide` como
/// fracción del alto real de la barra de controles.
const _bottomScrimHeight = 140.0;
const _bottomBarSlideFraction = 24 / _bottomScrimHeight; // 42:25

const _playPauseSwitchDuration = Duration(milliseconds: 150); // 42:30
const _playPauseSwitchCurve = Curves.easeOut; // 42:30

const _bufferingSpinDuration = Duration(milliseconds: 900); // 42:35

/// `hh:mm` de 24h con cero a la izquierda — compartido por `_WallClock` y
/// `_NowNext` ("A continuación {hh:mm}"), ninguno de los dos depende de
/// `intl` para esto (mismo criterio que `formatDurationShort`).
String _formatHm(DateTime dt) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.channel, required this.isLive});

  final PlayerController controller;
  final Channel channel;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.xl, vertical: IptvSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC0B0F14), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          if (!controller.isFullscreen) ...[
            _CircleIconButton(
              itemKey: const Key('playerOverlay.back'),
              tooltip: l10n.playerBackTooltip,
              icon: Symbols.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: IptvSpacing.md),
          ],
          if (isLive) ...[_LiveBadge(label: l10n.playerLiveBadge), const SizedBox(width: IptvSpacing.sm)],
          Expanded(
            child: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(color: IptvColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Insignia "DIRECTO" del overlay (`42:5`/`42:6`) — texto distinto del de
/// la tarjeta de Home (`homeLiveBadge` = "EN DIRECTO", `40:18`): son dos
/// componentes de Figma con dos textos literales distintos, no la misma
/// cadena reutilizada dos veces.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: IptvSpacing.sm, vertical: 3),
      decoration: BoxDecoration(color: IptvColors.accent, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: IptvTypography.labelDesktop.copyWith(color: IptvColors.onyx.accentOn)),
    );
  }
}

/// Botón circular translúcido — usado hoy solo por "volver"
/// (`playerOverlay.back`); el resto de acciones del overlay son iconos
/// planos sobre el scrim, como en `42:2`/`45:2`.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.itemKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key itemKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IptvColors.surface.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      child: IconButton(
        key: itemKey,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: IptvColors.textPrimary),
        iconSize: IptvIconSizes.action,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      ),
    );
  }
}

/// "Programa actual y siguiente" (ui-spec §2.13, live). En el frame Figma
/// `42:12` vive dentro del `ControlBar` inferior, junto al play — no bajo
/// el título como antes de S6.5 — y son dos líneas, no una unida con "→".
/// Reutiliza `EpgNowController` tal cual (`request`/`nowAiring`/`nextUp`),
/// mismo patrón que `EpgProgressBar` — sin `ListenableBuilder` propio
/// porque `PlayerScreen` ya reconstruye este árbol en cada notificación
/// del controller de reproducción; encadenar otro `ListenableBuilder` aquí
/// solo duplicaría el listener sin ganar nada.
class _NowNext extends StatelessWidget {
  const _NowNext({required this.channel, required this.epgController});

  final Channel channel;
  final EpgNowController? epgController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = epgController;
    final tvgId = channel.tvgId;
    if (controller == null || tvgId == null) return const SizedBox.shrink();

    final now = DateTime.now();
    controller.request(tvgId, now, channel: channel);
    final nowAiring = controller.nowAiring(tvgId);
    final nextUp = controller.nextUp(tvgId);
    if (nowAiring == null) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.playerNowPlayingLabel(nowAiring.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IptvTypography.bodyDesktop.copyWith(color: IptvColors.textPrimary),
        ),
        if (nextUp != null)
          Text(
            l10n.playerUpNextLabel(_formatHm(nextUp.start), nextUp.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IptvTypography.labelDesktop.copyWith(color: IptvColors.textSecondary),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.controller,
    required this.playbackState,
    required this.tracks,
    required this.isLive,
    required this.channel,
    required this.epgController,
    required this.boxFit,
    required this.onBoxFitChanged,
  });

  final PlayerController controller;
  final PlaybackState playbackState;
  final PlayerTracks tracks;
  final bool isLive;
  final Channel channel;
  final EpgNowController? epgController;
  final BoxFit boxFit;
  final ValueChanged<BoxFit> onBoxFitChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        IptvSpacing.xl,
        IptvSpacing.lg,
        IptvSpacing.xl,
        IptvSpacing.lg,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC0B0F14), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLive) ...[
            _SeekBar(controller: controller, playbackState: playbackState),
            const SizedBox(height: IptvSpacing.xs),
          ],
          Row(
            children: [
              if (controller.canGoPrevious)
                _BottomBarIconButton(
                  itemKey: const Key('playerOverlay.previous'),
                  tooltip: l10n.playerPreviousTooltip,
                  icon: Symbols.skip_previous_rounded,
                  onPressed: () => controller.previous(),
                ),
              _PlayPauseButton(controller: controller, playbackState: playbackState),
              if (controller.canGoNext)
                _BottomBarIconButton(
                  itemKey: const Key('playerOverlay.next'),
                  tooltip: l10n.playerNextTooltip,
                  icon: Symbols.skip_next_rounded,
                  onPressed: () => controller.next(),
                ),
              const SizedBox(width: IptvSpacing.md),
              if (isLive)
                Flexible(child: _NowNext(channel: channel, epgController: epgController))
              else
                Text(
                  '${formatDurationShort(playbackState.position)} / ${formatDurationShort(playbackState.duration)}',
                  style: IptvTypography.bodyDesktop.copyWith(color: IptvColors.textSecondary),
                ),
              const SizedBox(width: IptvSpacing.md),
              const _WallClock(),
              const Spacer(),
              _BottomBarIconButton(
                itemKey: const Key('playerOverlay.mute'),
                tooltip: playbackState.muted ? l10n.playerUnmuteTooltip : l10n.playerMuteTooltip,
                icon: playbackState.muted ? Symbols.volume_off_rounded : Symbols.volume_up_rounded,
                onPressed: () => controller.setMuted(!playbackState.muted),
              ),
              _TrackMenuButton(
                key: const Key('playerOverlay.subtitleTrack'),
                tooltip: l10n.playerSubtitleTrackTooltip,
                icon: Symbols.closed_caption_rounded,
                selectedId: tracks.selectedSubtitleId,
                items: tracks.subtitle,
                allowOff: true,
                offLabel: l10n.playerSubtitlesOffOption,
                onSelected: (id) => controller.port.setSubtitleTrack(id),
              ),
              _TrackMenuButton(
                key: const Key('playerOverlay.audioTrack'),
                tooltip: l10n.playerAudioTrackTooltip,
                icon: Symbols.audiotrack_rounded,
                selectedId: tracks.selectedAudioId,
                items: tracks.audio,
                allowOff: false,
                offLabel: l10n.playerSubtitlesOffOption,
                onSelected: (id) => controller.port.setAudioTrack(id!),
              ),
              _BottomBarIconButton(
                itemKey: const Key('playerOverlay.aspectRatio'),
                tooltip: l10n.playerAspectRatioTooltip,
                icon: Symbols.aspect_ratio_rounded,
                onPressed: () => onBoxFitChanged(_nextFit(boxFit)),
              ),
              _BottomBarIconButton(
                itemKey: const Key('playerOverlay.fullscreen'),
                tooltip: controller.isFullscreen
                    ? l10n.playerExitFullscreenTooltip
                    : l10n.playerFullscreenTooltip,
                icon: controller.isFullscreen
                    ? Symbols.fullscreen_exit_rounded
                    : Symbols.fullscreen_rounded,
                onPressed: () => controller.toggleFullscreen(),
              ),
            ],
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(
            isLive ? l10n.playerShortcutsHelpLive : l10n.playerShortcutsHelpVod,
            style: IptvTypography.labelDesktop.copyWith(color: IptvColors.textSecondary),
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

/// Play/pause 44×44 (`42:10`/`45:10`) — glifo en `AnimatedSwitcher` con
/// cross-fade + escala (nodo Figma `42:30`).
class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.controller, required this.playbackState});

  final PlayerController controller;
  final PlaybackState playbackState;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final playing = playbackState.status == PlaybackStatus.playing;

    return IconButton(
      key: const Key('playerOverlay.playPause'),
      tooltip: playing ? l10n.playerPauseTooltip : l10n.playerPlayTooltip,
      onPressed: () => controller.togglePlayPause(),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: AnimatedSwitcher(
        duration: _playPauseSwitchDuration,
        switchInCurve: _playPauseSwitchCurve,
        switchOutCurve: _playPauseSwitchCurve,
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
        child: Icon(
          playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
          key: ValueKey(playing),
          color: IptvColors.textPrimary,
          size: IptvIconSizes.action,
        ),
      ),
    );
  }
}

/// Icono plano 36×36 del control bar (`42:16`/`42:18`/`42:20`/`42:22`) —
/// mute, subtítulos, pista de audio, relación de aspecto y pantalla
/// completa comparten esta forma.
class _BottomBarIconButton extends StatelessWidget {
  const _BottomBarIconButton({
    required this.itemKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final Key itemKey;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: itemKey,
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      icon: Icon(icon, color: IptvColors.textPrimary, size: IptvIconSizes.action),
    );
  }
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
    // `PlaybackState.buffered` existe en el puerto desde siempre y hasta
    // S6.5 no se pintaba en ningún sitio — `ui-spec §2.13` pide "estado de
    // buffer" explícitamente.
    final buffered = playbackState.buffered.inMilliseconds.toDouble().clamp(0.0, max);

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: IptvColors.accent,
        inactiveTrackColor: IptvColors.border,
        secondaryActiveTrackColor: IptvColors.textSecondary,
        thumbColor: IptvColors.accent,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        key: const Key('playerOverlay.seekBar'),
        value: value,
        max: max,
        secondaryTrackValue: buffered,
        onChanged: duration.inMilliseconds > 0
            ? (next) {
                // Sin esto el overlay podía autoocultarse a mitad de un
                // arrastre (hallazgo S6.5 paso 6) — cada movimiento cuenta
                // como interacción, igual que mover el ratón.
                controller.show();
                controller.port.seek(Duration(milliseconds: next.round()));
              }
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
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        color: enabled ? IptvColors.textPrimary : IptvColors.textSecondary,
        size: IptvIconSizes.action,
      ),
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

/// Spinner de buffering (`42:35`): `RotationTransition` continua sobre un
/// glifo estático, en vez del `CircularProgressIndicator` genérico de
/// antes de S6.5. `IptvIconSizes.hero` (48, "el play grande del overlay")
/// no se usa aquí a propósito — el tamaño del spinner es una decisión
/// propia de este estado, no el mismo slot que un play hero; queda
/// anotado como token sin consumidor en el handoff de esta tarea.
class _BufferingIndicator extends StatefulWidget {
  const _BufferingIndicator({required this.label});

  final String label;

  @override
  State<_BufferingIndicator> createState() => _BufferingIndicatorState();
}

class _BufferingIndicatorState extends State<_BufferingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _bufferingSpinDuration,
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _spin,
            child: const Icon(Symbols.progress_activity_rounded, color: IptvColors.accent, size: 40),
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(widget.label, style: const TextStyle(color: IptvColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Reloj de pared del overlay (ui-spec §2.13) — sin relación con ningún
/// dato de dominio, así que corre su propio `Timer` local en vez de
/// depender de `epgClockProvider` (ese existe para recalcular progreso
/// EPG cada 30 s, una granularidad demasiado gruesa para un reloj legible
/// minuto a minuto). Se mueve al control bar (`42:15`/`45:12` no lo
/// dibujan junto al reloj, pero `x=306` de `42:9` sí lo sitúa ahí) — antes
/// de S6.5 vivía en la barra superior.
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
    return Text(_formatHm(_now), style: IptvTypography.bodyDesktop.copyWith(color: IptvColors.textSecondary));
  }
}
