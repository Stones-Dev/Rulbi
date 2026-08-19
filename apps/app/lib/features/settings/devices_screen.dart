import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';

/// Dispositivos y sincronización (ui-spec §2.12) — **placeholder** de S7,
/// paso 1. Solo ancla la ruta desde [SettingsScreen] (`../settings/
/// settings_screen.dart`); el contenido real (botón "Escanear QR" +
/// resultado del parseo del payload §3.1) llega en el paso 4 del mismo
/// sprint (tarea "Escáner QR base"). El resto de §2.12 (Recibir
/// configuración, lista de dispositivos emparejados, mDNS) es alcance de
/// sprints posteriores — el DoD de S7 dice explícitamente "aún sin
/// destino".
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: IptvColors.background,
      appBar: AppBar(
        backgroundColor: IptvColors.surface,
        title: Text(l10n.navDevices),
      ),
      // Placeholder deliberado — mismo patrón que `_SectionPlaceholder` de
      // `DesktopShell` para Guía/Ajustes: contenido real en el paso 4.
      body: Center(
        child: Text(
          l10n.navDevices,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: IptvColors.textPrimary),
        ),
      ),
    );
  }
}
