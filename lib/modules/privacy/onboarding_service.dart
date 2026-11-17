/// M-10 · Aceptación del aviso de privacidad en el primer inicio (RF-51;
/// CA-141 a CA-143).
library;

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/repositories/settings_repository.dart';

/// Mensajes del primer inicio.
class OnboardingMessages {
  OnboardingMessages._();

  static const String saveFailed =
      'No se pudo guardar tu aceptación por un problema con el '
      'almacenamiento del teléfono. Toca "Acepto" de nuevo.';
}

/// Lee y guarda si la persona ya aceptó el aviso.
class OnboardingService {
  OnboardingService(this._settings, this._logger);

  static const String module = 'M-10';

  /// Clave exacta en la tabla `ajuste` (sección 13.4).
  static const String acceptedKey = 'aviso_privacidad_aceptado';
  static const String acceptedValue = 'true';

  final SettingsRepository _settings;
  final ErrorLogger _logger;

  /// `true` si ya se aceptó. Si la lectura falla devuelve `false`: ante la
  /// duda se vuelve a mostrar el aviso (CA-142).
  Future<bool> isAccepted() async {
    try {
      return await _settings.getSetting(acceptedKey) == acceptedValue;
    } on Object catch (e) {
      await _logger.log(type: ErrorType.storageRead, module: module, cause: e);
      return false;
    }
  }

  /// Guarda la aceptación con su fecha y hora (CA-143).
  Future<Result<void>> accept() async {
    try {
      await _settings.setSetting(acceptedKey, acceptedValue);
      return const Success(null);
    } on Object catch (e) {
      final error = translateStorageError(e, writing: true);
      await _logger.log(type: error.type, module: module, cause: e);
      return Failure(
        AppError(type: error.type, message: OnboardingMessages.saveFailed),
      );
    }
  }
}
