/// M-05 · Clave de la API de Gemini capturada en Ajustes (TEC-01, RNF-18).
///
/// La clave vive solo en el almacenamiento seguro del teléfono (Keystore
/// en Android). Así el APK no trae ningún secreto y cada persona usa su
/// propia clave gratuita de Google AI Studio.
library;

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/secure_store.dart';

/// Mensajes de la clave (RNF-05).
class OcrKeyMessages {
  OcrKeyMessages._();

  static const String invalid =
      'Esa clave no parece válida. Cópiala completa desde Google AI Studio '
      '(aistudio.google.com, "Get API key") y pégala aquí.';
  static const String saveFailed =
      'No se pudo guardar la clave en el almacenamiento seguro del teléfono. '
      'Inténtalo de nuevo.';
}

/// Estado de la clave para mostrarlo sin revelarla.
class OcrKeyStatus {
  const OcrKeyStatus(this.lastChars);

  /// Últimos 4 caracteres, o `null` si no hay clave.
  final String? lastChars;

  bool get configured => lastChars != null;
}

/// Guarda, lee y borra la clave.
class OcrKeyService {
  OcrKeyService(this._store, this._logger);

  static const String module = 'M-05';

  /// Las claves de Google son de un solo bloque, sin espacios, de unas 39
  /// letras, números, `-` o `_`.
  static final RegExp _shape = RegExp(r'^[A-Za-z0-9_\-.]{20,200}$');

  final SecureStore _store;
  final ErrorLogger _logger;

  /// Clave guardada o `null`. Si la lectura falla devuelve `null` y la app
  /// lee los recibos en el teléfono.
  Future<String?> read() async {
    try {
      final key = (await _store.readGeminiApiKey())?.trim();
      return (key == null || key.isEmpty) ? null : key;
    } on Object catch (e) {
      await _logger.log(type: ErrorType.storageRead, module: module, cause: e);
      return null;
    }
  }

  Future<OcrKeyStatus> status() async {
    final key = await read();
    return OcrKeyStatus(key?.substring(key.length - 4));
  }

  /// `true` si [text] tiene forma de clave de Google.
  static bool looksValid(String text) => _shape.hasMatch(text.trim());

  Future<Result<void>> save(String text) async {
    final key = text.trim();
    if (!looksValid(key)) {
      return const Failure(
        AppError(type: ErrorType.validation, message: OcrKeyMessages.invalid),
      );
    }
    return _write(key);
  }

  Future<Result<void>> remove() => _write(null);

  Future<Result<void>> _write(String? key) async {
    try {
      await _store.writeGeminiApiKey(key);
      return const Success(null);
    } on Object catch (e) {
      await _logger.log(type: ErrorType.storageWrite, module: module, cause: e);
      return const Failure(
        AppError(
            type: ErrorType.storageWrite, message: OcrKeyMessages.saveFailed),
      );
    }
  }
}
