import 'package:iptv_core/iptv_core.dart';
import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

import 'xmltv_date.dart';
import 'xmltv_encoding.dart';
import 'xmltv_entry.dart';
import 'xmltv_report.dart';
import 'xmltv_window.dart';

/// Eventos internos del parser núcleo (no isolate-aware — eso lo añade el
/// wrapper público `parseXmltv` de `xmltv_parser.dart`, spawneando esta
/// función dentro de un `Isolate`, mismo patrón que M3U/T1.2). Se testea
/// directamente para no pagar el coste de un isolate real en cada caso
/// límite.
sealed class XmltvCoreEvent {}

/// Un lote de canales y/o programas parseados con éxito y, en el caso de
/// los programas, dentro de la ventana temporal.
final class XmltvBatch extends XmltvCoreEvent {
  XmltvBatch(this.entries);
  final List<XmltvEntry> entries;
}

/// Un `<channel>`/`<programme>` que no se pudo emitir. Nunca se lanza una
/// excepción por esto (P7): se reporta y se sigue.
final class XmltvCoreDiscard extends XmltvCoreEvent {
  XmltvCoreDiscard(this.discard);
  final XmltvDiscard discard;
}

/// Emitido una sola vez, al final del stream: los contadores agregados no
/// tienen forma de lista sin cota (ver `XmltvImportReport`) — con un
/// XMLTV real, `outOfWindowProgrammes` puede ser la inmensa mayoría del
/// archivo.
final class XmltvSummary extends XmltvCoreEvent {
  XmltvSummary({
    required this.parsedChannels,
    required this.parsedProgrammes,
    required this.outOfWindowProgrammes,
    required this.assumedUtcDates,
    required this.unknownChannelRefs,
    required this.unknownTags,
  });

  final int parsedChannels;
  final int parsedProgrammes;
  final int outOfWindowProgrammes;
  final int assumedUtcDates;
  final Map<String, int> unknownChannelRefs;
  final Map<String, int> unknownTags;
}

