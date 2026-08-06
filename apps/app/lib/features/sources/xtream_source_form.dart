import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';
import 'package:iptv_protocols/iptv_protocols.dart';

import '../../l10n/app_localizations.dart';
import 'probe_result.dart';
import 'save_source.dart';
import 'source_form_widgets.dart';
import 'source_providers.dart';
import 'xtream_probe.dart';

/// Formulario de fuente Xtream (ui-spec §2.9, ADR-006, S4 · Ola 2; edición
/// desde S4 · Ola 3). La contraseña nunca entra en `Source`/
/// `XtreamSourceConfig` (ver `source.dart:52-56`): se pasa a `SaveSource`
/// como `secret` y termina solo en `SecureCredentialStore`. La URL del
/// servidor se normaliza con `normalizeXtreamPanelHost`
/// (`packages/protocols`) — este widget no reimplementa esa lógica
/// (P6/ADR-006).
///
/// [initialSource] `!= null` activa el modo edición: precarga
/// nombre/host/usuario, pero **nunca** la contraseña (P5) — el campo
/// arranca vacío con una pista ("déjalo en blanco para mantener la
/// actual"); un campo vacío al guardar significa "sin cambios" y no toca
/// el almacén seguro (ver `SaveSource.call`).
class XtreamSourceForm extends ConsumerStatefulWidget {
  const XtreamSourceForm({this.initialSource, super.key});

  /// Fuente a editar, o `null` para dar de alta una nueva.
  final Source? initialSource;

  static const nameFieldKey = Key('xtreamSourceForm.name');
  static const hostFieldKey = Key('xtreamSourceForm.host');
  static const usernameFieldKey = Key('xtreamSourceForm.username');
  static const passwordFieldKey = Key('xtreamSourceForm.password');
  static const togglePasswordVisibilityKey = Key(
    'xtreamSourceForm.togglePasswordVisibility',
  );

  @override
  ConsumerState<XtreamSourceForm> createState() => _XtreamSourceFormState();
}

