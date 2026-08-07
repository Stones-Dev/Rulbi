import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import '../db/database.dart';

/// Puerto del escritor XMLTV→drift (ADR-008, S5 · Ola 2). Vive en `data`,
/// no en `core`: `XmltvEntry` es vocabulario del formato de origen (P6),
/// igual que `ImportReport` de M3U — `core` no puede conocerlo, pero
/// `data` sí puede depender de `protocols` (regla de dependencias del
/// monorepo). Interfaz separada de `DriftXmltvEpgWriter` (en vez de que
/// `apps/app` dependa directamente de la clase concreta) para que
/// `ImportController` pueda fakearla en sus tests sin isolate ni SQLite
/// real — mismo criterio que `ImportChannelSource`/`EpgSource`.
abstract interface class XmltvEpgWriter {
  Future<EpgImportStats> write(Stream<XmltvEntry> entries, {required DateTime now});
}

/// Implementación real de [XmltvEpgWriter]: consume el `Stream<XmltvEntry>`
/// de `parseXmltv` (`packages/protocols`) y hace upsert en
/// `epg_programmes`/`epg_channels`.
///
/// Procesa el stream en lotes acotados ([batchSize], mismo valor que
/// `DriftChannelRepository`/`DriftEpgRepository.purgeOutsideWindow`), con
/// una transacción por lote y cesión real (macrotask) entre lotes: un
/// XMLTV real puede pesar cientos de MB, y retener el lock de escritura de
/// SQLite durante todo el import bloquearía cualquier otra operación
/// concurrente (mismo riesgo, misma mitigación que esos dos).
final class DriftXmltvEpgWriter implements XmltvEpgWriter {
  DriftXmltvEpgWriter(this._db, {this.batchSize = 500});

  final IptvDatabase _db;

  /// Mismo valor por defecto que `DriftChannelRepository`/
  /// `DriftEpgRepository.purgeOutsideWindow`, ajustable en tests (mismo
  /// criterio que `ChannelPageCache.pageSize`) para poder cruzar un límite
  /// de lote con un número pequeño y determinista de entradas, en vez de
  /// depender de una carrera de temporizadores con 500 reales.
  final int batchSize;

  @override
  Future<EpgImportStats> write(
    Stream<XmltvEntry> entries, {
    required DateTime now,
  }) async {
    var programmesInserted = 0;
    var programmesUpdated = 0;
    var programmesUnchanged = 0;
    var channelsInserted = 0;
    var channelsUpdated = 0;
    var channelsUnchanged = 0;
    var duplicateKeys = 0;

    // Claves ya vistas en TODO el stream (no solo en el lote en curso):
    // un duplicado que cae en dos lotes distintos sigue siendo un
    // duplicado del mismo XMLTV (ADR-008 §Decisión 3), y el segundo lote
    // ya sobreescribe al primero vía upsert — este set solo existe para
    // contarlo, no para decidir qué se escribe, así que su coste de
    // memoria es O(claves), no O(filas).
    final seenProgrammeKeys = <String>{};
    final seenChannelIds = <String>{};

    var bufferedProgrammes = <String, EpgProgramme>{};
    var bufferedChannels = <String, XmltvChannel>{};
    var bufferedCount = 0;

    Future<void> flush() async {
      if (bufferedProgrammes.isEmpty && bufferedChannels.isEmpty) return;
      final stats = await _flushBatch(bufferedProgrammes, bufferedChannels);
      programmesInserted += stats.programmesInserted;
      programmesUpdated += stats.programmesUpdated;
      programmesUnchanged += stats.programmesUnchanged;
      channelsInserted += stats.channelsInserted;
      channelsUpdated += stats.channelsUpdated;
      channelsUnchanged += stats.channelsUnchanged;
      bufferedProgrammes = {};
      bufferedChannels = {};
      bufferedCount = 0;
      // Cesión real entre lotes — mismo patrón que
      // `DriftEpgRepository.purgeOutsideWindow`.
      await Future<void>.delayed(Duration.zero);
    }

    await for (final entry in entries) {
      switch (entry) {
        case XmltvProgrammeEntry(:final programme):
          final key = _programmeKey(programme.tvgId, programme.start);
          if (!seenProgrammeKeys.add(key)) duplicateKeys++;
          bufferedProgrammes[key] = programme;
        case XmltvChannelEntry(:final channel):
          if (!seenChannelIds.add(channel.id)) duplicateKeys++;
          bufferedChannels[channel.id] = channel;
      }
      bufferedCount++;
      if (bufferedCount >= batchSize) await flush();
    }
    await flush();

    return EpgImportStats(
      programmesInserted: programmesInserted,
      programmesUpdated: programmesUpdated,
      programmesUnchanged: programmesUnchanged,
      channelsInserted: channelsInserted,
      channelsUpdated: channelsUpdated,
      channelsUnchanged: channelsUnchanged,
      duplicateKeys: duplicateKeys,
    );
  }

