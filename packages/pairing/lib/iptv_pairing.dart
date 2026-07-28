/// Emparejamiento QR/código de 6 dígitos, canal WebSocket local cifrado y
/// motor de merge LWW con tombstones. Ver ADR-002/ADR-003 en el vault y
/// `.specify/ui-spec.md` §3 (contratos de datos). Paquete Dart puro,
/// testeable sin red (streams en memoria).
library;

export 'src/config_package.dart';
export 'src/lww_merger.dart';

export 'src/serialization/channel_ref_codec.dart';
export 'src/serialization/favorite_codec.dart';
export 'src/serialization/source_codec.dart';
export 'src/serialization/watch_state_codec.dart';