/// Parsea un XMLTV en streaming: decodifica el encoding correcto (gunzip
/// incluido, `xmltv_encoding.dart`), recorre el documento con una máquina
/// de estados sobre eventos SAX (`package:xml`, `toXmlEvents`), filtra
/// programas por [window] **durante** el parseo (P1: memoria acotada, un
/// XMLTV de cientos de MB no puede convertirse en una lista de "todo lo
/// que quedó fuera de rango"), y emite canales/programas en lotes de
/// [batchSize] entrelazados en el orden en que aparecen en el documento.
Stream<XmltvCoreEvent> parseXmltvCore({
  required Stream<List<int>> bytes,
  required XmltvWindow window,
  int batchSize = 500,
}) async* {
  final events = decodeXmltvBytes(
    bytes,
  ).toXmlEvents(withLocation: true).flatten();

  final stack = <_Frame>[_RootFrame()];
  var batch = <XmltvEntry>[];
  var entryIndex = 0;
  var parsedChannels = 0;
  var parsedProgrammes = 0;
  var outOfWindowProgrammes = 0;
  var assumedUtcDates = 0;
  final unknownTags = <String, int>{};
  final declaredChannelIds = <String>{};
  final pendingUnknownRefs = <String, int>{};
  XmltvDiscard? discard;

  void emitDiscard({
    required int index,
    required String reason,
    String? channelId,
    int? charOffset,
  }) {
    discard = XmltvDiscard(
      entryIndex: index,
      reason: reason,
      channelId: channelId,
      charOffset: charOffset,
    );
  }

  void finalizeChannel(_ChannelFrame frame) {
    final index = entryIndex++;
    final id = frame.id;
    if (id == null || id.isEmpty) {
      emitDiscard(
        index: index,
        reason: '<channel> sin atributo id',
        charOffset: frame.charOffset,
      );
      return;
    }
    declaredChannelIds.add(id);
    batch.add(
      XmltvChannelEntry(
        XmltvChannel(
          id: id,
          displayNames: List.unmodifiable(frame.displayNames),
          icon: frame.icon,
          urls: List.unmodifiable(frame.urls),
        ),
      ),
    );
    parsedChannels++;
  }

  void finalizeProgramme(_ProgrammeFrame frame) {
    final index = entryIndex++;
    final channelId = frame.channelId;
    if (channelId == null || channelId.isEmpty) {
      emitDiscard(
        index: index,
        reason: '<programme> sin atributo channel',
        charOffset: frame.charOffset,
      );
      return;
    }
    if (frame.startRaw == null) {
      emitDiscard(
        index: index,
        reason: '<programme> sin atributo start',
        channelId: channelId,
        charOffset: frame.charOffset,
      );
      return;
    }
    final start = parseXmltvDate(frame.startRaw!);
    if (start == null) {
      emitDiscard(
        index: index,
        reason: 'start ilegible: "${frame.startRaw}"',
        channelId: channelId,
        charOffset: frame.charOffset,
      );
      return;
    }
    if (frame.stopRaw == null) {
      emitDiscard(
        index: index,
        reason: '<programme> sin atributo stop',
        channelId: channelId,
        charOffset: frame.charOffset,
      );
      return;
    }
    final stop = parseXmltvDate(frame.stopRaw!);
    if (stop == null) {
      emitDiscard(
        index: index,
        reason: 'stop ilegible: "${frame.stopRaw}"',
        channelId: channelId,
        charOffset: frame.charOffset,
      );
      return;
    }

    if (!window.overlaps(start: start.dateTime, stop: stop.dateTime)) {
      // Fuera de ventana: no es un descarte (P7 — el dato está bien
      // formado), solo un contador. Ver XmltvImportReport.
      outOfWindowProgrammes++;
      return;
    }

    if (start.assumedUtc || stop.assumedUtc) assumedUtcDates++;
    if (!declaredChannelIds.contains(channelId)) {
      // Puede que el <channel> aparezca más adelante en el documento (no
      // conforme al DTD, pero se tolera): se reconcilia al final del
      // stream, no aquí.
      pendingUnknownRefs.update(channelId, (v) => v + 1, ifAbsent: () => 1);
    }

    batch.add(
      XmltvProgrammeEntry(
        EpgProgramme(
          tvgId: channelId,
          start: start.dateTime,
          stop: stop.dateTime,
          // Ausencia de <title> no es un descarte documentado (T1.3): se
          // conserva el programa con título vacío antes que perderlo.
          title: frame.title ?? '',
          description: frame.desc,
        ),
      ),
    );
    parsedProgrammes++;
  }

  _Frame pushFrameFor(
    String name,
    List<XmlEventAttribute> attrs,
    int? charOffset,
  ) {
    final parent = stack.last;
    if (parent is _RootFrame) {
      // Basura antes de <tv> (declaración/comentario ya filtrados aparte,
      // esto es un elemento real): no hay dónde acumularla, se ignora sin
      // contarla como "unknown tag" — todavía no estamos en vocabulario
      // XMLTV.
      return name == 'tv' ? _TvFrame() : _SkipFrame(name);
    }
    if (parent is _TvFrame) {
      if (name == 'channel') {
        return _ChannelFrame(_attr(attrs, 'id'), charOffset: charOffset);
      }
      if (name == 'programme') {
        return _ProgrammeFrame(
          channelId: _attr(attrs, 'channel'),
          startRaw: _attr(attrs, 'start'),
          stopRaw: _attr(attrs, 'stop'),
          charOffset: charOffset,
        );
      }
      unknownTags.update(name, (v) => v + 1, ifAbsent: () => 1);
      return _SkipFrame(name);
    }
    if (parent is _ChannelFrame) {
      switch (name) {
        case 'display-name':
          return _TextChildFrame(_ChildKind.displayName, name);
        case 'icon':
          final src = _attr(attrs, 'src');
          // Primer <icon> gana, misma convención que el primer <title>
          // duplicado de un <programme>.
          if (src != null) parent.icon ??= Uri.tryParse(src);
          return _KnownLeafFrame(name);
        case 'url':
          return _TextChildFrame(_ChildKind.channelUrl, name);
        default:
          unknownTags.update(name, (v) => v + 1, ifAbsent: () => 1);
          return _SkipFrame(name);
      }
    }
    if (parent is _ProgrammeFrame) {
      switch (name) {
        case 'title':
          return _TextChildFrame(_ChildKind.title, name);
        case 'desc':
          return _TextChildFrame(_ChildKind.desc, name);
        case 'sub-title':
          // No lo modela EpgProgramme: se consume para no romper el
          // anidamiento, pero su contenido no se guarda.
          return _KnownLeafFrame(name);
        default:
          unknownTags.update(name, (v) => v + 1, ifAbsent: () => 1);
          return _SkipFrame(name);
      }
    }
    // Dentro de un nodo de texto/hoja que no modela hijos, o ya dentro de
    // un subárbol descartado: cualquier anidamiento se ignora sin
    // contarlo aparte — evita que un <credits><actor/>×97 infle
    // unknownTags con entradas que no aportan nada al informe.
    return _SkipFrame(name);
  }

  void onEnd(String name) {
    if (stack.length <= 1) return; // cierre huérfano: nada que popear.
    if (stack.last.name != name) {
      // Cierre huérfano o mal anidado (validateNesting:false lo permite
      // en la entrada, P7 tolera un documento así): no coincide con lo
      // que hay abierto — se ignora sin popear nada. Popear a ciegas
      // aquí desincronizaría el resto del árbol frente a cualquier
      // etiqueta de cierre suelta.
      return;
    }
    final frame = stack.removeLast();
    final parent = stack.isEmpty ? null : stack.last;
    switch (frame) {
      case _ChannelFrame():
        finalizeChannel(frame);
      case _ProgrammeFrame():
        finalizeProgramme(frame);
      case _TextChildFrame(:final kind, :final buffer):
        final text = buffer.toString();
        switch (kind) {
          case _ChildKind.displayName:
            if (parent is _ChannelFrame) parent.displayNames.add(text);
          case _ChildKind.channelUrl:
            if (parent is _ChannelFrame) {
              final uri = Uri.tryParse(text.trim());
              if (uri != null) parent.urls.add(uri);
            }
          case _ChildKind.title:
            if (parent is _ProgrammeFrame) parent.title ??= text;
          case _ChildKind.desc:
            if (parent is _ProgrammeFrame) parent.desc ??= text;
        }
      case _TvFrame():
      case _KnownLeafFrame():
      case _SkipFrame():
      case _RootFrame():
        // Nada que propagar al padre.
        break;
    }
  }

  void onText(String value) {
    final top = stack.last;
    if (top is _TextChildFrame) top.buffer.write(value);
  }

  void onStart(XmlStartElementEvent event) {
    final frame = pushFrameFor(event.name, event.attributes, event.start);
    stack.add(frame);
    if (event.isSelfClosing) onEnd(event.name);
  }

  try {
    await for (final event in events) {
      switch (event) {
        case XmlStartElementEvent():
          onStart(event);
        case XmlEndElementEvent(:final name):
          onEnd(name);
        case XmlTextEvent(:final value):
          onText(value);
        case XmlCDATAEvent(:final value):
          onText(value);
        default:
        // Declaración, doctype, comentario, processing instruction: sin
        // significado para el modelo de datos, se ignoran.
      }

      if (discard != null) {
        yield XmltvCoreDiscard(discard!);
        discard = null;
      }
      if (batch.length >= batchSize) {
        yield XmltvBatch(List.unmodifiable(batch));
        batch = <XmltvEntry>[];
      }
    }
  } on XmlException catch (error) {
    // Riesgo conocido (T1.3): XmlEventDecoder.close() lanza si queda un
    // "carry" sin parsear al final del stream — un documento truncado a
    // media etiqueta (gunzip roto, descarga cortada) cae aquí. P7: no se
    // relanza. Se reporta como un descarte final y se conserva todo lo ya
    // emitido antes del corte.
    yield XmltvCoreDiscard(
      XmltvDiscard(
        entryIndex: entryIndex,
        reason: 'documento XML interrumpido o corrupto: $error',
      ),
    );
  } on FormatException catch (error) {
    // Mismo tratamiento para corrupción a nivel de bytes (gunzip roto a
    // mitad de stream: dart:io lanza FormatException, no XmlException).
    yield XmltvCoreDiscard(
      XmltvDiscard(
        entryIndex: entryIndex,
        reason: 'documento interrumpido o corrupto (formato): $error',
      ),
    );
  }

  // Un <channel> declarado después de los <programme> que lo referencian
  // (no conforme al DTD, pero real) no debe contar como ref desconocida:
  // la reconciliación ocurre aquí, con el documento completo ya visto.
  for (final id in declaredChannelIds) {
    pendingUnknownRefs.remove(id);
  }

  if (batch.isNotEmpty) {
    yield XmltvBatch(List.unmodifiable(batch));
  }

  yield XmltvSummary(
    parsedChannels: parsedChannels,
    parsedProgrammes: parsedProgrammes,
    outOfWindowProgrammes: outOfWindowProgrammes,
    assumedUtcDates: assumedUtcDates,
    unknownChannelRefs: Map.unmodifiable(pendingUnknownRefs),
    unknownTags: Map.unmodifiable(unknownTags),
  );
}

