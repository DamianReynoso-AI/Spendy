/// M-01 · Configuración: activar, cambiar o desactivar el PIN y activar
/// la biometría (RF-45, RF-47, RF-49; CA-114, CA-124, CA-126, CA-133).
///
/// También concentra la lectura de recibos con Gemini (clave propia), los
/// presupuestos y la copia de seguridad.
///
/// Solo usa módulos de lógica; nunca `lib/data/` (RNF-30).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/backup/backup_service.dart';
import '../../modules/budgets/budget_service.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/ocr/ocr_key_service.dart';
import '../../modules/security/biometric_service.dart';
import '../../modules/security/lock_controller.dart';
import '../theme/spendy_theme.dart';
import 'budget_screen.dart';
import 'pin_screen.dart';

/// Textos de Configuración.
class SettingsTexts {
  SettingsTexts._();

  static const String title = 'Configuración';
  static const String pinTitle = 'PIN de acceso';
  static const String pinOn = 'Se pide al abrir la app y al volver después '
      'de más de 1 minuto.';
  static const String pinOff = 'Protege la app con un PIN de 6 números.';
  static const String changePin = 'Cambiar PIN';
  static const String biometricsTitle = 'Desbloquear con huella o rostro';
  static const String biometricsOn = 'Tu PIN sigue funcionando como respaldo.';
  static const String biometricsNeedsPin = 'Primero activa el PIN.';
  static const String activated = 'PIN activado.';
  static const String changed = 'PIN cambiado.';
  static const String deactivated = 'PIN desactivado.';
}

/// Pantalla de Configuración.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.lock,
    this.ocrKey,
    this.backup,
    this.budgets,
    this.catalog,
  });

  final LockController lock;

  /// Clave de Gemini para leer recibos (M-05).
  final OcrKeyService? ocrKey;

  /// Copia de seguridad (M-16).
  final BackupService? backup;

  /// Presupuestos (M-14) y el catálogo para editarlos.
  final BudgetService? budgets;
  final CategoryCatalog? catalog;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loaded = false;
  bool _biometricsOn = false;
  OcrKeyStatus _keyStatus = const OcrKeyStatus(null);
  bool _busy = false;
  BiometricAvailability _availability = BiometricAvailability.noHardware;

  LockController get _lock => widget.lock;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final availability = await _lock.biometrics.availability();
    final on = await _lock.biometrics.isEnabled();
    final keyStatus = await widget.ocrKey?.status();
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _biometricsOn = on;
      _keyStatus = keyStatus ?? const OcrKeyStatus(null);
      _loaded = true;
    });
  }

  Future<void> _openPin(PinSetupMode mode, String doneMessage) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(pin: _lock.pin, mode: mode),
      ),
    );
    if (done != true) return;
    await _lock.refresh();
    await _load();
    _snack(doneMessage);
  }

  void _togglePin(bool on) => on
      ? _openPin(PinSetupMode.create, SettingsTexts.activated)
      : _openPin(PinSetupMode.disable, SettingsTexts.deactivated);

  Future<void> _toggleBiometrics(bool on) async {
    final result =
        on ? await _lock.biometrics.enable() : await _lock.biometrics.disable();
    if (!mounted) return;
    if (result case Failure(:final error)) _snack(error.message);
    await _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _lock,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text(SettingsTexts.title)),
        body: _loaded
            ? ListView(children: _tiles())
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  List<Widget> _tiles() {
    final pinOn = _lock.pinEnabled;
    return [
      const _Section('Seguridad'),
      SwitchListTile(
        key: const Key('pin_switch'),
        title: const Text(SettingsTexts.pinTitle),
        subtitle: Text(pinOn ? SettingsTexts.pinOn : SettingsTexts.pinOff),
        value: pinOn,
        onChanged: _togglePin,
      ),
      ListTile(
        key: const Key('change_pin'),
        enabled: pinOn,
        leading: const Icon(Icons.password),
        title: const Text(SettingsTexts.changePin),
        onTap: () => _openPin(PinSetupMode.change, SettingsTexts.changed),
      ),
      _biometricsTile(pinOn),
      ..._ocrTiles(),
      ..._budgetTiles(),
      ..._backupTiles(),
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _ocrTiles() => [
        if (widget.ocrKey != null) ...[
          const _Section('Lectura de recibos'),
          ListTile(
            key: const Key('gemini_key'),
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Leer recibos con Gemini'),
            subtitle: Text(_keyStatus.configured
                ? 'Activado con tu clave (termina en ${_keyStatus.lastChars}).'
                : 'Sin clave: los recibos se leen en el teléfono. Agrega tu '
                    'clave gratuita de Google AI Studio para leerlos mejor.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editKey,
          ),
        ],
      ];

  List<Widget> _budgetTiles() => [
        if (widget.budgets != null && widget.catalog != null) ...[
          const _Section('Presupuestos'),
          ListTile(
            key: const Key('budgets_tile'),
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Presupuestos mensuales'),
            subtitle: const Text('Límite de gasto por categoría.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => BudgetScreen(
                  budgets: widget.budgets!, catalog: widget.catalog!),
            )),
          ),
        ],
      ];

  List<Widget> _backupTiles() => [
        if (widget.backup != null) ...[
          const _Section('Copia de seguridad'),
          ListTile(
            key: const Key('backup_export'),
            enabled: !_busy,
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Crear copia de seguridad'),
            subtitle: const Text('Archivo cifrado con tu contraseña, con '
                'movimientos, fotos y presupuestos. Tú eliges dónde guardarlo.'),
            onTap: _exportBackup,
          ),
          ListTile(
            key: const Key('backup_restore'),
            enabled: !_busy,
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Restaurar copia de seguridad'),
            subtitle: const Text('Reemplaza los datos de este teléfono por los '
                'de un archivo .spendy.'),
            onTap: _restoreBackup,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
        ],
      ];

  Future<void> _editKey() async {
    final service = widget.ocrKey!;
    final result = await showDialog<_KeyAction>(
      context: context,
      builder: (_) => _KeyDialog(configured: _keyStatus.configured),
    );
    if (result == null) return;
    final Result<void> saved =
        result.remove ? await service.remove() : await service.save(result.key);
    if (!mounted) return;
    switch (saved) {
      case Failure(:final error):
        _snack(error.message);
      case Success():
        _snack(result.remove
            ? 'Clave quitada. Los recibos se leerán en el teléfono.'
            : 'Clave guardada. Los recibos se leerán con Gemini.');
    }
    await _load();
  }

  Future<void> _exportBackup() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(
        title: 'Crear copia de seguridad',
        message: 'Elige una contraseña para cifrar la copia. Sin ella no se '
            'puede restaurar: guárdala en un lugar seguro.',
        confirm: true,
      ),
    );
    if (password == null) return;
    setState(() => _busy = true);
    final result = await widget.backup!.export(password);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Failure(:final error)) _snack(error.message);
  }

  Future<PlatformFile?> _pickBackupFile() async {
    try {
      return await FilePicker.pickFile(dialogTitle: 'Copia de SPENDY');
    } on Object {
      _snack('No se pudo abrir el selector de archivos.');
      return null;
    }
  }

  Future<bool?> _confirmRestore() => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Restaurar una copia?'),
          content: const Text('Todos los movimientos, fotos y presupuestos de '
              'este teléfono se reemplazarán por los de la copia. Esto no se '
              'puede deshacer.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elegir archivo'),
            ),
          ],
        ),
      );

  Future<void> _restoreBackup() async {
    final ok = await _confirmRestore();
    if (ok != true || !mounted) return;
    final file = await _pickBackupFile();
    if (file == null || !mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(
        title: 'Contraseña de la copia',
        message: 'Escribe la contraseña con la que creaste la copia.',
        confirm: false,
      ),
    );
    if (password == null) return;
    setState(() => _busy = true);
    final bytes = await file.readAsBytes();
    final result = await widget.backup!.restore(bytes, password);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Failure(:final error):
        _snack(error.message);
      case Success(value: final s):
        _snack('Copia restaurada: ${s.movements} movimientos, '
            '${s.receipts} recibos y ${s.budgets} presupuestos.');
    }
  }

  /// Si el teléfono no tiene biometría, la opción aparece deshabilitada
  /// con la explicación (CA-126).
  Widget _biometricsTile(bool pinOn) {
    final reason = BiometricService.unavailableReason(_availability);
    final enabled = pinOn && reason == null;
    final subtitle = reason ??
        (pinOn ? SettingsTexts.biometricsOn : SettingsTexts.biometricsNeedsPin);
    return SwitchListTile(
      key: const Key('biometrics_switch'),
      secondary: const Icon(Icons.fingerprint),
      title: const Text(SettingsTexts.biometricsTitle),
      subtitle: Text(subtitle),
      value: enabled && _biometricsOn,
      onChanged: enabled ? _toggleBiometrics : null,
    );
  }
}

