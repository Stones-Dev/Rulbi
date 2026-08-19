import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import '../favorites/favorites_screen.dart';
import '../sources/sources_screen.dart';
import 'devices_screen.dart';

/// Ajustes móvil (S7 · Móvil base, paso 1) — **no** es la pantalla de
/// Ajustes completa de ui-spec §2.15 (Reproducción/Apariencia/Idioma/
/// Privacidad/Acerca de siguen sin construir en ningún shell). Es lo
/// mínimo para que Fuentes, Favoritos y Dispositivos —secciones de
/// Desktop que no caben en la barra inferior de 5 destinos (ui-spec
/// §1)— queden alcanzables desde móvil, detrás del icono de Ajustes del
/// `AppBar` de [MobileShell] ("resto por pila").
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: IptvColors.background,
      appBar: AppBar(
        backgroundColor: IptvColors.surface,
        title: Text(l10n.navSettings),
      ),
      body: ListView(
        children: [
          _SettingsTile(
            icon: Symbols.source_rounded,
            label: l10n.navSources,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
            ),
          ),
          _SettingsTile(
            icon: Symbols.favorite_rounded,
            label: l10n.navFavorites,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FavoritesScreen(),
              ),
            ),
          ),
          _SettingsTile(
            icon: Symbols.devices_rounded,
            label: l10n.navDevices,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DevicesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // Altura mínima de fila ≥48dp (RNF-08) — el `ListTile` de Material 3
      // ya cumple esto por defecto (56dp de alto con un solo título), sin
      // ajuste propio.
      leading: Icon(
        icon,
        size: IptvIconSizes.action,
        color: IptvColors.textSecondary,
      ),
      title: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: IptvColors.textPrimary),
      ),
      trailing: const Icon(
        Symbols.chevron_right_rounded,
        size: IptvIconSizes.action,
        color: IptvColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}