  /// Escribe un lote ya deduplicado (última entrada gana, ver [write]) en
  /// su propia transacción. Consulta solo las filas existentes que
  /// podrían solaparse con este lote (`tvgId IN (...)` de este lote, no de
  /// toda la tabla) — sobre-trae algo (todas las filas de ese `tvgId`, no
  /// solo las de `start` coincidente), pero eso está acotado por la
  /// ventana del propio XMLTV, y evita mantener un snapshot de toda
  /// `epg_programmes` en memoria (que sí sería un problema real con la PK
  /// global de ADR-008).
  Future<EpgImportStats> _flushBatch(
    Map<String, EpgProgramme> programmes,
    Map<String, XmltvChannel> channels,
  ) async {
    return _db.transaction(() async {
      final programmesStats = await _flushProgrammes(programmes);
      final channelsStats = await _flushChannels(channels);
      return EpgImportStats(
        programmesInserted: programmesStats.$1,
        programmesUpdated: programmesStats.$2,
        programmesUnchanged: programmesStats.$3,
        channelsInserted: channelsStats.$1,
        channelsUpdated: channelsStats.$2,
        channelsUnchanged: channelsStats.$3,
        duplicateKeys: 0,
      );
    });
  }

  Future<(int, int, int)> _flushProgrammes(
    Map<String, EpgProgramme> programmes,
  ) async {
    if (programmes.isEmpty) return (0, 0, 0);

    final tvgIds = programmes.values.map((p) => p.tvgId).toSet().toList();
    final existingRows =
        await (_db.select(_db.epgProgrammes)..where((p) => p.tvgId.isIn(tvgIds)))
            .get();
    final existingByKey = {
      for (final row in existingRows) _programmeKey(row.tvgId, row.start): row,
    };

    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    final toWrite = <EpgProgrammesCompanion>[];

    for (final entry in programmes.entries) {
      final programme = entry.value;
      final existing = existingByKey[entry.key];
      if (existing == null) {
        inserted++;
        toWrite.add(_programmeCompanion(programme));
      } else if (existing.stop.isAtSameMomentAs(programme.stop) &&
          existing.title == programme.title &&
          existing.description == programme.description) {
        // `isAtSameMomentAs`, no `==`: drift reconstruye `stop` como hora
        // local al leerlo de vuelta, y `DateTime.==` (a diferencia de
        // `isBefore`/`isAfter`/`isAtSameMomentAs`) sí distingue UTC de
        // local aunque sea el mismo instante — con `==` esta rama nunca
        // se alcanzaba y todo se clasificaba como `updated`.
        unchanged++;
      } else {
        updated++;
        toWrite.add(_programmeCompanion(programme));
      }
    }

    if (toWrite.isNotEmpty) {
      await _db.batch(
        (b) => b.insertAll(
          _db.epgProgrammes,
          toWrite,
          mode: InsertMode.insertOrReplace,
        ),
      );
    }
    return (inserted, updated, unchanged);
  }

  Future<(int, int, int)> _flushChannels(
    Map<String, XmltvChannel> channels,
  ) async {
    if (channels.isEmpty) return (0, 0, 0);

    final tvgIds = channels.keys.toList();
    final existingRows =
        await (_db.select(_db.epgChannels)..where((c) => c.tvgId.isIn(tvgIds)))
            .get();
    final existingByTvgId = {for (final row in existingRows) row.tvgId: row};

    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    final toWrite = <EpgChannelsCompanion>[];

    for (final entry in channels.entries) {
      final channel = entry.value;
      final companion = _channelCompanion(channel);
      final existing = existingByTvgId[entry.key];
      if (existing == null) {
        inserted++;
        toWrite.add(companion);
      } else if (existing.displayNamesJson == companion.displayNamesJson.value &&
          existing.icon == companion.icon.value &&
          existing.urlsJson == companion.urlsJson.value) {
        unchanged++;
      } else {
        updated++;
        toWrite.add(companion);
      }
    }

    if (toWrite.isNotEmpty) {
      await _db.batch(
        (b) => b.insertAll(
          _db.epgChannels,
          toWrite,
          mode: InsertMode.insertOrReplace,
        ),
      );
    }
    return (inserted, updated, unchanged);
  }

  EpgProgrammesCompanion _programmeCompanion(EpgProgramme programme) =>
      EpgProgrammesCompanion.insert(
        tvgId: programme.tvgId,
        start: programme.start,
        stop: programme.stop,
        title: programme.title,
        description: Value(programme.description),
      );

  EpgChannelsCompanion _channelCompanion(XmltvChannel channel) =>
      EpgChannelsCompanion.insert(
        tvgId: channel.id,
        displayNamesJson: jsonEncode(channel.displayNames),
        icon: Value(channel.icon?.toString()),
        urlsJson: jsonEncode([for (final url in channel.urls) url.toString()]),
      );

  /// Separador que no aparece en un `tvgId` real (los mismos que usa
  /// `content_hash.dart` para su propio delimitador de campos) — clave
  /// compuesta en memoria para deduplicar por `(tvgId, start)` sin
  /// necesitar un `Record` como clave de `Map` (funciona, pero una
  /// `String` es más barata de comparar en el hot path del `await for`).
  String _programmeKey(String tvgId, DateTime start) =>
      '$tvgId${start.toUtc().microsecondsSinceEpoch}';
}