/// Título de sección.
class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Semantics(
          header: true,
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: SpendyPalette.of(context).muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
        ),
      );
}

class _KeyAction {
  const _KeyAction.save(this.key) : remove = false;
  const _KeyAction.remove()
      : key = '',
        remove = true;

  final String key;
  final bool remove;
}

/// Pide la clave de Google AI Studio. No la muestra después de guardarla.
class _KeyDialog extends StatefulWidget {
  const _KeyDialog({required this.configured});

  final bool configured;

  @override
  State<_KeyDialog> createState() => _KeyDialogState();
}

class _KeyDialogState extends State<_KeyDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (!OcrKeyService.looksValid(_text.text)) {
      setState(() => _error = OcrKeyMessages.invalid);
      return;
    }
    Navigator.pop(context, _KeyAction.save(_text.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Clave de Gemini'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('1. Entra a aistudio.google.com con tu cuenta de '
                  'Google.\n2. Toca "Get API key" y copia la clave.\n'
                  '3. Pégala aquí. Se guarda cifrada solo en este teléfono.'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('gemini_key_field'),
                controller: _text,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Clave de API',
                  errorText: _error,
                  errorMaxLines: 4,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.configured)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const _KeyAction.remove()),
              child: const Text('Quitar clave'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: _save, child: const Text('Guardar')),
        ],
      );
}

/// Pide la contraseña de la copia; con [confirm] la pide dos veces.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.message,
    required this.confirm,
  });

  final String title;
  final String message;
  final bool confirm;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _ok() {
    final text = _first.text;
    if (widget.confirm && text.length < BackupCodec.minPasswordLength) {
      setState(() => _error = BackupMessages.shortPassword);
      return;
    }
    if (widget.confirm && text != _second.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (text.isEmpty) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.message),
              const SizedBox(height: 12),
              TextField(
                key: const Key('backup_password'),
                controller: _first,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  errorText: widget.confirm ? null : _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (widget.confirm) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('backup_password_confirm'),
                  controller: _second,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Repite la contraseña',
                    errorText: _error,
                    errorMaxLines: 2,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(onPressed: _ok, child: const Text('Continuar')),
        ],
      );
}
