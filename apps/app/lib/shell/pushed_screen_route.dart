import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../l10n/app_localizations.dart';

/// Ruta para empujar una pantalla que fue diseñada para vivir **embebida**
/// dentro de un shell (S7, fix post-verificación E2E) — p. ej. `SourcesScreen`
/// y `FavoritesScreen`, que `DesktopShell` monta directamente en su
/// `IndexedStack` y por eso no traen `Scaffold`/`AppBar` propios.
///
/// `MaterialPageRoute` por sí sola **no** aporta un ancestro `Material`:
/// solo la transición y el `_ModalScope`. Empujar una de esas pantallas
/// embebibles directo con `MaterialPageRoute` (como hacía `MobileShell`
/// antes de este fix) revienta en cuanto la pantalla usa `ListTile`,
/// `Chip`, `Switch` o cualquier otro widget que exija `Material` — el
/// `Scaffold` de `MobileShell` no cuenta, porque queda un nivel por encima
/// de la ruta empujada, no dentro de ella.
///
/// Invariante que debe respetarse a partir de ahora: pantalla **embebida**
/// en un shell (dentro de un `IndexedStack`/`body`) → sin `Scaffold`
/// propio; pantalla empujada como **ruta independiente** → pasa por
/// [pushedScreenRoute], que aporta el `Scaffold`+`AppBar` (con flecha de
/// retroceso) que le falta.
///
/// No usar esto para pantallas que ya traen su propio `Scaffold` (p. ej.
/// `SettingsScreen`, `DevicesScreen`) — produciría un `Scaffold` anidado
/// con `AppBar` duplicado.
///
/// `title` recibe [AppLocalizations] en vez de un `String` ya resuelto: el
/// `builder` de `MaterialPageRoute` solo se vuelve a invocar cuando algo de
/// lo que lee dentro cambia. Si se resolviera el `String` en el punto de
/// llamada (al pulsar el tile) y se capturase fijo aquí, el título del
/// `AppBar` quedaría congelado en el locale de ese instante — mientras que
/// el cuerpo (`SourcesScreen`/`FavoritesScreen`) sí se actualiza solo,
/// porque cada uno llama a `AppLocalizations.of(context)` en su propio
/// `build()`. Encontrado verificando este mismo fix en el emulador
/// (S7): cambiar el locale por-app con la pantalla ya abierta dejaba
/// "Favoritos" en el `AppBar` aunque el resto pasara a inglés.
Route<void> pushedScreenRoute({
  required String Function(AppLocalizations l10n) title,
  required Widget child,
}) => MaterialPageRoute<void>(
  builder: (context) => Scaffold(
    backgroundColor: IptvColors.background,
    appBar: AppBar(
      backgroundColor: IptvColors.surface,
      title: Text(title(AppLocalizations.of(context))),
    ),
    body: child,
  ),
);
