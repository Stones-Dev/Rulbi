import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_data/iptv_data.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import 'delete_source.dart';
import 'import_controller.dart';
import 'm3u_probe.dart';
import 'save_source.dart';
import 'xtream_probe.dart';

/// Cableado de Riverpod para el alta de fuentes (S4 · Ola 2). La BD y el
/// almacén seguro se abren una sola vez por proceso de app (`Provider`
/// simple, no `autoDispose`): los formularios de M3U/Xtream de esta ola y,
/// en Ola 3, la pantalla de Gestión de fuentes, comparten la misma
/// instancia — ninguno de los dos formularios cierra la BD al salir.
final iptvDatabaseProvider = Provider<IptvDatabase>((ref) {
  final db = IptvDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return DriftSourceRepository(ref.watch(iptvDatabaseProvider));
});

final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  return FlutterSecureCredentialStore();
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// `RetryingXtreamTransport(HttpXtreamTransport())` — mismo par usado por
/// `packages/protocols` en producción (T1.4): backoff ante 429 sobre
/// transporte HTTP real. Se construye por *probe* (`transportFactory`),
/// nunca compartido, para que cada intento de "Probar conexión" parta de
/// un transporte limpio.
final m3uProbeProvider = Provider<M3uProbe>((ref) => HttpM3uProbe());

final xtreamProbeProvider = Provider<XtreamProbe>((ref) {
  return XtreamClientProbe(
    transportFactory: () => RetryingXtreamTransport(HttpXtreamTransport()),
  );
});

final saveSourceProvider = Provider<SaveSource>((ref) {
  return SaveSource(
    sources: ref.watch(sourceRepositoryProvider),
    secureStore: ref.watch(secureCredentialStoreProvider),
    clock: ref.watch(clockProvider),
  );
});

final deleteSourceProvider = Provider<DeleteSource>((ref) {
  return DeleteSource(
    sources: ref.watch(sourceRepositoryProvider),
    secureStore: ref.watch(secureCredentialStoreProvider),
    clock: ref.watch(clockProvider),
  );
});

/// UI de importación (S4 · Ola 3, ui-spec §2.14).
final channelRepositoryProvider = Provider<ChannelRepository>((ref) {
  return DriftChannelRepository(ref.watch(iptvDatabaseProvider));
});

final manageSourcesProvider = Provider<ManageSources>((ref) {
  return DefaultManageSources(
    ref.watch(sourceRepositoryProvider),
    ref.watch(channelRepositoryProvider),
    ref.watch(clockProvider),
  );
});

final m3uImportChannelSourceProvider = Provider<ImportChannelSource>((ref) {
  return M3uImportChannelSource();
});

/// Mismo par de transporte que [xtreamProbeProvider] — ver su docstring:
/// se construye de nuevo en cada import, nunca compartido.
final xtreamImportChannelSourceProvider = Provider<ImportChannelSource>((ref) {
  return XtreamImportChannelSource(
    transportFactory: () => RetryingXtreamTransport(HttpXtreamTransport()),
  );
});
