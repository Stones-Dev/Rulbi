import 'dart:async';

import '../entities/source.dart';
import '../ports/clock.dart';
import '../ports/epg_ingest.dart';
import '../ports/source_repository.dart';
import 'periodic_job_scheduler.dart';

/// Intervalo mínimo entre refrescos automáticos de guía (S5.5, "Refresco
/// automático de guía") — calcada de `PurgePolicy` (S2): un value object
/// `const`, sin persistencia propia. "Configurable" hoy significa
/// parametrizable en código (tests, cableado de `apps/app`); la UI de
/// Ajustes (ui-spec §2.15, aún placeholder) lo expondrá cuando exista esa
/// pantalla — no hace falta una tabla de ajustes nueva para esto.
final class EpgRefreshPolicy {
  const EpgRefreshPolicy({this.minInterval = const Duration(hours: 6)});

  /// 6 h por defecto: mismo orden de magnitud que `PurgePolicy.minInterval`
  /// y, con la ventana EPG en `now+7d` (`XmltvWindow.around`), suficiente
  /// para que "ahora/siguiente" nunca quede muy desactualizado sin machacar
  /// paneles pequeños con descargas constantes de `xmltv.php`.
  final Duration minInterval;
}

/// Recuento de una corrida de refresco — un `EpgImportStats` es por fuente
/// (ADR-008); esto agrega sobre todas las fuentes vivas y activas en una
/// misma corrida, mismo estilo que `PurgeStats`.
final class EpgRefreshStats {
  const EpgRefreshStats({
    required this.sourcesRefreshed,
    required this.sourcesSkipped,
    required this.sourcesFailed,
    required this.programmesWritten,
    required this.ranAt,
  });

  /// Fuentes activas con guía que se refrescaron sin error (`ingestFor`
  /// devolvió `EpgImportStats`, aunque fuera con 0 cambios).
  final int sourcesRefreshed;

  /// Fuentes tumbadas, desactivadas, o sin guía configurada
  /// (`ingestFor` devolvió `null`) — nunca se intentó nada por ellas.
  final int sourcesSkipped;

  /// Fuentes activas con guía cuyo `ingestFor` lanzó — cada una en su
  /// propio `try/catch` (P7): una fuente rota no impide refrescar las
  /// demás, ni aborta la corrida completa.
  final int sourcesFailed;

  /// Suma de programas insertados/actualizados (`EpgImportStats
  /// .programmesInserted + .programmesUpdated`) de todas las fuentes
  /// refrescadas en esta corrida.
  final int programmesWritten;

  /// Instante (del `Clock` inyectado, nunca `DateTime.now()` real) en que
  /// corrió este refresco.
  final DateTime ranAt;

  Map<String, Object?> toJson() => {
    'sourcesRefreshed': sourcesRefreshed,
    'sourcesSkipped': sourcesSkipped,
    'sourcesFailed': sourcesFailed,
    'programmesWritten': programmesWritten,
    'ranAt': ranAt.toIso8601String(),
  };

  factory EpgRefreshStats.fromJson(Map<String, Object?> json) => EpgRefreshStats(
    sourcesRefreshed: json['sourcesRefreshed'] as int,
    sourcesSkipped: json['sourcesSkipped'] as int,
    sourcesFailed: json['sourcesFailed'] as int,
    programmesWritten: json['programmesWritten'] as int,
    ranAt: DateTime.parse(json['ranAt'] as String),
  );

  @override
  bool operator ==(Object other) =>
      other is EpgRefreshStats &&
      other.sourcesRefreshed == sourcesRefreshed &&
      other.sourcesSkipped == sourcesSkipped &&
      other.sourcesFailed == sourcesFailed &&
      other.programmesWritten == programmesWritten &&
      other.ranAt == ranAt;

  @override
  int get hashCode =>
      Object.hash(sourcesRefreshed, sourcesSkipped, sourcesFailed, programmesWritten, ranAt);

