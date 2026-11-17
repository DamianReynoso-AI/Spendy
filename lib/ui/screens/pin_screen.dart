/// M-01 · Pantallas del PIN: desbloqueo con biometría opcional, captura
/// para activar, cambiar o desactivar, y restablecimiento con doble
/// confirmación (RF-45 a RF-50; CA-114 a CA-140).
///
/// Solo usa M-09; nunca `lib/data/` (RNF-30). El PIN nunca se muestra ni
/// se registra (RNF-20).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../core/result.dart';
import '../../modules/security/lock_controller.dart';
import '../../modules/security/pin_service.dart';
import '../widgets/confirm_dialog.dart';

/// Textos de las pantallas del PIN.
class PinTexts {
  PinTexts._();

  static const String unlockTitle = 'Ingresa tu PIN';
  static const String useBiometrics = 'Usar huella o rostro';
  static const String forgot = 'Olvidé mi PIN / Restablecer app';
  static const String continueLabel = 'Continuar';
  static const String reset1Title = '¿Restablecer SPENDY?';
  static const String reset1Body =
      'Se borrarán todos tus movimientos, recibos y ajustes guardados en '
      'este teléfono, y también tu PIN. Esta acción no se puede deshacer.';
  static const String reset2Title = 'Confirma el borrado';
  static const String reset2Body =
      'Es la última confirmación: al tocar "Borrar todo" se eliminan todos '
      'los datos locales de SPENDY y no se pueden recuperar.';
  static const String reset1Confirm = 'Continuar';
  static const String reset2Confirm = 'Borrar todo';
  static const String currentPin = 'Escribe tu PIN actual';
  static const String newPin = 'Escribe un PIN nuevo de 6 números';
  static const String confirmPin = 'Escribe el PIN otra vez';
}

/// Campo para escribir el PIN: solo números, oculto y de 6 dígitos. Al
/// llegar a 6 se envía solo; "Continuar" envía lo que haya para explicar
/// el formato si falta algo (CA-115).
class PinInput extends StatefulWidget {
  const PinInput({
    super.key,
    required this.label,
    required this.onSubmit,
    this.enabled = true,
  });

  final String label;
  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  State<PinInput> createState() => _PinInputState();
}

class _PinInputState extends State<PinInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text;
    _controller.clear();
    widget.onSubmit(value);
  }

  void _changed(String value) {
    if (value.length == AppConfig.pinLength) _submit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('pin_field'),
          controller: _controller,
          enabled: widget.enabled,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 12),
          maxLength: AppConfig.pinLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: widget.label),
          onChanged: _changed,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: widget.enabled ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text(PinTexts.continueLabel),
        ),
      ],
    );
  }
}

/// Cuenta regresiva del bloqueo de 30 s (CA-130). Avisa cada segundo.
class LockoutCountdown extends ChangeNotifier {
  Timer? _timer;
  DateTime? _until;

  /// Segundos que faltan, o `null` si no hay bloqueo.
  int? get seconds {
    final until = _until;
    if (until == null) return null;
    final ms = until.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? null : (ms / 1000).ceil();
  }

  bool get active => seconds != null;

