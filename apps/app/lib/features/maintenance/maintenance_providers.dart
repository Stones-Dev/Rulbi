import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../sources/source_providers.dart';

/// Wiring de producción de la purga (`RunPurge`, S2) — escrita y testeada
/// desde entonces (`packages/core/test/run_purge_test.dart`,
/// `packages/data/test/purge_benchmark_test.dart`) pero **nunca arrancada
/// en la app real** hasta S5.5, Bloque B4: no había ningún bootstrap en
/// `main.dart` que la llamara. `PurgePolicy` usa sus defaults (S2): esto
/// no cambia con S5.5, solo la echa a andar.
final runPurgeProvider = Provider<RunPurge>((ref) {
  return DefaultRunPurge(
    ref.watch(epgRepositoryProvider),
    ref.watch(channelRepositoryProvider),
    ref.watch(clockProvider),
  );
});

/// `Stream.periodic(PurgePolicy().minInterval)` — mismo criterio que
/// `epgRefreshSchedulerProvider` (`features/epg/epg_providers.dart`):
/// sujeto de todas formas a `PurgePolicy.minInterval` vía
/// `RunPurge.runIfDue`, sin infraestructura de background nueva. Arrancado
/// una vez desde `IptvApp.initState` (`main.dart`).
final purgeSchedulerProvider = Provider<PeriodicJobScheduler>((ref) {
  final scheduler = PeriodicJobScheduler(
    ref.watch(runPurgeProvider),
    Stream<void>.periodic(const PurgePolicy().minInterval),
  );
  ref.onDispose(() => unawaited(scheduler.stop()));
  return scheduler;
});
