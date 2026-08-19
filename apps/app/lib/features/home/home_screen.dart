import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../epg/epg_providers.dart';
import '../favorites/favorites_providers.dart';
import '../player/open_channel.dart';
import '../player/open_player.dart';
import '../player/playback_request.dart';
import '../sources/source_providers.dart';
import 'continue_watching_row.dart';
import 'favorites_row.dart';
import 'home_providers.dart';
import 'now_on_your_channels_row.dart';

/// Home desktop (ui-spec §2.2): las tres filas —"Continuar viendo"
/// (S5 · Ola 1), "Favoritos" y "Ahora en tus canales" (S5 · Ola 2)— juntas
/// cierran la tarea "Home desktop" (su criterio original exigía las tres).
///
/// Reutilizada tal cual por `MobileShell` (S7 · Móvil base) — sin lógica
/// nueva, solo [contentPadding] parametrizado: por defecto
/// `IptvSpacing.containerDesktop`, que `MobileShell` sustituye por
/// `IptvSpacing.containerMobile`. Se pasa por parámetro en vez de leerlo de
/// un `FormFactor`/`IptvDensity` ambiental para que `HomeScreen` siga sin
/// depender de qué shell la aloja (mismo criterio que `onGoToSources`).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    required this.onGoToSources,
    this.contentPadding = IptvSpacing.containerDesktop,
    super.key,
  });

  /// Cambia la sección del shell a Fuentes — la CTA del estado vacío (§2.2:
  /// "vacío → CTA a Fuentes"). No hay router en la app (`IndexedStack` del
  /// shell), así que quien construye `HomeScreen` es quien conoce cómo
  /// cambiar de sección o abrir la pantalla de Fuentes.
  final VoidCallback onGoToSources;

  /// Padding del contenedor de pantalla (ui-spec §5.2). Antes de S7 este
  /// valor estaba hardcodeado a 24px en `_HomeContent` — ni el token
  /// Desktop (32) ni ningún token Mobile; deuda anotada en el cierre de
  /// S6.5, cerrada de paso aquí.
  final double contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(sourcesStreamProvider);

    return sourcesAsync.when(
      data: (sources) => sources.isEmpty
          ? _EmptyLibrary(onGoToSources: onGoToSources)
          : _HomeContent(contentPadding: contentPadding),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l10n.probeErrorUnknown)),
    );
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({required this.contentPadding});

  final double contentPadding;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  /// Una instancia por pantalla (S5 · Ola 2), mismo criterio que
  /// `ChannelListScreen`/`FavoritesScreen` — solo la usa la fila "Ahora en
  /// tus canales"; "Continuar viendo"/"Favoritos" no muestran EPG.
  late final EpgNowController _epgController;

  @override
  void initState() {
    super.initState();
    _epgController = createEpgNowController(ref);
  }

  @override
  void dispose() {
    _epgController.dispose();
    super.dispose();
  }

  /// Pull-to-refresh (S7 · Móvil base, paso 2) — invalida las tres filas y
  /// espera a que se resuelvan antes de que `RefreshIndicator` se oculte.
  /// Deliberadamente **no** relee `sourcesStreamProvider` ni dispara un
  /// refresco de fuentes: eso es una operación cara y sorprendente para un
  /// gesto de "refrescar la pantalla", y el refresco de fuentes ya tiene su
  /// sitio en Fuentes (ui-spec §2.10). `favoritesListProvider` es un
  /// `StreamProvider` sobre drift ya reactivo — invalidarlo solo reinicia
  /// la suscripción, sin coste real, pero se incluye por completitud (las
  /// tres filas de Home responden al mismo gesto).
  Future<void> _handleRefresh() async {
    ref
      ..invalidate(continueWatchingProvider)
      ..invalidate(favoritesListProvider)
      ..invalidate(nowOnYourChannelsProvider);
    await Future.wait([
      ref.read(continueWatchingProvider.future),
      ref.read(favoritesListProvider.future),
      ref.read(nowOnYourChannelsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final continueWatchingAsync = ref.watch(continueWatchingProvider);
    final favoritesAsync = ref.watch(favoritesListProvider);
    final nowOnYourChannelsAsync = ref.watch(nowOnYourChannelsProvider);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView(
        padding: EdgeInsets.all(widget.contentPadding),
        children: [
          continueWatchingAsync.when(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : ContinueWatchingRow(
                    items: items,
                    // S6, Bloque E: siempre reanuda directo (ver
                    // docstring de ContinueWatchingRow.onTap). `startAt`
                    // solo tiene sentido para VOD/episodio — un directo no
                    // tiene una línea de tiempo estable entre sesiones
                    // (WatchState.duration == Duration.zero ya documenta
                    // esto: "no hay progreso que mostrar"); pasar
                    // `item.position` como startAt ahí solo dispara un
                    // seek sin sentido sobre el buffer recién abierto
                    // (verificado a mano en S6: la posición cae en vez de
                    // continuar, confirmando que el seek no hace lo que
                    // parece pedir).
                    onTap: (item) => openPlayer(
                      context,
                      ref,
                      PlaybackRequest(
                        channel: item.channel,
                        startAt: item.duration == Duration.zero ? Duration.zero : item.position,
                      ),
                    ),
                  ),
            loading: () => const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
          favoritesAsync.when(
            data: (channels) => channels.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: IptvSpacing.lg),
                    child: FavoritesRow(
                      channels: channels,
                      // S6, Bloque E: mismo despacho por tipo que la
                      // sección Favoritos (favorites_screen.dart).
                      onTap: (channel) {
                        final liveChannels = channels
                            .where((c) => c.type == ContentType.live)
                            .toList();
                        final liveIndex = liveChannels.indexOf(channel);
                        openChannel(
                          context,
                          ref,
                          channel,
                          queue: liveIndex < 0
                              ? null
                              : PlaybackQueue(items: liveChannels, index: liveIndex),
                          heroTag: 'favoritesRow.${channel.ref.serialized}',
                        );
                      },
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          nowOnYourChannelsAsync.when(
            data: (channels) => channels.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: IptvSpacing.lg),
                    child: NowOnYourChannelsRow(
                      channels: channels,
                      epgController: _epgController,
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onGoToSources});

  final VoidCallback onGoToSources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: IptvColors.textSecondary,
          ),
          const SizedBox(height: IptvSpacing.md),
          Text(
            l10n.homeEmptyLibraryTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: IptvSpacing.sm),
          Text(l10n.homeEmptyLibraryHint, textAlign: TextAlign.center),
          const SizedBox(height: IptvSpacing.md * 1.5),
          FilledButton(
            key: const Key('homeGoToSourcesButton'),
            onPressed: onGoToSources,
            child: Text(l10n.homeGoToSourcesButton),
          ),
        ],
      ),
    );
  }
}