  void start(Duration remaining) {
    _until = DateTime.now().add(remaining);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    if (seconds == null) {
      _timer?.cancel();
      _until = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Mensaje de error o de bloqueo bajo el campo.
class _PinStatus extends StatelessWidget {
  const _PinStatus({required this.message, required this.countdown});

  final String? message;
  final LockoutCountdown countdown;

  @override
  Widget build(BuildContext context) {
    final seconds = countdown.seconds;
    final text = seconds != null
        ? PinMessages.locked(Duration(seconds: seconds))
        : message;
    if (text == null) return const SizedBox(height: 24);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        key: const Key('pin_message'),
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Pantalla de desbloqueo. Mientras se muestra, la app no enseña ningún
/// dato (CA-119, CA-120).
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key, required this.controller});

  final LockController controller;

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final _countdown = LockoutCountdown();
  String? _message;
  bool _busy = false;
  bool _biometricsEnabled = false;

  LockController get _lock => widget.controller;

  @override
  void initState() {
    super.initState();
    _countdown.addListener(_refresh);
    _start();
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Carga un bloqueo vigente (también tras reiniciar, CA-131) y ofrece la
  /// biometría si está activa y no hay bloqueo (CA-124).
  Future<void> _start() async {
    final remaining = await _lock.pin.lockoutRemaining();
    final biometrics = await _lock.biometrics.isEnabled();
    if (!mounted) return;
    if (remaining != null) _countdown.start(remaining);
    setState(() => _biometricsEnabled = biometrics);
    if (biometrics && remaining == null) await _useBiometrics();
  }

  Future<void> _useBiometrics() async {
    if (_busy || _countdown.active) return;
    setState(() => _busy = true);
    final result = await _lock.biometrics.unlock();
    if (!mounted) return;
    if (result.success) return _lock.unlock();
    final enabled = await _lock.biometrics.isEnabled();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _biometricsEnabled = enabled;
      _message = result.message ?? _message;
    });
  }

  Future<void> _submit(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final check = await _lock.pin.verify(value);
    if (!mounted) return;
    if (check is PinAccepted) return _lock.unlock();
    if (check is PinLocked) _countdown.start(check.remaining);
    setState(() {
      _busy = false;
      _message = check.message;
    });
  }

  /// Dos confirmaciones seguidas; si cancela en cualquiera no se borra
  /// nada (CA-137, CA-138).
  Future<void> _reset() async {
    final first = await showConfirmDialog(
      context,
      title: PinTexts.reset1Title,
      content: PinTexts.reset1Body,
      confirmLabel: PinTexts.reset1Confirm,
    );
    if (!first || !mounted) return;
    final second = await showConfirmDialog(
      context,
      title: PinTexts.reset2Title,
      content: PinTexts.reset2Body,
      confirmLabel: PinTexts.reset2Confirm,
    );
    if (!second || !mounted) return;
    setState(() => _busy = true);
    final result = await _lock.resetApp();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.errorOrNull?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _busy || _countdown.active;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: 16),
                Text(
                  PinTexts.unlockTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                PinInput(
                  label: 'PIN',
                  enabled: !blocked,
                  onSubmit: _submit,
                ),
                _PinStatus(message: _message, countdown: _countdown),
                ..._secondaryActions(blocked),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _secondaryActions(bool blocked) => [
        if (_biometricsEnabled)
          OutlinedButton.icon(
            onPressed: blocked ? null : _useBiometrics,
            icon: const Icon(Icons.fingerprint),
            label: const Text(PinTexts.useBiometrics),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _busy ? null : _reset,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text(PinTexts.forgot),
        ),
      ];
}

/// Qué hace [PinSetupScreen].
enum PinSetupMode {
  /// Activar: PIN nuevo dos veces (RF-45).
  create('Activar PIN'),

  /// Cambiar: PIN actual y luego el nuevo dos veces (RF-49).
  change('Cambiar PIN'),

  /// Desactivar: solo el PIN actual (RF-49).
  disable('Desactivar PIN');

  const PinSetupMode(this.title);
  final String title;
}

enum _Step { current, newPin, confirm }

/// Captura del PIN desde Configuración. Devuelve `true` al terminar bien.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key, required this.pin, required this.mode});

  final PinService pin;
  final PinSetupMode mode;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _countdown = LockoutCountdown();
  late _Step _step;
  String _current = '';
  String _newPin = '';
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _step = widget.mode == PinSetupMode.create ? _Step.newPin : _Step.current;
    _countdown.addListener(() => mounted ? setState(() {}) : null);
    if (_step == _Step.current) _loadLockout();
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  Future<void> _loadLockout() async {
    final remaining = await widget.pin.lockoutRemaining();
    if (remaining != null && mounted) _countdown.start(remaining);
  }

  String get _label => switch (_step) {
        _Step.current => PinTexts.currentPin,
        _Step.newPin => PinTexts.newPin,
        _Step.confirm => PinTexts.confirmPin,
      };

  Future<void> _submit(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    switch (_step) {
      case _Step.current:
        await _submitCurrent(value);
      case _Step.newPin:
        _submitNew(value);
      case _Step.confirm:
        await _finish(value);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Valida el PIN actual con el mismo conteo y bloqueo (CA-134, CA-136).
  Future<void> _submitCurrent(String value) async {
    if (widget.mode == PinSetupMode.disable) {
      return _apply(await widget.pin.disable(value));
    }
    final check = await widget.pin.verify(value);
    if (check is PinLocked) _countdown.start(check.remaining);
    if (check is! PinAccepted) return _show(check.message);
    _current = value;
    _goTo(_Step.newPin);
  }

  void _submitNew(String value) {
    if (!PinService.isValidFormat(value)) return _show(PinMessages.format);
    _newPin = value;
    _goTo(_Step.confirm);
  }

  /// Si la confirmación no coincide se vuelve a pedir el PIN nuevo y el
  /// anterior sigue vigente (CA-116, CA-135).
  Future<void> _finish(String confirmation) async {
    final result = widget.mode == PinSetupMode.create
        ? await widget.pin.activate(_newPin, confirmation)
        : await widget.pin.change(_current, _newPin, confirmation);
    if (!result.isSuccess) _newPin = '';
    _apply(result);
  }

  void _apply(Result<void> result) {
    if (!mounted) return;
    final error = result.errorOrNull;
    if (error == null) return Navigator.of(context).pop(true);
    if (_step == _Step.confirm) _step = _Step.newPin;
    _show(error.message);
    _loadLockout();
  }

  void _goTo(_Step step) => setState(() {
        _step = step;
        _message = null;
      });

  void _show(String? message) {
    if (mounted) setState(() => _message = message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.mode.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PinInput(
                key: ValueKey(_step),
                label: _label,
                enabled: !_busy && !_countdown.active,
                onSubmit: _submit,
              ),
              _PinStatus(message: _message, countdown: _countdown),
            ],
          ),
        ),
      ),
    );
  }
}