  @override
  String toString() =>
      'EpgRefreshStats(refreshed: $sourcesRefreshed, skipped: $sourcesSkipped, '
      'failed: $sourcesFailed, programmesWritten: $programmesWritten, ranAt: $ranAt)';
}

/// Orquesta el refresco automático de guía sobre todas las fuentes vivas
/// y activas (S5.5, "Refresco automático de guía") — independiente del
/// refresco manual de fuente (`Source.refreshPolicy`, aún sin consumidor,
/// ver `SaveSource`/formularios): esto es guía (`epg_programmes`), no
/// canales.
///
/// `implements PeriodicJob` (Bloque B3): mismo mecanismo de disparo que
/// `RunPurge`, sin duplicar `start`/`stop`/manejo de errores.
abstract interface class RunEpgRefresh implements PeriodicJob {
  /// Refresca todas las fuentes vivas y activas ahora mismo, sin consultar
  /// `minInterval`.
  Future<EpgRefreshStats> runOnce();

  /// Corre `runOnce` solo si ha pasado `EpgRefreshPolicy.minInterval`
  /// desde la última corrida (de este mismo `RunEpgRefresh`, en memoria —
  /// no persiste entre reinicios de la app, mismo criterio que
  /// `RunPurge`). Devuelve `null` si no tocaba.
  @override
  Future<EpgRefreshStats?> runIfDue();
}

final class DefaultRunEpgRefresh implements RunEpgRefresh {
  DefaultRunEpgRefresh(
    this._sources,
    this._ingest,
    this._clock, {
    this.policy = const EpgRefreshPolicy(),
  });

  final SourceRepository _sources;
  final EpgIngestPort _ingest;
  final Clock _clock;
  final EpgRefreshPolicy policy;

  DateTime? _lastRunAt;

  /// Mismo patrón mutex-por-future que `DefaultRunPurge._withLock`: dos
  /// corridas concurrentes se encolan, nunca se solapan.
  Future<void>? _tail;

  @override
  Future<EpgRefreshStats> runOnce() => _withLock(() => _runOnceLocked(_clock.now()));

  @override
  Future<EpgRefreshStats?> runIfDue() {
    return _withLock(() async {
      final now = _clock.now();
      if (_lastRunAt != null && now.difference(_lastRunAt!) < policy.minInterval) {
        return null;
      }
      return _runOnceLocked(now);
    });
  }

  /// Cada fuente se intenta con independencia de las demás (P7, mismo
  /// criterio que `DefaultRunPurge` con sus dos purgas y que
  /// `XtreamClient.importChannels` con sus actions): un panel caído no
  /// debe impedir refrescar el resto. A diferencia de `DefaultRunPurge`
  /// (dos jobs fijos, relanza el error tras intentar ambos), aquí son N
  /// fuentes — el fallo se cuenta (`sourcesFailed`), nunca se relanza:
  /// relanzar el error de una fuente cualquiera de entre N no sería más
  /// informativo que el recuento, y rompería la corrida para el resto.
  Future<EpgRefreshStats> _runOnceLocked(DateTime now) async {
    final sources = await _sources.getAll();

    var refreshed = 0;
    var skipped = 0;
    var failed = 0;
    var programmesWritten = 0;

    for (final Source source in sources) {
      if (source.isDeleted || !source.enabled) {
        skipped++;
        continue;
      }
      try {
        final stats = await _ingest.ingestFor(source, now: now);
        if (stats == null) {
          skipped++;
        } else {
          refreshed++;
          programmesWritten += stats.programmesInserted + stats.programmesUpdated;
        }
      } catch (_) {
        failed++;
      }
    }

    _lastRunAt = now;

    return EpgRefreshStats(
      sourcesRefreshed: refreshed,
      sourcesSkipped: skipped,
      sourcesFailed: failed,
      programmesWritten: programmesWritten,
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
