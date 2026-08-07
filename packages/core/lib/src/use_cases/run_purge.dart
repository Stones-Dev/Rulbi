import 'dart:async';

import '../ports/channel_repository.dart';
import '../ports/clock.dart';
import '../ports/epg_repository.dart';
import 'periodic_job_scheduler.dart';

/// Ventanas/gracia de las purgas de S2 ("Ventana y purga EPG" /
/// "Tombstones huérfanos"), parametrizables a propósito (nunca constantes
/// mágicas en el SQL de `data`).
final class PurgePolicy {
  const PurgePolicy({
    this.epgPast = const Duration(days: 1),
    this.epgFuture = const Duration(days: 7),
    this.tombstoneGrace = const Duration(days: 30),
    this.minInterval = const Duration(hours: 6),
  });

  /// Cuánto antes de ahora sigue viéndose un programa de EPG — la misma
  /// ventana que `XmltvWindow.around` aplica al parsear (spec HU-03).
  final Duration epgPast;

  /// Cuánto después de ahora sigue viéndose un programa de EPG.
  final Duration epgFuture;

  /// Cuánto tiempo debe llevar tumbado un canal (sin favorito ni
  /// watch-state vivos apuntándolo) antes de borrarse de verdad. 30 días
  /// por defecto: cubre una fuente que sirve una lista parcial durante
  /// semanas sin que eso se confunda con un borrado + reinserción del
  /// mismo canal como "nuevo" en el siguiente refresco.
  final Duration tombstoneGrace;

  /// Intervalo mínimo entre corridas automáticas (`runIfDue`) — evita que
  /// un scheduler con un trigger ruidoso (p. ej. "al final de cada
  /// import") dispare la purga completa varias veces seguidas.
  final Duration minInterval;
}

/// Recuento de una corrida de purga — la mitad de "purga" del par que
/// forma con `SourceImportStats` (import), mismo estilo de serialización.
final class PurgeStats {
  const PurgeStats({
    required this.epgProgrammes,
    required this.channelTombstones,
    required this.ranAt,
  });

  /// Filas de `epg_programmes` borradas por quedar fuera de la ventana.
  final int epgProgrammes;

  /// Filas de `channels` (tombstones) borradas por no tener favorito ni
  /// watch-state vivos y superar la ventana de gracia.
  final int channelTombstones;

  /// Instante (del `Clock` inyectado, nunca `DateTime.now()` real) en que
  /// corrió esta purga.
  final DateTime ranAt;

  Map<String, Object?> toJson() => {
    'epgProgrammes': epgProgrammes,
    'channelTombstones': channelTombstones,
    'ranAt': ranAt.toIso8601String(),
  };

