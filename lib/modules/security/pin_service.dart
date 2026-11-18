/// M-09 · PIN de acceso: activar, verificar con límite de intentos y
/// bloqueo temporal, cambiar y desactivar (RF-45, RF-48, RF-49; RNF-15,
/// RNF-20, RNF-22; CA-114 a CA-118, CA-128 a CA-136).
///
/// El PIN solo vive en memoria mientras se compara. Se guarda únicamente
/// su hash con sal en [SecureStore] (Keystore/Keychain), nunca en SQLite
/// ni en la bitácora (RNF-15, RNF-20).
library;

import '../../config/app_config.dart';
import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/secure_store.dart';
import 'pin_hasher.dart';
import 'uptime_clock.dart';

/// Mensajes de la protección de acceso, en español de México (RNF-04).
class PinMessages {
  PinMessages._();

  static const String format = 'El PIN debe tener exactamente '
      '${AppConfig.pinLength} números, sin letras ni espacios.';
  static const String mismatch =
      'Los dos PIN no coinciden. Escríbelos de nuevo.';
  static const String alreadyActive = 'Ya tienes un PIN activo.';
  static const String notActive = 'No hay un PIN activo.';
  static const String storageFailed =
      'No se pudo leer o guardar el PIN en el almacén seguro del teléfono. '
      'Intenta de nuevo.';

  /// "PIN incorrecto. Te quedan 3 intentos." (CA-129).
  static String wrong(int remaining) => remaining == 1
      ? 'PIN incorrecto. Te queda 1 intento.'
      : 'PIN incorrecto. Te quedan $remaining intentos.';

  /// "Espera 30 segundos para volver a intentar." (CA-130). Desde un
  /// minuto se dice en minutos (AUD-04).
  static String locked(Duration remaining) {
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    if (seconds < 60) {
      return 'Demasiados intentos fallidos. Espera $seconds '
          '${seconds == 1 ? 'segundo' : 'segundos'} para volver a intentar.';
    }
    final minutes = (seconds / 60).ceil();
    return 'Demasiados intentos fallidos. Espera $minutes '
        '${minutes == 1 ? 'minuto' : 'minutos'} para volver a intentar.';
  }
}

/// Resultado de comparar un PIN.
sealed class PinCheck {
  const PinCheck();

  /// Mensaje para la persona usuaria; `null` si se aceptó.
  String? get message;
}

/// PIN correcto: el contador se reinicia (CA-128).
final class PinAccepted extends PinCheck {
  const PinAccepted();
  @override
  String? get message => null;
}

/// PIN incorrecto con los intentos que quedan (CA-129).
final class PinRejected extends PinCheck {
  const PinRejected(this.remainingAttempts);
  final int remainingAttempts;
  @override
  String get message => PinMessages.wrong(remainingAttempts);
}

/// Acceso bloqueado temporalmente (CA-130, CA-131).
final class PinLocked extends PinCheck {
  const PinLocked(this.remaining);
  final Duration remaining;
  @override
  String get message => PinMessages.locked(remaining);
}

/// El texto no tiene el formato de PIN; no cuenta como intento (CA-115).
final class PinInvalidFormat extends PinCheck {
  const PinInvalidFormat();
  @override
  String get message => PinMessages.format;
}

/// No hay PIN activo o falló el almacén seguro.
final class PinCheckError extends PinCheck {
  const PinCheckError(this.message);
  @override
  final String message;
}

/// Lógica del PIN. Usa [SecureStore] y un reloj inyectable para probar
/// el bloqueo de 30 segundos sin esperar.
class PinService {
  PinService({
    required SecureStore store,
    required ErrorLogger logger,
    PinHasher? hasher,
    DateTime Function()? clock,
    UptimeClock? uptime,
  })  : _store = store,
        _logger = logger,
        _hasher = hasher ?? PinHasher(),
        _clock = clock ?? DateTime.now,
        _uptime = uptime ?? noUptime;

  static const String module = 'M-09';
  static final RegExp _pinPattern = RegExp('^[0-9]{${AppConfig.pinLength}}\$');

  final SecureStore _store;
  final ErrorLogger _logger;
  final PinHasher _hasher;
  final DateTime Function() _clock;
  final UptimeClock _uptime;

  /// `true` si [pin] tiene exactamente 6 dígitos (RF-45, CA-115).
  static bool isValidFormat(String pin) => _pinPattern.hasMatch(pin);

  /// `true` si hay una credencial completa guardada. Si la lectura falla
  /// se asume activo: ante la duda, se protege.
  Future<bool> isEnabled() async {
    try {
      return await _store.readCredential() != null;
    } on Object catch (e) {
      await _log(ErrorType.storageRead, e);
      return true;
    }
  }

  /// Activa el PIN capturado dos veces (RF-45; CA-114 a CA-117). La
  /// credencial se escribe en una sola operación al final: si la app se
  /// cierra antes, no queda ningún PIN a medias.
  Future<Result<void>> activate(String pin, String confirmation) async {
    final invalid = _checkNewPin(pin, confirmation);
    if (invalid != null) return invalid;
    try {
      if (await _store.readCredential() != null) {
        return _failure(ErrorType.validation, PinMessages.alreadyActive);
      }
      await _store.clearAttempts();
      await _store.writeCredential(await _newCredential(pin));
      return const Success(null);
    } on Object catch (e) {
      return _storageFailure(e);
    }
  }

