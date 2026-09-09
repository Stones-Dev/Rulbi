import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_tokens/iptv_tokens.dart';

import '../../l10n/app_localizations.dart';
import 'delete_source.dart';
import 'import_controller.dart';
import 'import_screen.dart';
import 'm3u_source_form.dart';
import 'source_providers.dart';
import 'xtream_source_form.dart';

/// Pantalla de Gestión de fuentes (ui-spec §2.10, S4 · Ola 3) — sustituye
/// al `SourcesEntryScreen` de Ola 2 (solo puntos de entrada, sin listado)
/// en la sección *Fuentes* del `DesktopShell`.
///
/// Flujo completo: Fuentes (lista) → *Nueva fuente* → formulario M3U/
/// Xtream → Guardar → `ImportScreen` (progreso) → vuelta a Fuentes con la
/// lista ya actualizada ([sourcesStreamProvider] es reactivo). Editar
/// **no** dispara import automático — el usuario pulsa *Actualizar* si
/// quiere reimportar.
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key, this.showSectionTitle = true});

  /// `false` cuando quien empuja esta pantalla ya pone el título "Fuentes"
  /// en su propio `AppBar` (ver `pushedScreenRoute`, S7 fix post-E2E) — evita
  /// que "Fuentes" salga duplicado. `DesktopShell` la embebe sin `AppBar`
  /// propio, así que sigue con el valor por defecto `true`.
  final bool showSectionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(sourcesStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: sourcesAsync.when(
        data: (sources) => sources.isEmpty
            ? const _EmptyState()
            : _SourcesList(sources: sources, showSectionTitle: showSectionTitle),
        loading: () => const Center(child: CircularProgressIndicator()),
        // watchAll() sobre drift no debería fallar en operación normal;
        // fallback genérico en vez de una pantalla en blanco (RNF-09).
        error: (_, _) => Center(child: Text(l10n.probeErrorUnknown)),
      ),
    );
  }
}

/// Alta de fuente: empuja el formulario correspondiente y, si se guardó
/// con éxito (`pop` devuelve el `Source`), encadena la pantalla de
/// importación — el flujo completo de ui-spec §2.1→§2.8/§2.9→§2.14.
Future<void> _addM3uSource(BuildContext context) async {
  final saved = await Navigator.of(
    context,
  ).push<Source>(MaterialPageRoute(builder: (_) => const M3uSourceForm()));
  if (saved != null && context.mounted) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => ImportScreen(source: saved)));
  }
}

Future<void> _addXtreamSource(BuildContext context) async {
  final saved = await Navigator.of(
    context,
  ).push<Source>(MaterialPageRoute(builder: (_) => const XtreamSourceForm()));
  if (saved != null && context.mounted) {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (_) => ImportScreen(source: saved)));
  }
}

