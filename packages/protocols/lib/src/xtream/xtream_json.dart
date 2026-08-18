/// Utilidades de parseo tolerante para respuestas de `player_api.php`
/// (T1.4): Xtream es notorio por no respetar tipos entre paneles (y a
/// veces ni dentro del mismo panel — ver `stream_id` int en
/// `get_vod_streams` vs string en `get_vod_info.movie_data`, mismo panel,
/// mismo campo, fixture real de T1.1). Cada función acepta la forma
/// "buena" y sus dialectos conocidos, sin lanzar — un valor irreconocible
/// se resuelve al valor por defecto explícito de quien llama.
library;

/// `String` o `num` → `String`. `null`/ausente → `null`.
String? asFlexibleString(Object? value) => switch (value) {
  null => null,
  String s => s,
  num n => n.toString(),
  _ => value.toString(),
};

/// `String` (incluida vacía), `num`, `bool` (`0`/`1` de Xtream) → `int`.
/// Cualquier forma irreconocible (`null`, cadena no numérica, lista) →
/// [fallback].
int asFlexibleInt(Object? value, {int fallback = 0}) => switch (value) {
  int i => i,
  double d => d.toInt(),
  String s => int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.toInt() ?? fallback,
  bool b => b ? 1 : 0,
  _ => fallback,
};

/// Como [asFlexibleInt] pero devuelve `null` en vez de un valor de
/// relleno cuando no hay dato — para campos opcionales donde "cero" y
/// "desconocido" no son lo mismo (p. ej. IDs).
int? asFlexibleIntOrNull(Object? value) => switch (value) {
  null => null,
  int i => i,
  double d => d.toInt(),
  String s => s.trim().isEmpty ? null : (int.tryParse(s.trim()) ?? double.tryParse(s.trim())?.toInt()),
  bool b => b ? 1 : 0,
  _ => null,
};

/// `String` `"0"`/`"1"`, `int` `0`/`1`, `bool` → `bool`. Xtream casi
/// siempre manda `0`/`1` como string o int, nunca `true`/`false` literal,
/// pero se tolera igual por si algún panel lo hace.
bool asFlexibleBool(Object? value, {bool fallback = false}) => switch (value) {
  bool b => b,
  int i => i != 0,
  String s => s.trim() == '1' || s.trim().toLowerCase() == 'true',
  _ => fallback,
};

/// `double` desde `num` o `String` (algunos paneles mandan `rating` como
/// `"7.5"`, otros como `7.5` numérico — fixture real de T1.1 con ambas
/// formas en el mismo panel: `get_vod_streams` vs `get_vod_info`).
double? asFlexibleDouble(Object? value) => switch (value) {
  null => null,
  num n => n.toDouble(),
  String s => double.tryParse(s.trim()),
  _ => null,
};

/// Un campo `Map` o `List` normalizado a `Map`: `get_series_info.episodes`
/// documenta la forma mapa (`{"1": [...]}`), pero un dialecto sintético
/// cubierto en T1.4 lo manda como lista plana — se reindexa por posición
/// (temporada 1-based) en ese caso, con la anotación correspondiente que
/// hace el llamador, no esta función (aquí solo se normaliza la forma).
Map<String, Object?> asFlexibleMap(Object? value) => switch (value) {
  Map<String, Object?> m => m,
  Map m => m.map((k, v) => MapEntry(k.toString(), v)),
  _ => const {},
};

/// Una `List` tolerante a `null`/forma inesperada → lista vacía en vez de
/// lanzar `TypeError` en el llamador.
List<Object?> asFlexibleList(Object? value) => switch (value) {
  List l => l,
  _ => const [],
};

/// `backdrop_path` de `get_vod_info`/`get_series_info`/`get_series`: la
/// forma habitual de Xtream es un `List` de URLs (a veces con entradas
/// `null` intercaladas — fixture real de T1.1, `dialect_o0zz`), pero
/// algún panel lo manda como un `String` suelto. Se toma la primera
/// entrada no vacía en cualquiera de las dos formas; `[]`, `[null]` o la
/// clave ausente → `null`, nunca lanza. Sin validar que el resultado sea
/// una URL bien formada — mismo criterio que `cover_url`/`stream_icon` en
/// este fichero: el string se pasa tal cual, la validación (si hace
/// falta) es cosa de quien lo consuma, no del parseo.
String? asFlexibleFirstUrl(Object? value) {
  // `nonEmptyOrNull` vive en `xtream_stream.dart`, que ya importa este
  // fichero — inline aquí en vez de crear un import circular por un
  // helper de una línea.
  String? nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  return switch (value) {
    null => null,
    String s => nonEmpty(s),
    List l => l.map((e) => nonEmpty(asFlexibleString(e))).firstWhere((e) => e != null, orElse: () => null),
    _ => null,
  };
}

/// `direct_source` (campo real de `get_live_streams`/`get_vod_streams`,
/// vacío en los fixtures de T1.1 pero no siempre en paneles reales) es una
/// URL alternativa que puede llevar sus propias credenciales embebidas —
/// nunca entra en `ChannelRef` ni en `Channel.url` (ADR-006). Se conserva
/// solo su `host`, nunca su ruta/query (donde viajaría cualquier secreto),
/// como dato informativo de metadata. `null` si está vacío o no es una
/// URL reconocible.
String? sanitizedDirectSourceHost(String? directSource) {
  if (directSource == null || directSource.trim().isEmpty) return null;
  final uri = Uri.tryParse(directSource.trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host;
}
