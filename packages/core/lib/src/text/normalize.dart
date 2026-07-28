/// Normalización de texto compartida por [ChannelRef] (búsqueda de igualdad
/// de canal) y, conceptualmente, por el tokenizador FTS5
/// (`unicode61 remove_diacritics 2`) de `packages/data` — no es el mismo
/// código (SQLite tokeniza en C), pero debe producir el mismo resultado
/// para las mismas cadenas de entrada. Si no coincidieran, dos dispositivos
/// podrían derivar un `ChannelRef` distinto para el mismo canal a partir de
/// la misma lista.
///
/// Cubre Latin-1 Supplement + los diacríticos más comunes de Latin
/// Extended-A: el alfabeto realista de nombres de canal (ES/PT/FR/DE/IT).
/// Si un golden file real (T1.1) trae un carácter no cubierto, se amplía
/// esta tabla — nunca se sustituye por una dependencia de normalización
/// Unicode completa sin necesidad demostrada.
String normalizeForMatching(String input) => input
    .split('')
    .map((ch) => _diacriticsMap[ch] ?? ch)
    .join()
    .toLowerCase()
    .trim();

const Map<String, String> _diacriticsMap = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Ā': 'A',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', 'Ē': 'E',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'Ī': 'I',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ō': 'o',
  'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ō': 'O',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ū': 'U',
  'ñ': 'n', 'Ñ': 'N',
  'ç': 'c', 'Ç': 'C',
  'ý': 'y', 'ÿ': 'y', 'Ý': 'Y',
};