  factory PurgeStats.fromJson(Map<String, Object?> json) => PurgeStats(
    epgProgrammes: json['epgProgrammes'] as int,
    channelTombstones: json['channelTombstones'] as int,
    ranAt: DateTime.parse(json['ranAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is PurgeStats &&
      other.epgProgrammes == epgProgrammes &&
      other.channelTombstones == channelTombstones &&
      other.ranAt == ranAt;

  @override
  int get hashCode => Object.hash(epgProgrammes, channelTombstones, ranAt);

  @override
  String toString() =>
      'PurgeStats(epgProgrammes: $epgProgrammes, '
      'channelTombstones: $channelTombstones, ranAt: $ranAt)';
}

/// Orquesta las dos purgas de S2 sobre los puertos de `core` (P6: el SQL
/// vive en `data`, aquí solo se decide cuándo y con qué ventanas).
///
/// `implements PeriodicJob` (S5.5, Bloque B3): `Future<PurgeStats?>` es un
/// subtipo válido de `Future<void>` (Dart trata `void` como el tipo de
/// retorno más permisivo posible), así que `RunPurge` satisface
/// `PeriodicJob` sin cambiar su firma pública — `PurgeScheduler` sigue
/// recibiendo un `RunPurge` normal, tipado, con su `PurgeStats` intacto.
abstract interface class RunPurge implements PeriodicJob {
  /// Corre las dos purgas ahora mismo, sin consultar `minInterval`.
  Future<PurgeStats> runOnce();

  /// Corre `runOnce` solo si ha pasado `PurgePolicy.minInterval` desde la
  /// última corrida (de este mismo `RunPurge`, en memoria — no persiste
  /// entre reinicios de la app). Devuelve `null` si no tocaba.
  @override
  Future<PurgeStats?> runIfDue();
}

final class DefaultRunPurge implements RunPurge {
  DefaultRunPurge(
    this._epg,
    this._channels,
    this._clock, {
    this.policy = const PurgePolicy(),
  });

  final EpgRepository _epg;
  final ChannelRepository _channels;
  final Clock _clock;
  final PurgePolicy policy;

  DateTime? _lastRunAt;

  /// Mismo patrón mutex-por-future que `DefaultManageSources._withLock`
  /// (`manage_sources.dart`): dos corridas concurrentes se encolan, nunca
  /// se solapan — sin esto, dos `runOnce` a la vez podrían pisarse los
  /// contadores de `_lastRunAt` o duplicar trabajo de purga.
  Future<void>? _tail;

  @override
  Future<PurgeStats> runOnce() => _withLock(() => _runOnceLocked(_clock.now()));

  @override
  Future<PurgeStats?> runIfDue() {
    return _withLock(() async {
      final now = _clock.now();
      if (_lastRunAt != null && now.difference(_lastRunAt!) < policy.minInterval) {
        return null;
      }
      return _runOnceLocked(now);
    });
  }

  /// Cada purga se intenta con independencia de la otra (P7 extendido,
  /// mismo criterio que `importChannels` de Xtream con sus actions: un
  /// fallo en una no debe impedir la otra). Si alguna falló, se relanza
  /// su error al final —tras intentar ambas— para que el llamador (o el
  /// `PurgeScheduler`) se entere; `_lastRunAt` se actualiza igualmente
  /// para no reintentar en bucle apretado ante un fallo sistemático, el
  /// próximo trigger natural ya lo reintentará.
  Future<PurgeStats> _runOnceLocked(DateTime now) async {
    Object? epgError;
    StackTrace? epgStack;
    var epgDeleted = 0;
    try {
      epgDeleted = await _epg.purgeOutsideWindow(
        from: now.subtract(policy.epgPast),
        to: now.add(policy.epgFuture),
      );
    } catch (error, stack) {
      epgError = error;
      epgStack = stack;
    }

    Object? tombstoneError;
    StackTrace? tombstoneStack;
    var tombstonesDeleted = 0;
    try {
      tombstonesDeleted = await _channels.purgeOrphanTombstones(
        deletedBefore: now.subtract(policy.tombstoneGrace),
      );
    } catch (error, stack) {
      tombstoneError = error;
      tombstoneStack = stack;
    }

    _lastRunAt = now;

    if (epgError != null) {
      Error.throwWithStackTrace(epgError, epgStack!);
    }
    if (tombstoneError != null) {
      Error.throwWithStackTrace(tombstoneError, tombstoneStack!);
    }

    return PurgeStats(
      epgProgrammes: epgDeleted,
      channelTombstones: tombstonesDeleted,
      ranAt: now,
    );
  }

  Future<T> _withLock<T>(Future<T> Function() action) async {
    final previousTail = _tail ?? Future<void>.value();
    final completer = Completer<void>();
    _tail = completer.future;

    await previousTail;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}

/// Dispara `RunPurge` a partir de un `Stream<void>` de triggers
/// inyectado — sin `Timer` real (testeable sin dormir de verdad) y sin
/// atar `core` a un WorkManager de plataforma concreto (eso es cableado
/// de `apps/app`, F2). En producción, `triggers` se compone de
/// `Stream.periodic(policy.minInterval)` + el final de cada import; en
/// tests es un `StreamController` bombeado a mano.
///
/// Envoltorio fino sobre [PeriodicJobScheduler] (S5.5, Bloque B3): el
/// mecanismo de disparo se extrajo ahí para que `RunEpgRefresh` lo
/// reutilice; esta clase se conserva tal cual (mismo constructor
/// posicional, mismos `start`/`stop`) para que nada que ya dependa de
/// `PurgeScheduler` tenga que cambiar.
final class PurgeScheduler {
  PurgeScheduler(
    RunPurge runPurge,
    Stream<void> triggers, {
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _inner = PeriodicJobScheduler(runPurge, triggers, onError: onError);

  final PeriodicJobScheduler _inner;

  Future<void> start() => _inner.start();

  Future<void> stop() => _inner.stop();
}
