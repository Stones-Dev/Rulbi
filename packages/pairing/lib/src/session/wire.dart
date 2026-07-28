import 'dart:convert';
import 'dart:typed_data';

/// Formato de mensaje interno del protocolo de sesión — deliberadamente
/// no exportado del paquete: es un detalle de implementación entre
/// `ReceiverSession` y `SenderSession`, no un contrato público. Provisional
/// (JSON sobre el canal), como el resto de `session/` (ver
/// `SessionCrypto`): puede cambiar sin que el resto del paquete lo note.
const pairingConfirmationPhrase = 'iptv-pairing-ok';

Uint8List encodeMessage(Map<String, Object?> message) =>
    Uint8List.fromList(utf8.encode(jsonEncode(message)));

Map<String, Object?> decodeMessage(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
