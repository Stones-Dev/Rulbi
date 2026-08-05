import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'm3u_source_form.dart';

/// Sección *Fuentes* del `DesktopShell` (ui-spec §2.10), S4 · Ola 2:
/// deliberadamente sin lista de fuentes todavía — eso es *Gestión de
/// fuentes* (Ola 3). Aquí solo viven los puntos de entrada a los
/// formularios de alta.
class SourcesEntryScreen extends StatelessWidget {
  const SourcesEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: Text(l10n.sourcesAddM3uButton),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const M3uSourceForm()),
            ),
          ),
        ],
      ),
    );
  }
}
