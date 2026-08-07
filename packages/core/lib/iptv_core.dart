/// Dominio puro del reproductor IPTV: entidades, casos de uso y puertos
/// (p. ej. `PlayerPort`). No depende de Flutter ni de ninguna API de
/// plataforma — ver principio P6 de la constitution en `.specify/`.
library;

export 'src/entities/category.dart';
export 'src/entities/channel.dart';
export 'src/entities/channel_query.dart';
export 'src/entities/content_type.dart';
export 'src/entities/epg_now_index.dart';
export 'src/entities/epg_programme.dart';
export 'src/entities/favorite.dart';
export 'src/entities/paired_device.dart';
export 'src/entities/source.dart';
export 'src/entities/watch_state.dart';

export 'src/ports/channel_repository.dart';
export 'src/ports/channel_search_port.dart';
export 'src/ports/clock.dart';
export 'src/ports/epg_ingest.dart';
export 'src/ports/epg_repository.dart';
export 'src/ports/favorites_repository.dart';
export 'src/ports/paired_device_repository.dart';
export 'src/ports/secure_credential_store.dart';
export 'src/ports/source_repository.dart';
export 'src/ports/watch_state_repository.dart';

export 'src/sync/channel_ref.dart';
export 'src/sync/lww.dart';
export 'src/sync/syncable.dart';

export 'src/text/normalize.dart';

export 'src/use_cases/get_continue_watching.dart';
export 'src/use_cases/manage_favorites.dart';
export 'src/use_cases/manage_sources.dart';
export 'src/use_cases/periodic_job_scheduler.dart';
export 'src/use_cases/run_epg_refresh.dart';
export 'src/use_cases/run_purge.dart';
export 'src/use_cases/search_channels.dart';
export 'src/use_cases/track_watch_progress.dart';
