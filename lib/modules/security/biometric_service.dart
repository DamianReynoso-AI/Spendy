/// M-09 · Biometría local (huella o rostro) como alternativa al PIN, con
/// el PIN de 6 dígitos siempre como respaldo (RF-47; CA-124 a CA-127;
/// AMB-07).
library;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/secure_store.dart';

/// Qué ofrece el teléfono (CA-126).
enum BiometricAvailability {
  /// Tiene sensor y al menos una huella o rostro registrado.
  available,

  /// No tiene sensor biométrico.
  noHardware,

  /// Tiene sensor pero nada registrado en el sistema.
  notEnrolled,
}

/// Resultado de pedir la biometría al sistema.
enum BiometricOutcome { success, failed, canceled, lockedOut, unavailable }

/// Adaptador del sistema biométrico; las pruebas usan uno falso.
abstract interface class BiometricAuthenticator {
  Future<BiometricAvailability> availability();

  /// Tipos registrados (por ejemplo "fingerprint,face"), ordenados.
  Future<String> enrollment();

  Future<BiometricOutcome> authenticate(String reason);
}

/// AUD-14: llave del Keystore ligada al registro biométrico. Android la
/// invalida si se agrega o quita una huella o un rostro, cosa que la lista
/// de tipos de [BiometricAuthenticator.enrollment] no nota.
abstract interface class BiometricKeyGuard {
  /// Crea (o recrea) la llave al activar la biometría.
  Future<void> create();

  /// `true` si sigue válida, `false` si cambió el registro o no existe,
  /// `null` si no se puede saber (sin Keystore, pruebas).
  Future<bool?> isValid();

  Future<void> delete();
}

/// Llave real por el canal de [MainActivity]. Los errores se tratan como
/// "no se puede saber"; nunca rompen el desbloqueo.
class PlatformBiometricKeyGuard implements BiometricKeyGuard {
  const PlatformBiometricKeyGuard();

  static const MethodChannel _channel =
      MethodChannel('mx.zenorbak.spendy/biometric_key');

  @override
  Future<void> create() => _call('create');

  @override
  Future<bool?> isValid() => _call('isValid');

  @override
  Future<void> delete() => _call('delete');

  Future<bool?> _call(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method);
    } on Object {
      return null;
    }
  }
}

/// Sin Keystore: solo se compara la lista de tipos (pruebas, escritorio).
class NoBiometricKeyGuard implements BiometricKeyGuard {
  const NoBiometricKeyGuard();
  @override
  Future<void> create() async {}
  @override
  Future<bool?> isValid() async => null;
  @override
  Future<void> delete() async {}
}

/// Adaptador real con `local_auth` (BiometricPrompt / LocalAuthentication).
class LocalAuthAuthenticator implements BiometricAuthenticator {
  LocalAuthAuthenticator([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricAvailability> availability() async {
    try {
      if (!await _auth.canCheckBiometrics) {
        return BiometricAvailability.noHardware;
      }
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on Object {
      return BiometricAvailability.noHardware;
    }
  }

  @override
  Future<String> enrollment() async {
    final types = await _auth.getAvailableBiometrics();
    return (types.map((t) => t.name).toList()..sort()).join(',');
  }

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.failed;
    } on LocalAuthException catch (e) {
      return _outcomeFor(e.code);
    }
  }

  static BiometricOutcome _outcomeFor(LocalAuthExceptionCode code) =>
      switch (code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricOutcome.canceled,
        LocalAuthExceptionCode.biometricLockout ||
        LocalAuthExceptionCode.temporaryLockout =>
          BiometricOutcome.lockedOut,
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet =>
          BiometricOutcome.unavailable,
        _ => BiometricOutcome.failed,
      };
}

/// Mensajes de la biometría.
class BiometricMessages {
  BiometricMessages._();

  static const String reason = 'Desbloquea SPENDY';
  static const String enableReason =
      'Confirma tu huella o rostro para usarlo en SPENDY';
  static const String noHardware =
      'Tu teléfono no tiene lector de huella ni reconocimiento de rostro. '
      'Puedes seguir usando tu PIN.';
  static const String notEnrolled =
      'No tienes huellas ni rostro registrados en el teléfono. Regístralos '
      'en los ajustes del sistema para usarlos aquí.';
  static const String failed = 'No te reconocimos. Ingresa tu PIN.';
  static const String changed =
      'Cambiaron las huellas o rostros registrados en el teléfono. '
      'Ingresa tu PIN; después puedes volver a activar la biometría.';
  static const String saveFailed =
      'No se pudo guardar el ajuste de biometría. Intenta de nuevo.';
}

/// Resultado de intentar desbloquear con biometría. Si no es [success],
/// la pantalla pide el PIN (CA-125, CA-127).
class BiometricUnlock {
  const BiometricUnlock._(this.success, this.message);