/// Editar: reabre el formulario precargado. A diferencia del alta, no
/// encadena `ImportScreen` — el resultado (fuente editada, `Source?`) se
/// descarta más allá de dejar que `sourcesStreamProvider` refleje el
/// cambio solo.
Future<void> _editSource(BuildContext context, Source source) async {
  await Navigator.of(context).push<Source>(
    MaterialPageRoute<Source>(
      builder: (_) => switch (source.kind) {
        SourceKind.xtream => XtreamSourceForm(initialSource: source),
        SourceKind.m3uUrl || SourceKind.m3uFile => M3uSourceForm(initialSource: source),
      },
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.source_outlined,
            size: 64,
            color: IptvColors.textSecondary,
          ),
          const SizedBox(height: IptvSpacing.md),
          Text(l10n.sourcesEmptyTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: IptvSpacing.sm),
          Text(l10n.sourcesEmptyHint, textAlign: TextAlign.center),
          const SizedBox(height: IptvSpacing.md * 1.5),
          Wrap(
            spacing: IptvSpacing.sm,
            runSpacing: IptvSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.playlist_add),
                label: Text(l10n.sourcesAddM3uButton),
                onPressed: () => _addM3uSource(context),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.dns_outlined),
                label: Text(l10n.sourcesAddXtreamButton),
                onPressed: () => _addXtreamSource(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourcesList extends StatelessWidget {
  const _SourcesList({required this.sources, required this.showSectionTitle});

  final List<Source> sources;
  final bool showSectionTitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // `Wrap` en `Flexible` (no directo en el `Row`): un `Row` da a sus
    // hijos no-flex `maxWidth: infinity`, así que sin acotar el `Wrap`
    // nunca envuelve — recibe anchura infinita y coloca los dos botones en
    // una sola línea, que en móvil (locale ES: "Añadir fuente M3U" +
    // "Añadir fuente Xtream") desborda por la derecha (S7, verificación
    // E2E). El título también en `Expanded` con ellipsis por si el ancho
    // que le queda al `Wrap` fuera aún más justo.
    final actions = Wrap(
      spacing: IptvSpacing.sm,
      runSpacing: IptvSpacing.sm,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.playlist_add),
          label: Text(l10n.sourcesAddM3uButton),
          onPressed: () => _addM3uSource(context),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.dns_outlined),
          label: Text(l10n.sourcesAddXtreamButton),
          onPressed: () => _addXtreamSource(context),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSectionTitle)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  l10n.navSources,
                  style: Theme.of(context).textTheme.headlineSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Flexible(child: actions),
            ],
          )
        else
          Align(alignment: Alignment.centerRight, child: actions),
        const SizedBox(height: IptvSpacing.md),
        Expanded(
          child: ListView.separated(
            itemCount: sources.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: IptvColors.border),
            itemBuilder: (context, index) => _SourceRow(source: sources[index]),
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final countAsync = ref.watch(channelCountProvider(source.id));
    final lastStatusOk = ref.watch(lastImportStatusProvider)[source.id];
    final isXtream = source.kind == SourceKind.xtream;

    return ListTile(
      key: Key('sourceRow.${source.id}'),
      leading: Icon(isXtream ? Icons.dns_outlined : Icons.playlist_play),
      // `Wrap`, no `Row` (S7, verificación E2E) — mismo motivo que ya
      // documenta `subtitle` más abajo: en móvil, el `trailing` de 4
      // acciones (switch + 3 `IconButton`) deja tan poco ancho a `title`
      // que el `Chip` (no flexible) desborda aunque el nombre sí lo sea.
      // Antes quedaba enmascarado por el crash de "No Material widget
      // found" — al arreglar eso quedó expuesto este overflow, real y
      // distinto del de la cabecera.
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: IptvSpacing.sm,
        children: [
          Text(source.name, overflow: TextOverflow.ellipsis),
          Chip(
            label: Text(isXtream ? l10n.sourceTypeXtream : l10n.sourceTypeM3u),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          if (lastStatusOk == false)
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
        ],
      ),
      // `Wrap`, no `Row`: nombre/tipo/contador/fecha juntos no siempre
      // caben en una línea a la anchura mínima del `NavigationRail`
      // extendido (overflow real encontrado por sources_screen_test.dart)
      // — en vez de recortar contenido, la segunda línea se envuelve.
      subtitle: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          countAsync.when(
            data: (count) => Text(l10n.channelCount(count)),
            loading: () => const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(width: IptvSpacing.sm),
          const Text('·'),
          const SizedBox(width: IptvSpacing.sm),
          Text(
            source.lastRefresh != null
                ? l10n.lastUpdated(source.lastRefresh!)
                : l10n.sourceNeverImported,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: source.enabled,
            onChanged: (value) => _toggleEnabled(ref, source, value),
          ),
          IconButton(
            key: Key('sourceRow.${source.id}.refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.sourceRefreshTooltip,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => ImportScreen(source: source)),
            ),
          ),
          IconButton(
            key: Key('sourceRow.${source.id}.edit'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.sourceEditTooltip,
            onPressed: () => _editSource(context, source),
          ),
          IconButton(
            key: Key('sourceRow.${source.id}.delete'),
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.sourceDeleteTooltip,
            onPressed: () => _confirmDelete(context, ref, source),
          ),
        ],
      ),
    );
  }

  void _toggleEnabled(WidgetRef ref, Source source, bool value) {
    final now = ref.read(clockProvider).now();
    ref.read(sourceRepositoryProvider).upsert(source.withEnabled(value, now));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Source source,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.sourceDeleteConfirmTitle),
        content: Text(l10n.sourceDeleteConfirmBody(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.sourceDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      final result = await ref.read(deleteSourceProvider)(source.id);
      if (result is DeleteSourceFailed && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.sourceDeleteError)));
      }
    }
  }
}
