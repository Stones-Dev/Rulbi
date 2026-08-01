import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Override manual de idioma (D4, requisito 5: "detección automática con
/// opción de override manual"). `null` significa "sigue la locale del
/// sistema, con fallback a inglés" — el comportamiento por defecto de
/// `MaterialApp`. La pantalla de Ajustes que materializa el selector visible
/// llega en una tarea de F2/F3 aparte; este provider es el mecanismo que esa
/// pantalla escribirá.
final localeOverrideProvider = StateProvider<Locale?>((ref) => null);
