import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/features/channels/channel_row.dart';

/// `highlightedSpans` (ui-spec §2.11: "resalta coincidencia") como
/// función pura — más robusto que inspeccionar el árbol de `RichText`
/// renderizado (que puede incluir spans intermedios generados por
/// Flutter, no solo los que construye esta función).
void main() {
  const baseStyle = TextStyle(color: Colors.white);
  const matchStyle = TextStyle(color: Colors.blue, fontWeight: FontWeight.bold);

  List<TextSpan> spansOf(String text, String? query) =>
      highlightedSpans(
        text: text,
        query: query,
        baseStyle: baseStyle,
        matchStyle: matchStyle,
      ).cast<TextSpan>();

  test('sin query, devuelve un único span con el texto completo', () {
    final spans = spansOf('La 1 HD', null);
    expect(spans, hasLength(1));
    expect(spans.single.text, 'La 1 HD');
    expect(spans.single.style, baseStyle);
  });

  test('query vacía o solo espacios se comporta como sin query', () {
    expect(spansOf('La 1 HD', '   ').single.text, 'La 1 HD');
  });

  test('resalta la coincidencia exacta en el medio del texto', () {
    final spans = spansOf('La 1 HD', 'la 1');
    expect(spans.map((s) => s.text), ['', 'La 1', ' HD']);
    expect(spans[1].style, matchStyle);
    expect(spans[0].style, baseStyle);
    expect(spans[2].style, baseStyle);
  });

  test('insensible a acentos y mayúsculas (misma normalización que FTS5)', () {
    final spans = spansOf('España TV', 'espana');
    expect(spans.map((s) => s.text), ['', 'España', ' TV']);
    expect(spans[1].style, matchStyle);
  });

  test('sin coincidencia, devuelve el texto completo sin resaltar', () {
    final spans = spansOf('La 1 HD', 'xyz');
    expect(spans, hasLength(1));
    expect(spans.single.text, 'La 1 HD');
  });

  test('coincidencia al principio del texto (prefijo vacío)', () {
    final spans = spansOf('Canal España', 'canal');
    expect(spans.map((s) => s.text), ['', 'Canal', ' España']);
    expect(spans[1].style, matchStyle);
  });

  test('coincidencia al final del texto (sufijo vacío)', () {
    final spans = spansOf('TV España', 'espana');
    expect(spans.map((s) => s.text), ['TV ', 'España', '']);
    expect(spans[1].style, matchStyle);
  });
}
