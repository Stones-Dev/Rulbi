/// Estados de una sesión de emparejamiento (receptor o emisor, T1.7).
enum PairingSessionState {
  idle,
  advertising,
  challenged,
  established,
  transferring,
  done,
  failed,
}
