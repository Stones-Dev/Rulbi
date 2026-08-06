import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../l10n/app_localizations.dart';
import 'import_controller.dart';
import 'probe_result.dart';
import 'source_form_widgets.dart';

/// Pantalla de importación en curso (ui-spec §2.14): reutilizada por alta
/// de fuente y por refresco (S4 · Ola 3) — el mismo flujo que el resto de
/// la ficha describe para la futura recepción de configuración (F4).
///
/// [source] es opcional: al abrirla desde Gestión de fuentes (alta nueva o
/// refresco) se pasa la fuente real y arranca la importación si el
/// controller sigue en [ImportIdle]. Al reabrirla desde
/// [ImportStatusBar] (el chip global de un import ya en marcha) no hace
/// falta — el nombre a mostrar se lee del propio `ImportState`
/// (`sourceName`, presente en las cuatro variantes no-`Idle`), nunca de
/// [source], que en ese caso es `null`.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({this.source, super.key});

  final Source? source;

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  @override
  void initState() {
    super.initState();
    final source = widget.source;
    if (source != null && ref.read(importControllerProvider) is ImportIdle) {
      final notifier = ref.read(importControllerProvider.notifier);
      // Se dispara tras el primer frame para no llamar `start` (que hace
      // `ref.read`/escribe estado) durante `build`.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(notifier.start(source));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(importControllerProvider);
    final displayName = switch (state) {
      ImportRunning(:final sourceName) => sourceName,
      ImportDone(:final sourceName) => sourceName,
      ImportFailed(:final sourceName) => sourceName,
      ImportCancelled(:final sourceName) => sourceName,
      ImportIdle() => widget.source?.name ?? '',
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.importScreenTitle(displayName))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (state) {
          ImportIdle() => const _RunningView(channelsSeen: 0),
          ImportRunning(:final channelsSeen) => _RunningView(
            channelsSeen: channelsSeen,
          ),
          ImportDone(:final stats, :final summary) => _DoneView(
            stats: stats,
            summary: summary,
          ),
          ImportFailed(:final reason) => _FailedView(reason: reason),
          ImportCancelled() => const _CancelledView(),
        },
      ),
    );
  }
}

class _RunningView extends ConsumerWidget {
  const _RunningView({required this.channelsSeen});

  final int channelsSeen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          l10n.channelCount(channelsSeen),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () =>
                  ref.read(importControllerProvider.notifier).cancel(),
              child: Text(l10n.importCancelButton),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.importBackgroundButton),
            ),
          ],
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.stats, required this.summary});

  final SourceImportStats stats;
  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.importDoneTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(l10n.importStatsInserted(stats.inserted)),
          Text(l10n.importStatsUpdated(stats.updated)),
          Text(l10n.importStatsUnchanged(stats.unchanged)),
          Text(l10n.importStatsTombstoned(stats.tombstoned)),
          Text(l10n.importStatsResurrected(stats.resurrected)),
          Text(l10n.importStatsDuplicates(stats.duplicateRefs)),
          if (summary.discardedCount > 0) ...[
            const SizedBox(height: 16),
            _DiscardedList(summary: summary),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.importBackButton),
          ),
        ],
      ),
    );
  }
}

/// "Visor de incidencias" (ui-spec §2.14): `ExpansionTile` sobre
/// `ImportReport.discarded` (M3U) o `XtreamImportReport.discarded`
/// (Xtream) — sin reinventar sus campos, cada uno con su propia forma de
/// fila (P6: cada capa de protocolo describe sus propios fallos).
class _DiscardedList extends StatelessWidget {
  const _DiscardedList({required this.summary});

  final ImportSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ExpansionTile(
      key: const Key('importScreen.issuesToggle'),
      title: Text(l10n.importIssuesToggle(summary.discardedCount)),
      children: switch (summary) {
        M3uImportSummary(:final report) => [
          for (final line in report.discarded)
            ListTile(
              dense: true,
              title: Text(
                l10n.importM3uDiscardLine(line.lineNumber, line.reason),
              ),
            ),
        ],
        XtreamImportSummary(:final report) => [
          for (final discard in report.discarded)
            ListTile(
              dense: true,
              title: Text(
                l10n.importXtreamDiscardLine(discard.action, discard.reason),
              ),
            ),
        ],
      },
    );
  }
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.reason});

  final ProbeFailureReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importFailedTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(probeFailureReasonLabel(l10n, reason)),
        const SizedBox(height: 8),
        Text(l10n.importFailedHint),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.importBackButton),
        ),
      ],
    );
  }
}

class _CancelledView extends StatelessWidget {
  const _CancelledView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.importCancelledTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.importCancelledMessage),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.importBackButton),
        ),
      ],
    );
  }
}
