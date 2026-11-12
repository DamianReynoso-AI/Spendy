/// M-13 · Resultado tipado de cada operación (RNF-05).
///
/// Las capas de datos y de lógica no lanzan excepciones hacia la interfaz:
/// devuelven un [Result] que es [Success] con el valor o [Failure] con un
/// [AppError] que ya trae el mensaje para la persona usuaria.
library;

/// Tipo de error. Se guarda en la bitácora (nunca datos del usuario).
enum ErrorType {
  /// Uno o más campos no cumplen las reglas (RF-04, RF-05).
  validation('validacion'),

  /// El dispositivo no tiene espacio para guardar (CA-030).
  storageFull('almacenamiento_lleno'),

  /// Falló la escritura en la base o en un archivo (RF-11).
  storageWrite('almacenamiento_escritura'),

  /// Falló la lectura de la base (lista de movimientos o categorías).
  storageRead('almacenamiento_lectura'),

  /// La persona negó el permiso de cámara (RF-16). No es un fallo técnico
  /// y no se escribe en la bitácora.
  cameraPermission('permiso_camara'),

  /// La cámara falló, está ocupada o no existe (RF-17).
  camera('camara'),

  /// Falló la lectura del recibo con OCR: sin internet, error del
  /// servicio o tiempo agotado (RF-30).
  ocr('ocr'),

  /// Cualquier otro fallo no previsto.
  unexpected('inesperado');

  const ErrorType(this.code);

  /// Código corto en español que se escribe en `errores.log`.
  final String code;
}

/// Error listo para mostrarse: mensaje en español de México, sin códigos
/// ni trazas, con la causa y la acción siguiente (RNF-04, RNF-05).
class AppError {
  const AppError({
    required this.type,
    required this.message,
    this.fieldErrors = const {},
    this.missingFields = const [],
  });

  final ErrorType type;

  /// Mensaje general para la persona usuaria.
  final String message;

  /// Errores por campo, para resaltar cada uno junto al campo (RF-05).
  final Map<String, String> fieldErrors;

  /// Campos obligatorios que quedaron vacíos (RF-05). Es un subconjunto
  /// de las llaves de [fieldErrors].
  final List<String> missingFields;

  /// Campos con error, en el orden en que se detectaron.
  List<String> get fields => fieldErrors.keys.toList(growable: false);
}

/// Resultado de una operación: éxito con valor o fallo con error.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;

  /// Valor si es éxito; `null` si es fallo.
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  /// Error si es fallo; `null` si es éxito.
  AppError? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final error) => error,
      };
}

/// Operación exitosa.
final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

/// Operación fallida con un error tipado.
final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final AppError error;
}
