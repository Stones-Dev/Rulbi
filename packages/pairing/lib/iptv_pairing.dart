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

export 'src/session/pairing_channel.dart';
export 'src/session/pairing_qr_payload.dart';
export 'src/session/pairing_session_errors.dart';
export 'src/session/pairing_session_state.dart';
export 'src/session/receiver_session.dart';
export 'src/session/sender_session.dart';
export 'src/session/session_crypto.dart';
export 'src/session/six_digit_code.dart';
export 'src/session/x25519_session_crypto.dart';
