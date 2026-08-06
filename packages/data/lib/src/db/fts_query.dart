/// Caracteres alfanuméricos Unicode — usado para descartar tokens que son
/// pura puntuación (no aportan nada a una búsqueda de texto).
final RegExp _hasWordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Traduce una consulta de usuario en lenguaje natural a una expresión
/// `MATCH` de FTS5 segura (S5 · Ola 1, `ChannelSearchPort.search`).
///
/// Sin este paso, escribir `"`, `*`, `AND`, `NEAR(`... en el cuadro de
/// búsqueda lanzaba directamente una excepción de SQLite: FTS5 tiene su
/// propia gramática de consulta y la entrada del usuario no la respeta.
/// Cada token se envuelve en un literal de cadena entre comillas dobles
/// (duplicando las comillas internas, la forma de escapar de FTS5), lo
/// que neutraliza cualquier operador (`AND`/`OR`/`NOT`/`NEAR(`) y
/// cualquier carácter especial (`*`, `-`, `^`, `:`) tratándolo como texto
/// literal. El último token se convierte en consulta de prefijo (`*` justo
/// tras la comilla de cierre, sintaxis válida de FTS5 para un token entre
/// comillas) para que aparezcan resultados mientras se sigue escribiendo,
/// antes de terminar la última palabra.
///
/// Los tokens sin ninguna letra o dígito (p. ej. una entrada
/// solo-puntuación como `"!!!"`) se descartan: no aportan nada a una
/// búsqueda de texto y el tokenizer `unicode61` de FTS5 los reduce a nada
/// de todas formas. Si no queda ningún token, devuelve `''` — quien llama
/// (`DriftChannelRepository.search`) debe tratarlo como "no buscar nada" y
/// devolver `[]` sin tocar la base de datos, nunca pasar `''` a `MATCH`.
String toFtsMatchQuery(String raw) {
  final tokens = raw
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty && _hasWordChar.hasMatch(token))
      .toList();
  if (tokens.isEmpty) return '';

  String quote(String token) => '"${token.replaceAll('"', '""')}"';

  return [
    for (var i = 0; i < tokens.length; i++)
      i == tokens.length - 1 ? '${quote(tokens[i])}*' : quote(tokens[i]),
  ].join(' ');
}
