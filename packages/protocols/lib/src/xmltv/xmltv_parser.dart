import 'dart:async';
import 'dart:isolate';

import 'xmltv_core_parser.dart';
import 'xmltv_entry.dart';
import 'xmltv_report.dart';
import 'xmltv_window.dart';

/// Resultado de [parseXmltv]: el stream de canales/programas
/// entrelazados (pásalo a la escritura por lotes de `data`) y, una vez
/// que termina de emitir, el informe de tolerancia.
class XmltvParseOutcome {
  const XmltvParseOutcome({required this.entries, required this.report});

  final Stream<XmltvEntry> entries;

  /// Completa cuando [entries] agota su emisión (con éxito o con error).
  final Future<XmltvImportReport> report;
}

/// Parsea un XMLTV en un `Isolate` dedicado (P1, mismo patrón que
/// `parseM3u` de T1.2: no bloquea el isolate llamador con documentos de
/// cientos de MB). El isolate llamador solo actúa de proxy de bytes; todo
/// el trabajo de gunzip, decodificación y parseo ocurre en el worker (ver
/// `xmltv_core_parser.dart`, testeado aparte sin isolate real por
/// velocidad).
///
/// El parseo empieza solo cuando alguien escucha
/// [XmltvParseOutcome.entries] (`onListen` diferido): si nadie escucha, no
/// se spawnea isolate ni se consume [bytes].
XmltvParseOutcome parseXmltv({
  required Stream<List<int>> bytes,
  required XmltvWindow window,
  int batchSize = 500,
}) {
  final controller = StreamController<XmltvEntry>();
  final reportCompleter = Completer<XmltvImportReport>();

  controller.onListen = () {
    final builder = XmltvReportBuilder();

    unawaited(
      _runWorker(
            bytes: bytes,
            window: window,
            batchSize: batchSize,
            onBatch: (batch) {
              for (final entry in batch) {
                controller.add(entry);
              }
            },
            onDiscard: builder.addDiscard,
            onSummary: (summary) => builder.applySummary(
              parsedChannels: summary.parsedChannels,
              parsedProgrammes: summary.parsedProgrammes,
              outOfWindowProgrammes: summary.outOfWindowProgrammes,
              assumedUtcDates: summary.assumedUtcDates,
              unknownChannelRefs: summary.unknownChannelRefs,
              unknownTags: summary.unknownTags,
            ),
          )
          .then((_) {
            reportCompleter.complete(builder.build());
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

  return XmltvParseOutcome(
    entries: controller.stream,
    report: reportCompleter.future,
  );
}

/// Handshake + relé de mensajes con el isolate worker. Mismo diseño que
/// `_runWorker` de `m3u_parser.dart` (T1.2): el llamador crea un puerto de
/// resultados, spawnea el worker, recibe de vuelta el puerto de bytes del
/// worker (primer mensaje), y desde ahí bombea [bytes] hacia el worker
/// mientras drena lotes/descartes/resumen hasta el mensaje de fin.
Future<void> _runWorker({
  required Stream<List<int>> bytes,
  required XmltvWindow window,
  required int batchSize,
  required void Function(List<XmltvEntry> batch) onBatch,
  required void Function(XmltvDiscard discard) onDiscard,
  required void Function(XmltvSummary summary) onSummary,
}) async {
  final resultsPort = ReceivePort();
  final results = StreamIterator<dynamic>(resultsPort);
  final isolate = await Isolate.spawn(
    _isolateEntryPoint,
    _StartMessage(resultsPort.sendPort, window, batchSize),
  );

  StreamSubscription<List<int>>? inputSubscription;
  try {
    if (!await results.moveNext()) {
      throw StateError('El isolate del parser XMLTV terminó sin anunciarse.');
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
        case _Batch(:final entries):
          onBatch(entries);
        case _Discard(:final discard):
          onDiscard(discard);
        case _Summary(:final summary):
          onSummary(summary);
        case _Done():
          return;
        case _Failed(:final errorMessage):
          throw StateError(
            'Fallo en el isolate del parser XMLTV: $errorMessage',
          );
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
  _StartMessage(this.resultsPort, this.window, this.batchSize);
  final SendPort resultsPort;
  final XmltvWindow window;
  final int batchSize;
}

sealed class _WorkerEvent {}

final class _Ready extends _WorkerEvent {
  _Ready(this.bytesPort);
  final SendPort bytesPort;
}

final class _Batch extends _WorkerEvent {
  _Batch(this.entries);
  final List<XmltvEntry> entries;
}

final class _Discard extends _WorkerEvent {
  _Discard(this.discard);
  final XmltvDiscard discard;
}

final class _Summary extends _WorkerEvent {
  _Summary(this.summary);
  final XmltvSummary summary;
}

final class _Done extends _WorkerEvent {}

final class _Failed extends _WorkerEvent {
  _Failed(this.errorMessage);
  final String errorMessage;
}

/// Enviado por el isolate llamador al puerto de bytes del worker cuando
/// el stream de entrada falla (en vez de intentar reenviar la excepción
/// original, que podría no ser sendable entre isolates). A diferencia de
/// un XMLTV interno truncado/corrupto (que `parseXmltvCore` ya convierte
/// en un descarte, P7), esto es un fallo real de la fuente de bytes —
/// se propaga como error del stream, no se disuelve en el informe.
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
    await for (final event in parseXmltvCore(
      bytes: _byteStreamFromPort(bytesPort),
      window: start.window,
      batchSize: start.batchSize,
    )) {
      switch (event) {
        case XmltvBatch(:final entries):
          start.resultsPort.send(_Batch(entries));
        case XmltvCoreDiscard(:final discard):
          start.resultsPort.send(_Discard(discard));
        case XmltvSummary():
          start.resultsPort.send(_Summary(event));
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
    if (message == null) return; // fin de entrada, ver parseXmltv/_runWorker.
    if (message is _InputFailed) {
      throw StateError('Error leyendo la entrada: ${message.message}');
    }
    yield message as List<int>;
  }
}
