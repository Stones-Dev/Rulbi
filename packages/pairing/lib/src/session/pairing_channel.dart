// El ciclo de vida de los StreamControllers de createInMemoryChannelPair
// es el del par de canales que devuelve la función: los cierra quien
// deje de usar el canal (ReceiverSession/SenderSession cancelan su
// suscripción al terminar), no la función de fábrica en sí.
// ignore_for_file: close_sinks

import 'dart:async';

/// Extremo bidireccional de transporte, inyectado desde fuera: en
/// producción será el canal WebSocket local (plan §4.5); en tests, dos
/// streams en memoria conectados entre sí — sin sockets (P7).
final class PairingChannel {
  const PairingChannel({required this.incoming, required this.outgoing});

  final Stream<List<int>> incoming;
  final StreamSink<List<int>> outgoing;
}

/// Construye un par de canales conectados en memoria: lo que uno envía
/// por [PairingChannel.outgoing] llega al otro por
/// [PairingChannel.incoming], y viceversa.
(PairingChannel, PairingChannel) createInMemoryChannelPair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  final channelA = PairingChannel(incoming: bToA.stream, outgoing: aToB.sink);
  final channelB = PairingChannel(incoming: aToB.stream, outgoing: bToA.sink);
  return (channelA, channelB);
}
