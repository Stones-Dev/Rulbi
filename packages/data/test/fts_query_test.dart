import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_data/src/db/fts_query.dart';

void main() {
  group('toFtsMatchQuery (S5 · Ola 1)', () {
    test('un único token se envuelve en comillas y se convierte en prefijo', () {
      expect(toFtsMatchQuery('canal'), '"canal"*');
    });

    test('varios tokens: solo el último es prefijo', () {
      expect(toFtsMatchQuery('canal espana'), '"canal" "espana"*');
    });

    test('colapsa espacios múltiples y recorta bordes', () {
      expect(toFtsMatchQuery('  canal    espana  '), '"canal" "espana"*');
    });

    test('escapa comillas dobles internas duplicándolas', () {
      // El usuario escribe literalmente `"42"` como parte de la consulta.
      expect(toFtsMatchQuery('"42"'), '"""42"""*');
    });

    test('neutraliza operadores de FTS5 (AND/OR/NOT/NEAR) como texto literal', () {
      final result = toFtsMatchQuery('AND OR NOT NEAR(canal)');
      // Ninguno debe colar sin comillas: si alguno apareciera desnudo,
      // SQLite lo interpretaría como operador y lanzaría (o cambiaría el
      // significado de) la consulta.
      expect(result, '"AND" "OR" "NOT" "NEAR(canal)"*');
    });

    test('neutraliza caracteres especiales sueltos (*, -, ^, :)', () {
      expect(toFtsMatchQuery('esp*'), '"esp*"*');
      expect(toFtsMatchQuery('-canal'), '"-canal"*');
      expect(toFtsMatchQuery('a^b'), '"a^b"*');
      expect(toFtsMatchQuery('tvg:1'), '"tvg:1"*');
    });

    test('conserva acentos y mayúsculas tal cual (el folding lo hace el tokenizer FTS5)', () {
      expect(toFtsMatchQuery('España'), '"España"*');
    });

    test('entrada vacía o solo espacios produce cadena vacía', () {
      expect(toFtsMatchQuery(''), '');
      expect(toFtsMatchQuery('   '), '');
    });

    test('entrada solo-puntuación produce cadena vacía (sin letras/dígitos)', () {
      expect(toFtsMatchQuery('!!!'), '');
      expect(toFtsMatchQuery('*** --- ...'), '');
      expect(toFtsMatchQuery('"'), '');
    });

    test('descarta tokens de puntuación pura entre tokens válidos', () {
      expect(toFtsMatchQuery('canal - espana'), '"canal" "espana"*');
    });

    test('un token con dígitos se conserva aunque no tenga letras', () {
      expect(toFtsMatchQuery('007'), '"007"*');
    });
  });
}
