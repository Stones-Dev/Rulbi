import 'dart:io';

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

/// Formulario de fuente M3U (ui-spec §2.8, S4 · Ola 2; edición desde S4 ·
/// Ola 3). No llama a `ManageSources.addSource`/`refreshSource` — eso es
/// `ImportController` (Ola 3), invocado por Gestión de fuentes tras
/// recibir el `Source` que devuelve este formulario al hacer pop.
///
/// [initialSource] `!= null` activa el modo edición (Gestión de fuentes):
/// precarga los campos desde el `Source` existente y pasa `existing` a
/// `SaveSource` para conservar `id`/`enabled`/`lastRefresh`.
class M3uSourceForm extends ConsumerStatefulWidget {
  const M3uSourceForm({this.pickFile, this.initialSource, super.key});

  /// Inyectable para tests de widget — el `file_picker` real dispara un
  /// diálogo nativo que no existe en el entorno de test. `null` (el valor
  /// de producción) usa `FilePicker.platform.pickFiles`.
  final Future<String?> Function()? pickFile;

  /// Fuente a editar, o `null` para dar de alta una nueva.
  final Source? initialSource;

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
  void initState() {
    super.initState();
    final source = widget.initialSource;
    if (source == null) return;

    _nameController.text = source.name;
    _refreshPolicy = source.refreshPolicy;
    switch (source.config) {
      case M3uUrlSourceConfig(:final url, :final epgUrl, :final userAgent):
        _origin = M3uOrigin.url;
        _urlController.text = url.toString();
        if (epgUrl != null) _epgUrlController.text = epgUrl.toString();
        if (userAgent != null) _userAgentController.text = userAgent;
      case M3uFileSourceConfig(:final filePath, :final epgUrl):
        _origin = M3uOrigin.file;
        _fileController.text = filePath;
        if (epgUrl != null) _epgUrlController.text = epgUrl.toString();
      case XtreamSourceConfig():
        // No debería llegar aquí: Gestión de fuentes abre este formulario
        // solo para SourceKind.m3uUrl/m3uFile (ver sources_screen.dart).
        break;
    }
  }

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
    // Android filtra `FileType.custom` por MIME type vía el Storage Access
    // Framework, no por extensión — `.m3u`/`.m3u8` no tienen entrada
    // estándar en el registro de MIME de Android, así que el picker puede
    // abrir sin mostrar ningún archivo (gotcha documentado del propio
    // paquete file_picker, S7 · Móvil base). `FileType.any` evita el
    // filtrado ahí; en Desktop/Linux se mantiene el filtro estricto que ya
    // funcionaba. No se valida la extensión tras elegir: el archivo puede
    // legítimamente no terminar en `.m3u` (nombres arbitrarios al
    // descargar) y el parser (`M3uProbe`, botón "Probar") ya es quien
    // decide si el contenido es válido — RNF-02, no aborta con datos
    // malformados.
    final result = await FilePicker.platform.pickFiles(
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : ['m3u', 'm3u8'],
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
                textInputAction: TextInputAction.next,
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
                  textInputAction: TextInputAction.next,
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
                // `done`, no `next`: el siguiente campo real (User-Agent)
                // vive dentro del ExpansionTile "Avanzado", colapsado por
                // defecto — encadenar ahí saltaría a un campo invisible.
                textInputAction: TextInputAction.done,
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
                    textInputAction: TextInputAction.done,
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
