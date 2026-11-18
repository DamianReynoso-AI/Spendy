/// M-01 · Configuración: activar, cambiar o desactivar el PIN y activar
/// la biometría (RF-45, RF-47, RF-49; CA-114, CA-124, CA-126, CA-133).
///
/// Solo usa M-09; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/security/biometric_service.dart';
import '../../modules/security/lock_controller.dart';
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
  const SettingsScreen({super.key, required this.lock});

  final LockController lock;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loaded = false;
  bool _biometricsOn = false;
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
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _biometricsOn = on;
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
    ];
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