  static const BiometricUnlock ok = BiometricUnlock._(true, null);
  static const BiometricUnlock usePin = BiometricUnlock._(false, null);

  factory BiometricUnlock.fallback(String message) =>
      BiometricUnlock._(false, message);

  final bool success;

  /// Explicación para mostrar junto al teclado del PIN, si la hay.
  final String? message;
}

/// Activa, desactiva y usa la biometría. Solo se ofrece con PIN activo.
class BiometricService {
  BiometricService({
    required SecureStore store,
    required ErrorLogger logger,
    BiometricAuthenticator? authenticator,
    BiometricKeyGuard keyGuard = const NoBiometricKeyGuard(),
  })  : _store = store,
        _logger = logger,
        _auth = authenticator ?? LocalAuthAuthenticator(),
        _keyGuard = keyGuard;

  static const String module = 'M-09';

  final SecureStore _store;
  final ErrorLogger _logger;
  final BiometricAuthenticator _auth;
  final BiometricKeyGuard _keyGuard;

  Future<BiometricAvailability> availability() => _auth.availability();

  /// Explicación si la opción debe aparecer deshabilitada (CA-126).
  static String? unavailableReason(BiometricAvailability availability) =>
      switch (availability) {
        BiometricAvailability.available => null,
        BiometricAvailability.noHardware => BiometricMessages.noHardware,
        BiometricAvailability.notEnrolled => BiometricMessages.notEnrolled,
      };

  /// `true` si la persona activó la biometría.
  Future<bool> isEnabled() async {
    try {
      return await _store.readBiometricEnrollment() != null;
    } on Object {
      return false;
    }
  }

  /// Pide la biometría una vez para confirmar y la deja activada (CA-124).
  Future<Result<void>> enable() async {
    if (await _auth.availability() != BiometricAvailability.available) {
      return const Failure(AppError(
        type: ErrorType.validation,
        message: BiometricMessages.notEnrolled,
      ));
    }
    final outcome = await _auth.authenticate(BiometricMessages.enableReason);
    if (outcome != BiometricOutcome.success) {
      return const Failure(
        AppError(type: ErrorType.validation, message: BiometricMessages.failed),
      );
    }
    await _keyGuard.create();
    return _save(await _auth.enrollment());
  }

  Future<Result<void>> disable() => _save(null);

  /// Intenta desbloquear. Si la biometría falla, se cancela, está bloqueada
  /// por el sistema o cambió el registro de huellas, se pide el PIN
  /// (CA-125, CA-127). Si cambió el registro, además se apaga.
  Future<BiometricUnlock> unlock() async {
    final saved = await _store.readBiometricEnrollment();
    if (saved == null) return BiometricUnlock.usePin;
    if (await _enrollmentChanged(saved)) {
      await _save(null);
      return BiometricUnlock.fallback(BiometricMessages.changed);
    }
    final outcome = await _auth.authenticate(BiometricMessages.reason);
    return switch (outcome) {
      BiometricOutcome.success => BiometricUnlock.ok,
      BiometricOutcome.canceled => BiometricUnlock.usePin,
      _ => BiometricUnlock.fallback(BiometricMessages.failed),
    };
  }

  Future<bool> _enrollmentChanged(String saved) async {
    try {
      if (await _auth.availability() != BiometricAvailability.available) {
        return true;
      }
      if (await _keyGuard.isValid() == false) return true;
      return await _auth.enrollment() != saved;
    } on Object {
      return true;
    }
  }

  Future<Result<void>> _save(String? enrollment) async {
    if (enrollment == null) await _keyGuard.delete();
    try {
      await _store.writeBiometricEnrollment(enrollment);
      return const Success(null);
    } on Object catch (e) {
      await _logger.log(type: ErrorType.storageWrite, module: module, cause: e);
      return const Failure(AppError(
        type: ErrorType.storageWrite,
        message: BiometricMessages.saveFailed,
      ));
    }
  }
}
