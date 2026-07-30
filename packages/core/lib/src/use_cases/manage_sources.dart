import 'dart:async';

import '../entities/channel.dart';
import '../entities/source.dart';
import '../ports/channel_repository.dart';
import '../ports/clock.dart';
import '../ports/source_repository.dart';

/// Añadir y refrescar una fuente (upsert diferencial que preserva
/// favoritos y progreso, plan §4.2).
///
/// La firma toma un `Stream<Channel>` porque quien lo produce es el
/// parser de `packages/protocols` (T1.2/T1.4) — `core` no conoce el
/// parser (P6). Un XMLTV **no** entra por aquí: `parseXmltv` produce
/// `Stream<XmltvEntry>` (canales de guía + programas), no `Channel` — es
/// una fuente de EPG, se une por `tvgId`, y su escritura a `data` vive en
/// la tarea "Ventana y purga EPG" (S2), con su propio ADR.
abstract interface class ManageSources {
  /// Crea la fuente y hace la primera importación completa a partir de
  /// [channels]. Devuelve el [Source] persistido (con `lastRefresh` ya
  /// actualizado) junto al recuento del upsert diferencial (T1.9).
  Future<(Source, SourceImportStats)> addSource(
    Source source,
    Stream<Channel> channels,
  );

  /// Refresca una fuente existente: upsert diferencial que preserva
  /// favoritos y watch-state indexados por `ChannelRef` (ADR-003), no un
  /// borrado + reinserción completa. Falla si `sourceId` no existe o si
  /// la fuente está eliminada (tombstone) — refrescar algo que ya no
  /// existe no tiene un resultado con sentido.
  Future<SourceImportStats> refreshSource(
    String sourceId,
    Stream<Channel> channels,
  );
}

/// Implementación real (T1.6b): orquesta [SourceRepository] y
/// [ChannelRepository], pero no sabe SQL — el diff campo a campo vive en
/// la implementación concreta de `ChannelRepository` (`data`, T1.5),
/// indexado por `ChannelRef`.
///
/// Serializa los imports de una misma fuente (un mapa de `sourceId` a
/// `Future<void>` encadenado, patrón mutex-por-future estándar en Dart):
/// dos `refreshSource`/`addSource` concurrentes sobre el mismo `sourceId`
/// se ejecutan uno tras otro, nunca solapados — sin esto, el segundo
/// leería un snapshot previo a los inserts del primero y tumbaría
/// canales que el primero acaba de insertar. Es un cerrojo *in-process*:
/// no protege contra dos procesos/isolates distintos abriendo la misma
/// BD a la vez, pero la app tiene un único punto de escritura, así que no
/// es un agujero real hoy (ver riesgos de T1.6b).
final class DefaultManageSources implements ManageSources {
  DefaultManageSources(this._sources, this._channels, this._clock);

  final SourceRepository _sources;
  final ChannelRepository _channels;
  final Clock _clock;

  final Map<String, Future<void>> _tails = {};

  @override
  Future<(Source, SourceImportStats)> addSource(
    Source source,
    Stream<Channel> channels,
  ) {
    return _withLock(source.id, () async {
      await _sources.upsert(source);
      final stats = await _channels.importSourceContent(
        source.id,
        channels,
        now: _clock.now(),
      );
      final refreshed = source.withRefreshed(_clock.now());
      await _sources.upsert(refreshed);
      return (refreshed, stats);
    });
  }

  @override
  Future<SourceImportStats> refreshSource(
    String sourceId,
    Stream<Channel> channels,
  ) {
    return _withLock(sourceId, () async {
      final existing = await _sources.getById(sourceId);
      if (existing == null) {
        throw StateError('No existe una fuente con id "$sourceId".');
      }
      if (existing.isDeleted) {
        throw StateError('La fuente "$sourceId" está eliminada.');
      }

      final stats = await _channels.importSourceContent(
        sourceId,
        channels,
        now: _clock.now(),
      );
      await _sources.upsert(existing.withRefreshed(_clock.now()));
      return stats;
    });
  }

  /// Encadena [action] tras cualquier import en curso para el mismo
  /// [sourceId]. Publica su propio `Completer` como la nueva "cola" antes
  /// de esperar a la anterior, para que un tercer llamador concurrente
  /// también se encole detrás de este y no de la fuente original.
  Future<T> _withLock<T>(String sourceId, Future<T> Function() action) async {
    final previousTail = _tails[sourceId] ?? Future<void>.value();
    final completer = Completer<void>();
    _tails[sourceId] = completer.future;

    await previousTail;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
