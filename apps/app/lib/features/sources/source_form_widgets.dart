import 'package:flutter/material.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../l10n/app_localizations.dart';
import 'probe_result.dart';
import 'save_source.dart';

/// Piezas compartidas entre `m3u_source_form.dart` y `xtream_source_form.dart`
/// (S4 · Ola 2): el mapeo de motivos de fallo tipados a texto i18n, el
/// selector de política de refresco y la barra de acciones Probar/Guardar/
/// Cancelar. Ninguna de las dos pantallas reimplementa esto por separado.

String probeFailureReasonLabel(AppLocalizations l10n, ProbeFailureReason reason) =>
    switch (reason) {
      ProbeFailureReason.network => l10n.probeErrorNetwork,
      ProbeFailureReason.timeout => l10n.probeErrorTimeout,
      ProbeFailureReason.notFound => l10n.probeErrorNotFound,
      ProbeFailureReason.malformed => l10n.probeErrorMalformed,
      ProbeFailureReason.authFailed => l10n.probeErrorAuthFailed,
      ProbeFailureReason.accountExpired => l10n.probeErrorAccountExpired,
      ProbeFailureReason.accountDisabled => l10n.probeErrorAccountDisabled,
      ProbeFailureReason.rateLimited => l10n.probeErrorRateLimited,
      ProbeFailureReason.unknown => l10n.probeErrorUnknown,
    };

String saveSourceFailureReasonLabel(
  AppLocalizations l10n,
  SaveSourceFailureReason reason,
) => switch (reason) {
  SaveSourceFailureReason.duplicateName => l10n.sourceNameDuplicateError,
  SaveSourceFailureReason.secretStoreFailed => l10n.sourceSaveErrorSecretStore,
  SaveSourceFailureReason.persistFailed => l10n.sourceSaveErrorGeneric,
};

String refreshPolicyLabel(AppLocalizations l10n, SourceRefreshPolicy policy) =>
    switch (policy) {
      SourceRefreshPolicy.manual => l10n.refreshPolicyManual,
      SourceRefreshPolicy.onOpen => l10n.refreshPolicyOnOpen,
      SourceRefreshPolicy.daily => l10n.refreshPolicyDaily,
    };

class RefreshPolicyDropdown extends StatelessWidget {
  const RefreshPolicyDropdown({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final SourceRefreshPolicy value;
  final ValueChanged<SourceRefreshPolicy?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DropdownButtonFormField<SourceRefreshPolicy>(
      initialValue: value,
      decoration: InputDecoration(labelText: l10n.refreshPolicyLabel),
      items: [
        for (final policy in SourceRefreshPolicy.values)
          DropdownMenuItem(
            value: policy,
            child: Text(refreshPolicyLabel(l10n, policy)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Fila de acciones común a ambos formularios: *Probar*/*Probar conexión*
/// (texto inyectado por [probeLabel]) · *Guardar* (`commonSave`) ·
/// *Cancelar* (`commonCancel`, hace `Navigator.pop`). Los tres botones se
/// deshabilitan mientras [isProbing]/[isSaving] es verdadero, para no
/// disparar una segunda petición en vuelo.
class SourceFormActionBar extends StatelessWidget {
  const SourceFormActionBar({
    required this.probeLabel,
    required this.isProbing,
    required this.isSaving,
    required this.onProbe,
    required this.onSave,
    super.key,
  });

  final String probeLabel;
  final bool isProbing;
  final bool isSaving;
  final VoidCallback? onProbe;
  final VoidCallback? onSave;

  // Target táctil mínimo (RNF-08) — el `minimumSize` por defecto de un
  // botón Material 3 estándar es 40dp de alto, por debajo del umbral;
  // fijado explícito en vez de confiar en el padding de tap-target
  // implícito de la plataforma, que no es igual de fiable en todas.
  static const _minTouchSize = Size(64, 48);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = isProbing || isSaving;

    // `Wrap` en vez de `Row` (S7 · Móvil base): tres botones de ancho
    // variable ("Cancelar" · "Probar conexión" · "Guardar") no siempre
    // caben en una fila de 360dp de ancho, sobre todo en español. `Wrap`
    // se comporta igual que `Row` cuando sí caben (Desktop) y baja el
    // último botón a una segunda línea cuando no, en vez de desbordar.
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: _minTouchSize),
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: _minTouchSize),
          onPressed: busy ? null : onProbe,
          child: Text(isProbing ? l10n.probingInProgress : probeLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: _minTouchSize),
          onPressed: busy ? null : onSave,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
