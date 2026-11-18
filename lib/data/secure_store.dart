/// M-11 · Almacén seguro del sistema para la protección de acceso
/// (RF-45, RF-48, RF-50; RNF-15, RNF-22; CA-117, CA-118, CA-131).
///
/// Usa el Keystore de Android y el Keychain de iOS mediante
/// `flutter_secure_storage`. Aquí, y en ningún otro lugar, viven:
/// - la credencial del PIN: hash PBKDF2 con su sal aleatoria, nunca el
///   PIN en texto plano (RNF-15, CA-118);
/// - el contador de intentos fallidos consecutivos y la hora de fin del
///   bloqueo, para que sobrevivan al cierre de la app y al reinicio del
///   teléfono (RNF-22, CA-131);
/// - si la biometría está activada (RF-47);
/// - la bandera de restablecimiento en curso (RF-50, CA-139).
///
/// Nada de esto se guarda en SQLite.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credencial guardada del PIN: algoritmo, iteraciones, sal y hash en
/// Base64. Se escribe como un solo valor para que la activación sea
/// atómica: o existe completa o no existe (CA-117).
class PinCredential {
  const PinCredential({
    required this.iterations,
    required this.salt,
    required this.hash,
  });

  /// Identificador del algoritmo de derivación.
  static const String algorithm = 'pbkdf2-sha256';

  final int iterations;
  final List<int> salt;
  final List<int> hash;

  String encode() => jsonEncode({
        'alg': algorithm,
        'iter': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
      });

  /// Devuelve `null` si el valor está dañado o es de otro algoritmo; en
  /// ese caso se trata como si no hubiera PIN completo.
  static PinCredential? decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['alg'] != algorithm) return null;
      return PinCredential(
        iterations: map['iter'] as int,
        salt: base64Decode(map['salt'] as String),
        hash: base64Decode(map['hash'] as String),
      );
    } on Object {
      return null;
    }
  }
}

/// Operaciones mínimas de un almacén llave-valor seguro. Permite usar el
/// almacén del sistema en la app y uno en memoria en las pruebas.
abstract interface class SecureBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keystore (Android) / Keychain (iOS).
class PlatformSecureBackend implements SecureBackend {
  const PlatformSecureBackend([
    this._storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        // Solo en este dispositivo y nunca en respaldos de iCloud.
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Almacén en memoria para pruebas. Simula un fallo de escritura con
/// [failWrites] y conserva los datos entre "reinicios" si se reutiliza.
class MemorySecureBackend implements SecureBackend {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('escritura simulada fallida');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('borrado simulado fallido');
    values.remove(key);
  }
}

/// Acceso tipado a las claves de la protección de acceso.
class SecureStore {
  SecureStore([SecureBackend? backend])
      : _backend = backend ?? const PlatformSecureBackend();

  final SecureBackend _backend;

  static const String pinCredentialKey = 'pin_credential';
  static const String failedAttemptsKey = 'failed_attempts';
  static const String lockoutUntilKey = 'lockout_until';
  static const String biometricEnabledKey = 'biometric_enabled';
  static const String resetPendingKey = 'reset_pending';

  /// Clave de la API de Gemini que captura la persona en Ajustes (TEC-01:
  /// nunca va dentro del APK). No es parte de la seguridad del PIN: no la
  /// borra desactivar el PIN, solo el restablecimiento total.
  static const String geminiApiKeyKey = 'gemini_api_key';

  /// Claves que borra el restablecimiento total. La bandera de
  /// restablecimiento no está aquí: se borra al final, aparte.
  static const List<String> securityKeys = [
    pinCredentialKey,
    failedAttemptsKey,
    lockoutUntilKey,
    biometricEnabledKey,
  ];

  Future<PinCredential?> readCredential() async =>
      PinCredential.decode(await _backend.read(pinCredentialKey));

  /// Una sola escritura: la credencial nunca queda a medias (CA-117).
  Future<void> writeCredential(PinCredential credential) =>
      _backend.write(pinCredentialKey, credential.encode());

  Future<int> readFailedAttempts() async =>
      int.tryParse(await _backend.read(failedAttemptsKey) ?? '') ?? 0;

  Future<void> writeFailedAttempts(int count) =>
      _backend.write(failedAttemptsKey, '$count');

  /// Fin del bloqueo en milisegundos desde la época (UTC), o `null`.
  Future<DateTime?> readLockoutUntil() async {
    final ms = int.tryParse(await _backend.read(lockoutUntilKey) ?? '');
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> writeLockoutUntil(DateTime until) => _backend.write(
      lockoutUntilKey, '${until.toUtc().millisecondsSinceEpoch}');

  /// Reinicia el contador y quita el bloqueo (CA-128, CA-132).
  Future<void> clearAttempts() async {
    await _backend.delete(lockoutUntilKey);
    await _backend.delete(failedAttemptsKey);
  }

  /// Biometría activada: guarda la huella digital del registro biométrico
  /// del teléfono al activarla (tipos registrados), para notar si cambió
  /// (CA-127). `null` = biometría apagada.
  Future<String?> readBiometricEnrollment() =>
      _backend.read(biometricEnabledKey);

  Future<void> writeBiometricEnrollment(String? enrollment) =>
      enrollment == null
          ? _backend.delete(biometricEnabledKey)
          : _backend.write(biometricEnabledKey, enrollment);

  /// Borra PIN, intentos, bloqueo y biometría (desactivar el PIN o
  /// restablecer la app).
  Future<void> clearSecurity() async {
    for (final key in securityKeys) {
      await _backend.delete(key);
    }
  }

  Future<String?> readGeminiApiKey() => _backend.read(geminiApiKeyKey);

  Future<void> writeGeminiApiKey(String? key) => key == null
      ? _backend.delete(geminiApiKeyKey)
      : _backend.write(geminiApiKeyKey, key);

  Future<bool> readResetPending() async =>
      await _backend.read(resetPendingKey) == 'true';

  Future<void> writeResetPending(bool pending) => pending
      ? _backend.write(resetPendingKey, 'true')
      : _backend.delete(resetPendingKey);
}