  /// Compara [pin] con el guardado aplicando intentos y bloqueo (RF-48;
  /// CA-128 a CA-132). Se usa al desbloquear y en Configuración (CA-136).
  Future<PinCheck> verify(String pin) async {
    try {
      final remaining = await lockoutRemaining();
      if (remaining != null) return PinLocked(remaining);
      if (!isValidFormat(pin)) return const PinInvalidFormat();
      final credential = await _store.readCredential();
      if (credential == null) return const PinCheckError(PinMessages.notActive);
      if (await _matches(pin, credential)) {
        await _store.clearAttempts();
        await _store.clearLockoutCount();
        return const PinAccepted();
      }
      return await _registerFailure();
    } on Object catch (e) {
      await _log(ErrorType.storageRead, e);
      return const PinCheckError(PinMessages.storageFailed);
    }
  }

  /// Tiempo que falta de bloqueo, o `null` si no hay. Si el bloqueo ya
  /// venció, reinicia el contador para dar 5 intentos nuevos (CA-132).
  ///
  /// AUD-04: cuenta el que diga más tiempo entre la hora del teléfono y el
  /// reloj monótono, así que adelantar la hora no quita el bloqueo. Si el
  /// reloj de la hora se atrasó, el bloqueo nunca dura más que el escalón
  /// actual a partir de ahora.
  Future<Duration?> lockoutRemaining() async {
    final until = await _store.readLockoutUntil();
    if (until == null) return null;
    final step = _stepFor(await _store.readLockoutCount());
    final now = _clock().toUtc();
    var byWall = until.difference(now);
    if (byWall > step) {
      await _store.writeLockoutUntil(now.add(step));
      byWall = step;
    }
    final byUptime = await _uptimeRemaining(step);
    final remaining = byUptime != null && byUptime > byWall ? byUptime : byWall;
    if (remaining <= Duration.zero) {
      await _store.clearAttempts();
      return null;
    }
    return remaining;
  }

  /// Lo que falta según el reloj monótono, o `null` si no hay dato o el
  /// teléfono se reinició (el reloj volvió a empezar).
  Future<Duration?> _uptimeRemaining(Duration step) async {
    final start = await _store.readLockoutUptime();
    final current = await _uptime();
    if (start == null || current == null || current < start) return null;
    return step - Duration(milliseconds: current - start);
  }

  /// Duración del bloqueo número [count] (1 = el primero).
  static Duration _stepFor(int count) {
    const steps = AppConfig.pinLockoutSteps;
    final index = (count - 1).clamp(0, steps.length - 1);
    return steps[index];
  }

  /// Cambia el PIN (RF-49; CA-133 a CA-136). Primero revisa que el nuevo
  /// PIN sea válido y coincida (eso no gasta intentos); luego valida el
  /// actual con el mismo conteo y bloqueo. Si algo falla, el PIN anterior
  /// sigue vigente (CA-135).
  Future<Result<void>> change(
    String current,
    String newPin,
    String confirmation,
  ) async {
    final invalid = _checkNewPin(newPin, confirmation);
    if (invalid != null) return invalid;
    final check = await verify(current);
    if (check is! PinAccepted) return _checkFailure(check);
    try {
      await _store.writeCredential(await _newCredential(newPin));
      return const Success(null);
    } on Object catch (e) {
      return _storageFailure(e);
    }
  }

  /// Desactiva el PIN tras validar el actual (RF-49; CA-133, CA-134,
  /// CA-136). También apaga la biometría, que depende del PIN.
  Future<Result<void>> disable(String current) async {
    final check = await verify(current);
    if (check is! PinAccepted) return _checkFailure(check);
    try {
      await _store.clearSecurity();
      return const Success(null);
    } on Object catch (e) {
      return _storageFailure(e);
    }
  }

  Result<void>? _checkNewPin(String pin, String confirmation) {
    if (!isValidFormat(pin)) {
      return const Failure(
        AppError(type: ErrorType.validation, message: PinMessages.format),
      );
    }
    if (pin != confirmation) {
      return const Failure(
        AppError(type: ErrorType.validation, message: PinMessages.mismatch),
      );
    }
    return null;
  }

  Future<PinCredential> _newCredential(String pin) async {
    final salt = _hasher.newSalt();
    return PinCredential(
      iterations: _hasher.iterations,
      salt: salt,
      hash: await _hasher.hash(pin, salt),
    );
  }

  Future<bool> _matches(String pin, PinCredential credential) async {
    final hash = await _hasher.hash(
      pin,
      credential.salt,
      iterations: credential.iterations,
    );
    return constantTimeEquals(hash, credential.hash);
  }

  /// Suma un fallo; al quinto consecutivo bloquea (CA-129, CA-130). El
  /// primer bloqueo dura 30 s y los siguientes, más (AUD-04).
  Future<PinCheck> _registerFailure() async {
    final failed = await _store.readFailedAttempts() + 1;
    await _store.writeFailedAttempts(failed);
    if (failed < AppConfig.maxPinAttempts) {
      return PinRejected(AppConfig.maxPinAttempts - failed);
    }
    final count = await _store.readLockoutCount() + 1;
    final step = _stepFor(count);
    await _store.writeLockoutCount(count);
    await _store.writeLockoutUptime(await _uptime());
    await _store.writeLockoutUntil(_clock().toUtc().add(step));
    return PinLocked(step);
  }

  Result<void> _checkFailure(PinCheck check) => Failure(
        AppError(
          type: ErrorType.validation,
          message: check.message ?? PinMessages.storageFailed,
        ),
      );

  Result<void> _failure(ErrorType type, String message) =>
      Failure(AppError(type: type, message: message));

  Future<Result<void>> _storageFailure(Object e) async {
    await _log(ErrorType.storageWrite, e);
    return _failure(ErrorType.storageWrite, PinMessages.storageFailed);
  }

  /// Solo registra tipo y clase de la excepción; nunca el PIN (RNF-20).
  Future<void> _log(ErrorType type, Object e) =>
      _logger.log(type: type, module: module, cause: e);
}
