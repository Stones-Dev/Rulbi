import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iptv_core/iptv_core.dart';

import '../../l10n/app_localizations.dart';
import 'm3u_probe.dart';
import 'probe_result.dart';
import 'save_source.dart';
import 'source_form_widgets.dart';
import 'source_providers.dart';

enum M3uOrigin { url, file }

/// Formulario de fuente M3U (ui-spec §2.8, S4 · Ola 2). No llama a
/// `ManageSources.addSource` (Ola 3): guarda la fuente con
/// `lastRefresh == null` vía `SaveSource` y vuelve al shell.
class M3uSourceForm extends ConsumerStatefulWidget {
  const M3uSourceForm({this.pickFile, super.key});

  /// Inyectable para tests de widget — el `file_picker` real dispara un
  /// diálogo nativo que no existe en el entorno de test. `null` (el valor
  /// de producción) usa `FilePicker.platform.pickFiles`.
  final Future<String?> Function()? pickFile;

  static const nameFieldKey = Key('m3uSourceForm.name');
  static const originSegmentKey = Key('m3uSourceForm.origin');
  static const urlFieldKey = Key('m3uSourceForm.url');
  static const fileFieldKey = Key('m3uSourceForm.file');
  static const pickFileButtonKey = Key('m3uSourceForm.pickFileButton');
  static const epgUrlFieldKey = Key('m3uSourceForm.epgUrl');
  static const userAgentFieldKey = Key('m3uSourceForm.userAgent');

  @override
  ConsumerState<M3uSourceForm> createState() => _M3uSourceFormState();
}

class _M3uSourceFormState extends ConsumerState<M3uSourceForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _fileController = TextEditingController();
  final _epgUrlController = TextEditingController();
  final _userAgentController = TextEditingController();

  M3uOrigin _origin = M3uOrigin.url;
  SourceRefreshPolicy _refreshPolicy = SourceRefreshPolicy.manual;

  bool _isProbing = false;
  bool _isSaving = false;
  ProbeResult<M3uProbeSummary>? _probeResult;
  SaveSourceFailureReason? _saveFailure;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _fileController.dispose();
    _epgUrlController.dispose();
    _userAgentController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picker = widget.pickFile ?? _defaultPickFile;
    final path = await picker();
    if (path == null || !mounted) return;
    setState(() => _fileController.text = path);
  }

  Future<String?> _defaultPickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m3u', 'm3u8'],
    );
    return result?.files.single.path;
  }

  String? _validateOriginField(AppLocalizations l10n) {
    if (_origin == M3uOrigin.url) {
      final value = _urlController.text.trim();
      if (value.isEmpty) return l10n.m3uUrlRequiredError;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          uri.host.isEmpty) {
        return l10n.m3uUrlInvalidError;
      }
      return null;
    }
    if (_fileController.text.trim().isEmpty) return l10n.m3uFileRequiredError;
    return null;
  }

  String? _validateEpgUrl(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return l10n.epgUrlInvalidError;
    }
    return null;
  }

  Future<void> _handleProbe() async {
    final l10n = AppLocalizations.of(context);
    if (_validateOriginField(l10n) != null) {
      _formKey.currentState?.validate();
      return;
    }

    setState(() {
      _isProbing = true;
      _probeResult = null;
    });

    final probe = ref.read(m3uProbeProvider);
    final userAgent = _userAgentController.text.trim();
    final result = _origin == M3uOrigin.url
        ? await probe.probeUrl(
            Uri.parse(_urlController.text.trim()),
            userAgent: userAgent.isEmpty ? null : userAgent,
          )
        : await probe.probeFile(_fileController.text.trim());

    if (!mounted) return;
    setState(() {
      _isProbing = false;
      _probeResult = result;
    });
  }

  Future<void> _handleSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _saveFailure = null;
    });

    final epgUrlText = _epgUrlController.text.trim();
    final epgUrl = epgUrlText.isEmpty ? null : Uri.tryParse(epgUrlText);
    final userAgent = _userAgentController.text.trim();

    final config = _origin == M3uOrigin.url
        ? M3uUrlSourceConfig(
            url: Uri.parse(_urlController.text.trim()),
            epgUrl: epgUrl,
            userAgent: userAgent.isEmpty ? null : userAgent,
          )
        : M3uFileSourceConfig(
            filePath: _fileController.text.trim(),
            epgUrl: epgUrl,
          );

    final saveSource = ref.read(saveSourceProvider);
    final result = await saveSource(
      name: _nameController.text.trim(),
      config: config,
      refreshPolicy: _refreshPolicy,
    );

    if (!mounted) return;
    switch (result) {
      case SaveSourceOk(:final source):
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.sourceSavedSnackbar(source.name))));
        Navigator.of(context).pop();
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
      appBar: AppBar(title: Text(l10n.m3uFormTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: M3uSourceForm.nameFieldKey,
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.sourceNameLabel),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.sourceNameRequiredError
                    : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<M3uOrigin>(
                key: M3uSourceForm.originSegmentKey,
                segments: [
                  ButtonSegment(
                    value: M3uOrigin.url,
                    label: Text(l10n.m3uOriginUrl),
                  ),
                  ButtonSegment(
                    value: M3uOrigin.file,
                    label: Text(l10n.m3uOriginFile),
                  ),
                ],
                selected: {_origin},
                onSelectionChanged: (selection) =>
                    setState(() => _origin = selection.first),
              ),
              const SizedBox(height: 16),
              if (_origin == M3uOrigin.url)
                TextFormField(
                  key: M3uSourceForm.urlFieldKey,
                  controller: _urlController,
                  decoration: InputDecoration(labelText: l10n.m3uUrlLabel),
                  keyboardType: TextInputType.url,
                  validator: (_) => _validateOriginField(l10n),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: M3uSourceForm.fileFieldKey,
                        controller: _fileController,
                        readOnly: true,
                        decoration: InputDecoration(labelText: l10n.m3uFileLabel),
                        validator: (_) => _validateOriginField(l10n),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: M3uSourceForm.pickFileButtonKey,
                      onPressed: _pickFile,
                      child: Text(l10n.m3uFilePickButton),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              TextFormField(
                key: M3uSourceForm.epgUrlFieldKey,
                controller: _epgUrlController,
                decoration: InputDecoration(labelText: l10n.epgUrlLabel),
                keyboardType: TextInputType.url,
                validator: (value) => _validateEpgUrl(l10n, value),
              ),
              const SizedBox(height: 16),
              RefreshPolicyDropdown(
                value: _refreshPolicy,
                onChanged: (policy) {
                  if (policy != null) setState(() => _refreshPolicy = policy);
                },
              ),
              ExpansionTile(
                title: Text(l10n.advancedSectionLabel),
                childrenPadding: const EdgeInsets.only(bottom: 16),
                children: [
                  TextFormField(
                    key: M3uSourceForm.userAgentFieldKey,
                    controller: _userAgentController,
                    decoration: InputDecoration(labelText: l10n.userAgentLabel),
                  ),
                ],
              ),
              if (_probeResult case final ProbeOk<M3uProbeSummary> ok)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.m3uProbeSuccessTitle(ok.value.channelCount)),
                      if (ok.value.discardedCount > 0)
                        Text(l10n.m3uProbeDiscardedNote(ok.value.discardedCount)),
                    ],
                  ),
                ),
              if (_probeResult case final ProbeFailed<M3uProbeSummary> failed)
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
                probeLabel: l10n.m3uProbeAction,
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
