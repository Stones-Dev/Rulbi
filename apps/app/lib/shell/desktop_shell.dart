import 'package:flutter/material.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

/// Shell de escritorio: barra lateral persistente + atajos de teclado según
/// ui-spec §1. Esqueleto del Sprint 0 — las pantallas reales llegan en F2.
class DesktopShell extends StatelessWidget {
  const DesktopShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IptvColors.background,
      body: Center(
        child: Text(
          'DesktopShell',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(color: IptvColors.textPrimary),
        ),
      ),
    );
  }
}