String? _attr(List<XmlEventAttribute> attrs, String name) {
  for (final a in attrs) {
    if (a.name == name) return a.value;
  }
  return null;
}

/// Cada frame recuerda el nombre del elemento que lo abrió (salvo
/// [_RootFrame], que no corresponde a ningún elemento real). `onEnd`
/// compara este nombre contra el de la etiqueta de cierre antes de
/// popear — una etiqueta huérfana o mal anidada (posible: `validateNesting`
/// va en `false`) no debe desincronizar el resto del árbol.
sealed class _Frame {
  String get name;
}

/// Antes de ver `<tv>`. Nunca se popea (es la base de la pila) — su
/// [name] no se usa en la práctica, `onEnd` corta antes por el guard de
/// pila con un solo elemento.
final class _RootFrame extends _Frame {
  @override
  String get name => '';
}

final class _TvFrame extends _Frame {
  @override
  String get name => 'tv';
}

final class _ChannelFrame extends _Frame {
  _ChannelFrame(this.id, {required this.charOffset});
  final String? id;
  final int? charOffset;
  final List<String> displayNames = [];
  Uri? icon;
  final List<Uri> urls = [];

  @override
  String get name => 'channel';
}

final class _ProgrammeFrame extends _Frame {
  _ProgrammeFrame({
    required this.channelId,
    required this.startRaw,
    required this.stopRaw,
    required this.charOffset,
  });
  final String? channelId;
  final String? startRaw;
  final String? stopRaw;
  final int? charOffset;
  String? title;
  String? desc;

  @override
  String get name => 'programme';
}

enum _ChildKind { displayName, channelUrl, title, desc }

final class _TextChildFrame extends _Frame {
  _TextChildFrame(this.kind, this.name);
  final _ChildKind kind;
  @override
  final String name;
  final StringBuffer buffer = StringBuffer();
}

/// Elemento conocido cuyo contenido no se modela (`<icon>`, `<sub-title>`
/// de programa): se consume para no romper el anidamiento del stack, sin
/// bufferizar texto.
final class _KnownLeafFrame extends _Frame {
  _KnownLeafFrame(this.name);
  @override
  final String name;
}

/// Subárbol ignorado: etiqueta desconocida, o anidamiento dentro de algo
/// que ya no nos interesa. No bufferiza texto — es lo que mantiene la
/// memoria acotada frente a un `<credits>` con decenas de hijos.
final class _SkipFrame extends _Frame {
  _SkipFrame(this.name);
  @override
  final String name;
}
