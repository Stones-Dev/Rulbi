import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import 'epg_providers.dart';

/// Programa actual + barra de progreso EPG (ui-spec §2.3: "programa actual
/// con barra de progreso"; §2.2: fila "Ahora en tus canales") — hoja del
/// árbol de widgets a propósito (S5 · Ola 2, D7 del plan de la ola): es el
/// único punto que se repinta en cada tick de [epgClockProvider]
/// (`ValueListenableBuilder`), nunca la fila/tarjeta completa que lo
/// contiene.
///
/// Pide sus datos a [controller] en cada `build()` (`EpgNowController
/// .request`, agrupa por lotes, ver su docstring) y lee siempre síncrono
/// — sin `FutureBuilder`, sin parpadeo de carga por fila.
///
/// Estado vacío explícito (ui-spec §2.3: "sin EPG, ítem sin subtítulo"):
/// si [tvgId] es `null` o el canal no tiene guía, no pinta absolutamente
/// nada — ni subtítulo ni barra — nunca un dato inventado (RNF-09).
class EpgProgressBar extends ConsumerWidget {
  const EpgProgressBar({
    required this.tvgId,
    required this.controller,
    super.key,
  });

  final String? tvgId;
  final EpgNowController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(epgClockProvider);

    // Dos fuentes de rebuild, anidadas a propósito: `controller` avisa
    // cuando llegan datos nuevos de la BD (`request`/`_flush`, en
    // cualquier momento, no solo en el tick); `clock` avisa cada 30 s para
    // recalcular la fracción de la barra contra el mismo programa ya
    // cargado, sin tocar la BD. Sin la primera, la barra se quedaría en
    // blanco hasta el siguiente tick aunque los datos ya hubieran llegado.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ValueListenableBuilder<DateTime>(
        valueListenable: clock,
        builder: (context, now, _) {
          // Idempotente y barato (no toca la BD si nada terminó de emitir,
          // ver docstring de `invalidateIfStale`) — se llama aquí, no en
          // un `Timer` propio de la pantalla, para no tener que cablear
          // ese ciclo de vida por separado en cada pantalla que use EPG.
          controller.invalidateIfStale(now);
          controller.request(tvgId, now);
          final programme = controller.nowAiring(tvgId);
          if (programme == null) return const SizedBox.shrink();

          final fraction = _fractionOf(programme, now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                programme.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: IptvColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 3,
                  backgroundColor: IptvColors.border,
                  valueColor: const AlwaysStoppedAnimation(IptvColors.accent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _fractionOf(EpgProgramme programme, DateTime now) {
    final total = programme.stop.difference(programme.start).inMilliseconds;
    if (total <= 0) return 0;
    final elapsed = now.difference(programme.start).inMilliseconds;
    return (elapsed / total).clamp(0, 1);
  }
}
