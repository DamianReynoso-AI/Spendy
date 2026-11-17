/// M-09 · Control de la sesión bloqueada: pedir el PIN al abrir la app y
/// al volver tras más de 1 minuto en segundo plano, y ocultar el contenido
/// en el selector de apps recientes (RF-46, RF-50; RNF-19; CA-119 a
/// CA-123, CA-140; AMB-07).
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../config/app_config.dart';
import '../../core/result.dart';
import 'biometric_service.dart';
import 'pin_service.dart';
import 'reset_service.dart';

/// Protección del sistema contra capturas de la ventana (RNF-19).
abstract interface class ScreenShield {
  Future<void> setProtected(bool protected);
}

/// Android: `FLAG_SECURE` (el selector de recientes muestra la ventana en
/// blanco y no se permiten capturas). iOS: cubre la ventana con un color
/// sólido al salir de primer plano.
class PluginScreenShield implements ScreenShield {
  const PluginScreenShield();

  static const Color _cover = Color(0xFFFFFFFF);

  @override
  Future<void> setProtected(bool protected) async {
    try {
      if (protected) {
        await ScreenProtector.protectDataLeakageOn();
        await ScreenProtector.protectDataLeakageWithColor(_cover);
      } else {
        await ScreenProtector.protectDataLeakageOff();
        await ScreenProtector.protectDataLeakageWithColorOff();
      }
    } on MissingPluginException {
      // Plataforma sin el plugin (pruebas o escritorio): queda la cubierta
      // de Flutter de [LockController.obscured].
    } on PlatformException {
      // Igual que arriba: nunca romper la app por la protección visual.
    }
  }
}

/// Sin protección del sistema (pruebas).
class NoScreenShield implements ScreenShield {
  const NoScreenShield();
  @override
  Future<void> setProtected(bool protected) async {}
}

/// Estado del bloqueo que escucha la interfaz.
class LockController extends ChangeNotifier {
  LockController({
    required this.pin,
    required this.biometrics,
    required this.reset,
    ScreenShield shield = const PluginScreenShield(),
    DateTime Function()? clock,
  })  : _shield = shield,
        _clock = clock ?? DateTime.now;

  final PinService pin;
  final BiometricService biometrics;
  final ResetService reset;
  final ScreenShield _shield;
  final DateTime Function() _clock;

  bool _ready = false;
  bool _pinEnabled = false;
  bool _locked = false;
  bool _obscured = false;
  int _generation = 0;
  DateTime? _backgroundedAt;

  /// Ya se leyó si hay PIN; antes no se muestra nada.
  bool get ready => _ready;

  /// Hay PIN activo.
  bool get pinEnabled => _pinEnabled;

  /// Se debe mostrar la pantalla de PIN en lugar de la app (CA-119).
  bool get locked => _locked;

  /// Bandera de ocultamiento: la app no está en primer plano y hay PIN,
  /// así que se cubre el contenido (RNF-19, CA-123).
  bool get obscured => _obscured;

  /// Cambia tras un restablecimiento para reconstruir toda la app desde
  /// el aviso de privacidad (CA-140).
  int get generation => _generation;

  /// Arranque en frío: con PIN activo, la app inicia bloqueada (CA-119).
  Future<void> init() async {
    _pinEnabled = await pin.isEnabled();
    _locked = _pinEnabled;
    _ready = true;
    await _shield.setProtected(_pinEnabled);
    notifyListeners();
  }

  /// Vuelve a leer si hay PIN (tras activarlo o desactivarlo).
  Future<void> refresh() async {
    _pinEnabled = await pin.isEnabled();
    if (!_pinEnabled) _locked = false;
    await _shield.setProtected(_pinEnabled);
    notifyListeners();
  }

  /// La persona se autenticó con PIN o biometría (CA-128, CA-124).
  void unlock() {
    _locked = false;
    notifyListeners();
  }

  /// Ciclo de vida de la app (CA-121 a CA-123).
  void handleLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.inactive:
        _setObscured(_pinEnabled);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundedAt ??= _clock();
        _setObscured(_pinEnabled);
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Más de 60 s en segundo plano bloquea; 60 s o menos, no (CA-121,
  /// CA-122). Se cuenta desde que la app deja de verse (AMB-07).
  void _onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (_pinEnabled &&
        since != null &&
        _clock().difference(since) > AppConfig.backgroundLockAfter) {
      _locked = true;
    }
    _obscured = false;
    notifyListeners();
  }

  void _setObscured(bool value) {
    if (_obscured == value) return;
    _obscured = value;
    notifyListeners();
  }

  /// Restablece la app (RF-50). Si sale bien, quita el bloqueo y pide
  /// reconstruir la app para mostrar el aviso de privacidad (CA-140).
  Future<Result<void>> resetApp() async {
    final result = await reset.resetAll();
    if (result.isSuccess) {
      _pinEnabled = false;
      _locked = false;
      _generation++;
      await _shield.setProtected(false);
      notifyListeners();
    }
    return result;
  }

  @visibleForTesting
  DateTime? get backgroundedAt => _backgroundedAt;
}
