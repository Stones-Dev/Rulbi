/// Persistencia local: drift/SQLite + FTS5, repositorios y almacén seguro
/// de credenciales Xtream (Keychain/Keystore). Ver `.specify/plan.md` §4.2.
///
/// **Nota de arquitectura (T1.5)**: este paquete queda deliberadamente
/// fuera del Dart native workspace raíz — ver el comentario en el
/// `pubspec.yaml` de la raíz y en el de este paquete.
library;

export 'src/db/database.dart';
export 'src/repositories/channel_repository.dart';
export 'src/repositories/epg_repository.dart';
export 'src/repositories/favorites_repository.dart';
export 'src/repositories/paired_device_repository.dart';
export 'src/repositories/source_repository.dart';
export 'src/repositories/watch_state_repository.dart';
