import 'package:iptv_core/iptv_core.dart';

/// `EpgRepository` en memoria (S5 · Ola 2) — reutilizable entre pantallas
/// que pintan `ChannelRow` con `epgController` no nulo (`ChannelListScreen`,
/// `FavoritesScreen`): sin overridear este provider, `createEpgNowController`
/// dispara `iptvDatabaseProvider` de verdad durante un widget test.
final class FakeEpgRepository implements EpgRepository {
  final List<EpgProgramme> _programmes = [];

  void seed(EpgProgramme programme) => _programmes.add(programme);

  @override
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    required DateTime from,
    required DateTime to,
  }) async => _programmes.where((p) => p.tvgId == tvgId).toList();

  @override
  Future<EpgNowIndex> nowAndNextFor(Set<String> tvgIds, DateTime at) async {
    final entries = <String, EpgNowNext>{};
    for (final tvgId in tvgIds) {
      final forChannel =
          _programmes.where((p) => p.tvgId == tvgId).toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      if (forChannel.isEmpty) continue;

      EpgProgramme? now;
      EpgProgramme? next;
      for (final programme in forChannel) {
        if (!programme.start.isAfter(at) && programme.stop.isAfter(at)) {
          now = programme;
        } else if (programme.start.isAfter(at)) {
          next ??= programme;
        }
      }
      entries[tvgId] = EpgNowNext(now: now, next: next);
    }
    return EpgNowIndex(at: at, entries: entries);
  }

  @override
  Future<int> purgeOutsideWindow({
    required DateTime from,
    required DateTime to,
  }) async => 0;
}