class _XtreamSourceFormState extends ConsumerState<XtreamSourceForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  SourceRefreshPolicy _refreshPolicy = SourceRefreshPolicy.manual;
  bool _obscurePassword = true;

  bool _isProbing = false;
  bool _isSaving = false;
  ProbeResult<XtreamProbeSummary>? _probeResult;
  SaveSourceFailureReason? _saveFailure;

  bool get _isEditing => widget.initialSource != null;

  @override
  void initState() {
    super.initState();
    final source = widget.initialSource;
    if (source == null) return;

    _nameController.text = source.name;
    _refreshPolicy = source.refreshPolicy;
    if (source.config case XtreamSourceConfig(:final host, :final username)) {
      _hostController.text = host.toString();
      _usernameController.text = username;
    }
    // La contraseña NUNCA se precarga desde el almacén seguro (P5) — el
    // campo queda vacío a propósito, ver docstring de la clase.
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateHost(AppLocalizations l10n) {
    final result = normalizeXtreamPanelHost(_hostController.text.trim());
    return switch (result) {
      XtreamHostOk() => null,
      XtreamHostInvalid(reason: XtreamHostInvalidReason.empty) =>
        l10n.xtreamHostRequiredError,
      XtreamHostInvalid(reason: XtreamHostInvalidReason.malformed) =>
        l10n.xtreamHostInvalidError,
      XtreamHostInvalid(reason: XtreamHostInvalidReason.embeddedCredentials) =>
        l10n.xtreamHostCredentialsError,
    };
  }

  Future<void> _handleProbe() async {
    final hostResult = normalizeXtreamPanelHost(_hostController.text.trim());
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (hostResult is! XtreamHostOk || username.isEmpty || password.isEmpty) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() {
      _isProbing = true;
      _probeResult = null;
    });

    final probe = ref.read(xtreamProbeProvider);
    final result = await probe.probe(
      host: hostResult.host,
      username: username,
      password: password,
    );

    if (!mounted) return;
    setState(() {
      _isProbing = false;
      _probeResult = result;
    });
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final hostResult =
        normalizeXtreamPanelHost(_hostController.text.trim()) as XtreamHostOk;

    setState(() {
      _isSaving = true;
      _saveFailure = null;
    });

    final saveSource = ref.read(saveSourceProvider);
    final username = _usernameController.text.trim();
    // Campo vacío en edición == "sin cambios" (P5, patrón estándar de
    // formularios de credenciales): SaveSource no toca el almacén seguro
    // cuando `secret` es null. En alta, el validador ya exige contraseña,
    // así que aquí nunca llega vacío por ese camino.
    final password = _passwordController.text;
    final result = await saveSource(
      name: _nameController.text.trim(),
      config: XtreamSourceConfig(host: hostResult.host, username: username),
      refreshPolicy: _refreshPolicy,
      secret: password.isEmpty ? null : password,
      existing: widget.initialSource,
    );

    if (!mounted) return;
    switch (result) {
      case SaveSourceOk(:final source):
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.sourceSavedSnackbar(source.name))));
        Navigator.of(context).pop(source);
      case SaveSourceFailed(:final reason):
        setState(() {
          _isSaving = false;
          _saveFailure = reason;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.xtreamFormTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: XtreamSourceForm.nameFieldKey,
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.sourceNameLabel),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.sourceNameRequiredError
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: XtreamSourceForm.hostFieldKey,
                controller: _hostController,
                decoration: InputDecoration(labelText: l10n.xtreamHostLabel),
                keyboardType: TextInputType.url,
                validator: (_) => _validateHost(l10n),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: XtreamSourceForm.usernameFieldKey,
                controller: _usernameController,
                decoration: InputDecoration(labelText: l10n.xtreamUsernameLabel),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.xtreamUsernameRequiredError
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: XtreamSourceForm.passwordFieldKey,
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: l10n.xtreamPasswordLabel,
                  helperText: _isEditing ? l10n.xtreamPasswordKeepHint : null,
                  suffixIcon: IconButton(
                    key: XtreamSourceForm.togglePasswordVisibilityKey,
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    tooltip: _obscurePassword
                        ? l10n.xtreamPasswordShowTooltip
                        : l10n.xtreamPasswordHideTooltip,
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                // En edición, un campo vacío es válido — significa "sin
                // cambios" (ver _handleSave). Solo se exige en alta.
                validator: (value) => (!_isEditing && (value == null || value.isEmpty))
                    ? l10n.xtreamPasswordRequiredError
                    : null,
              ),
              const SizedBox(height: 16),
              RefreshPolicyDropdown(
                value: _refreshPolicy,
                onChanged: (policy) {
                  if (policy != null) setState(() => _refreshPolicy = policy);
                },
              ),
              if (_probeResult case final ProbeOk<XtreamProbeSummary> ok)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.xtreamProbeStatusLabel(ok.value.account.status)),
                      Text(
                        ok.value.account.expiresAt != null
                            ? l10n.xtreamProbeExpiresLabel(ok.value.account.expiresAt!)
                            : l10n.xtreamProbeNoExpiry,
                      ),
                      Text(
                        ok.value.liveStreamCount != null
                            ? l10n.xtreamProbeStreamCount(ok.value.liveStreamCount!)
                            : l10n.xtreamProbeStreamCountUnavailable,
                      ),
                    ],
                  ),
                ),
              if (_probeResult case final ProbeFailed<XtreamProbeSummary> failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(probeFailureReasonLabel(l10n, failed.reason)),
                ),
              if (_saveFailure case final reason?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(saveSourceFailureReasonLabel(l10n, reason)),
                ),
              const SizedBox(height: 16),
              SourceFormActionBar(
                probeLabel: l10n.xtreamProbeAction,
                isProbing: _isProbing,
                isSaving: _isSaving,
                onProbe: _handleProbe,
                onSave: _handleSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
