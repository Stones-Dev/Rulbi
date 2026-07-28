import 'dart:async';
import 'dart:isolate';

import 'package:iptv_core/iptv_core.dart';

import 'import_report.dart';
import 'm3u_core_parser.dart';

/// Resultado de [parseM3u]: el stream de canales (pásalo tal cual a
/// `ChannelRepository.replaceSourceContent`/`ManageSources.addSource`) y,
/// una vez que termina de emitir, el informe de descartes.
class M3uParseOutcome {
  const M3uParseOutcome({required this.channels, required this.report});

  final Stream<Channel> channels;

  /// Completa cuando [channels] agota su emisión (con éxito o con error).
  final Future<ImportReport> report;
}

/// Parsea un M3U en un `Isolate` dedicado (P1: no bloquea el isolate
/// llamador con archivos grandes — RNF-01, ~100k canales). El isolate
/// llamador solo actúa de proxy de bytes; todo el trabajo de decodificar
/// y parsear ocurre en el worker (ver `m3u_core_parser.dart`, que se
/// testea aparte sin isolate real por velocidad).
///
/// El parseo empieza solo cuando alguien escucha [M3uParseOutcome.channels]
/// (`onListen` diferido): si nadie escucha, no se spawnea isolate ni se
/// consume [bytes].
M3uParseOutcome parseM3u({
  required Stream<List<int>> bytes,
  required String sourceId,
  int batchSize = 500,
}) {
  final controller = StreamController<Channel>();
  final reportCompleter = Completer<ImportReport>();

  controller.onListen = () {
    final discarded = <DiscardedLine>[];
    var parsedCount = 0;

    unawaited(
      _runWorker(
            bytes: bytes,
            sourceId: sourceId,
            batchSize: batchSize,
            onBatch: (batch) {
              parsedCount += batch.length;
              for (final channel in batch) {
                controller.add(channel);
              }
            },
            onDiscard: discarded.add,
          )
          .then((_) {
            reportCompleter.complete(
              ImportReport(
                parsed: parsedCount,
                discarded: List.unmodifiable(discarded),
              ),
            );
            controller.close();
          })
          .catchError((Object error, StackTrace stack) {
            controller.addError(error, stack);
            controller.close();
            if (!reportCompleter.isCompleted) {
              reportCompleter.completeError(error, stack);
            }
          }),
    );
  };

  return M3uParseOutcome(channels: controller.stream, report: reportCompleter.future);
}

/// Handshake + relé de mensajes con el isolate worker. Ver diseño en el
/// plan de T1.2: el llamador crea un puerto de resultados, spawnea el
/// worker, recibe de vuelta el puerto de bytes del worker (primer
/// mensaje), y desde ahí bombea [bytes] hacia el worker mientras drena
/// lotes/descartes hasta el mensaje de fin.
Future<void> _runWorker({
  required Stream<List<int>> bytes,
  required String sourceId,
  required int batchSize,
  required void Function(List<Channel> batch) onBatch,
  required void Function(DiscardedLine line) onDiscard,
}) async {
  final resultsPort = ReceivePort();
  final results = StreamIterator<dynamic>(resultsPort);
  final isolate = await Isolate.spawn(
    _isolateEntryPoint,
    _StartMessage(resultsPort.sendPort, sourceId, batchSize),
  );

  StreamSubscription<List<int>>? inputSubscription;
  try {
    if (!await results.moveNext()) {
      throw StateError('El isolate del parser M3U terminó sin anunciarse.');
    }
    final ready = results.current as _Ready;

    inputSubscription = bytes.listen(
      ready.bytesPort.send,
      onError: (Object error, StackTrace stack) {
        ready.bytesPort.send(_InputFailed(error.toString()));
      },
      onDone: () => ready.bytesPort.send(null),
      cancelOnError: true,
    );

    while (await results.moveNext()) {
      switch (results.current) {
        case _Batch(:final channels):
          onBatch(channels);
        case _Discard(:final line):
          onDiscard(line);
        case _Done():
          return;
        case _Failed(:final errorMessage):
          throw StateError('Fallo en el isolate del parser M3U: $errorMessage');
        case _Ready():
          // Ya consumido arriba; no debería repetirse.
          break;
      }
    }
  } finally {
    await inputSubscription?.cancel();
    await results.cancel();
    isolate.kill(priority: Isolate.immediate);
  }
}

class _StartMessage {
  _StartMessage(this.resultsPort, this.sourceId, this.batchSize);
  final SendPort resultsPort;
  final String sourceId;
  final int batchSize;
}

sealed class _WorkerEvent {}

final class _Ready extends _WorkerEvent {
  _Ready(this.bytesPort);
  final SendPort bytesPort;
}

final class _Batch extends _WorkerEvent {
  _Batch(this.channels);
  final List<Channel> channels;
}

final class _Discard extends _WorkerEvent {
  _Discard(this.line);
  final DiscardedLine line;
}

final class _Done extends _WorkerEvent {}

final class _Failed extends _WorkerEvent {
  _Failed(this.errorMessage);
  final String errorMessage;
}

/// Enviado por el isolate llamador al puerto de bytes del worker cuando
/// el stream de entrada falla (en vez de intentar reenviar la excepción
/// original, que podría no ser sendable entre isolates).
class _InputFailed {
  _InputFailed(this.message);
  final String message;
}

/// Punto de entrada del isolate worker. Debe ser una función de nivel
/// superior (no un closure) para `Isolate.spawn`.
void _isolateEntryPoint(_StartMessage start) async {
  final bytesPort = ReceivePort();
  start.resultsPort.send(_Ready(bytesPort.sendPort));

  try {
    await for (final event in parseM3uCore(
      bytes: _byteStreamFromPort(bytesPort),
      sourceId: start.sourceId,
      batchSize: start.batchSize,
    )) {
      switch (event) {
        case M3uChannelBatch(:final channels):
          start.resultsPort.send(_Batch(channels));
        case M3uDiscard(:final line):
          start.resultsPort.send(_Discard(line));
      }
    }
    start.resultsPort.send(_Done());
  } catch (error) {
    start.resultsPort.send(_Failed(error.toString()));
  } finally {
    bytesPort.close();
  }
}

Stream<List<int>> _byteStreamFromPort(ReceivePort port) async* {
  await for (final message in port) {
    if (message == null) return; // fin de entrada, ver parseM3u/_runWorker.
    if (message is _InputFailed) {
      throw StateError('Error leyendo la entrada: ${message.message}');
    }
    yield message as List<int>;
  }
}
