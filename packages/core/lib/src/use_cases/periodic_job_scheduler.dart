import 'dart:async';

/// Contrato mínimo de un trabajo periódico con guarda de intervalo propia
/// (S5.5, Bloque B3) — extraído de `PurgeScheduler` (S2) para que
/// `RunEpgRefresh` reutilice el mismo mecanismo de disparo sin duplicar
/// `start`/`stop`/manejo de errores. El intervalo mínimo entre corridas y
/// la decisión de "tocaba o no" viven en cada implementación
/// (`DefaultRunPurge.runIfDue`, `DefaultRunEpgRefresh.runIfDue`), no aquí:
/// este scheduler no sabe nada de políticas, solo de cuándo intentar.
abstract interface class PeriodicJob {
  Future<void> runIfDue();
}

/// Dispara un [PeriodicJob] a partir de un `Stream<void>` de triggers
/// inyectado — sin `Timer` real (testeable sin dormir de verdad) y sin
/// atar `core` a un WorkManager de plataforma concreto (eso es cableado de
/// `apps/app`, F2/F6). En producción, `triggers` se compone de
/// `Stream.periodic(policy.minInterval)` + el final de cada import (para
/// `RunPurge`) o de arranque de app (para `RunEpgRefresh`); en tests es un
/// `StreamController` bombeado a mano.
final class PeriodicJobScheduler {
  PeriodicJobScheduler(this._job, this._triggers, {this.onError});

  final PeriodicJob _job;
  final Stream<void> _triggers;

  /// Reporta el fallo de una corrida individual. Nunca cancela la
  /// suscripción: un trabajo roto una vez no debe impedir que las
  /// siguientes se intenten.
  final void Function(Object error, StackTrace stackTrace)? onError;

  StreamSubscription<void>? _subscription;

  /// Corre una vez inmediatamente y luego una vez por cada evento de
  /// `triggers` (sujeto a la guarda de intervalo propia de [PeriodicJob]).
  Future<void> start() async {
    await _runGuarded();
    _subscription = _triggers.listen((_) => unawaited(_runGuarded()));
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _runGuarded() async {
    try {
      await _job.runIfDue();
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }
}
