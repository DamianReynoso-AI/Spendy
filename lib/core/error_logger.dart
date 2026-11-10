/// M-13 · Bitácora local de errores y traducción de fallos técnicos
/// (RNF-04, RNF-05, RNF-20, RNF-28).
///
/// La bitácora vive en el archivo privado `errores.log` y solo guarda
/// tipo, módulo, causa técnica (el nombre de la clase de la excepción) y
/// fecha y hora. Nunca guarda el texto de la excepción, porque puede traer
/// montos, comercios o notas (por ejemplo, los argumentos de un INSERT).
library;

import 'dart:io';

import 'result.dart';

/// Nombre del archivo de la bitácora dentro del almacenamiento privado.
const String errorLogFileName = 'errores.log';

/// Mensajes de error para la persona usuaria: causa y acción siguiente,
/// en español de México y sin códigos ni trazas (RNF-04, RNF-05).
class ErrorMessages {
  ErrorMessages._();

  static const String saveFailed =
      'No se pudo guardar el movimiento por un problema con el '
      'almacenamiento del teléfono. Tus datos siguen en el formulario; '
      'toca "Reintentar".';
  static const String storageFull =
      'No se pudo guardar porque el teléfono no tiene espacio libre. '
      'Libera espacio (por ejemplo, borra fotos o apps que no uses) y toca '
      '"Reintentar". Tus datos siguen en el formulario.';
  static const String loadFailed =
      'No se pudieron cargar tus datos. Cierra y vuelve a abrir la app; '
      'si sigue pasando, reinicia el teléfono.';
  static const String unexpected =
      'Algo salió mal. Tus datos siguen en el formulario; toca '
      '"Reintentar".';
  static const String missingFields =
      'Faltan datos obligatorios. Completa los campos marcados y toca '
      '"Guardar".';
  static const String invalidFields =
      'Revisa los campos marcados y toca "Guardar" de nuevo.';
}

/// Convierte una excepción de almacenamiento en un [AppError] con mensaje
/// para la persona usuaria. [writing] indica si fallaba una escritura.
AppError translateStorageError(Object error, {required bool writing}) {
  if (isDiskFullError(error)) {
    return const AppError(
      type: ErrorType.storageFull,
      message: ErrorMessages.storageFull,
    );
  }
  return writing
      ? const AppError(
          type: ErrorType.storageWrite,
          message: ErrorMessages.saveFailed,
        )
      : const AppError(
          type: ErrorType.storageRead,
          message: ErrorMessages.loadFailed,
        );
}

/// Detecta "sin espacio": ENOSPC (28) en archivos o SQLITE_FULL en la base.
/// El texto de la excepción solo se revisa aquí; nunca se guarda.
bool isDiskFullError(Object error) {
  if (error is FileSystemException && error.osError?.errorCode == 28) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('sqlite_full') ||
      text.contains('disk is full') ||
      text.contains('no space left');
}

/// Escribe errores en `errores.log` sin datos del usuario (RNF-20).
class ErrorLogger {
  /// [logFile] devuelve el archivo de la bitácora (en la app, dentro del
  /// almacenamiento privado; en pruebas, una carpeta temporal).
  ErrorLogger(this._logFile, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Future<File> Function() _logFile;
  final DateTime Function() _clock;

  static final RegExp _unsafeChars = RegExp(r'[^A-Za-z0-9_\-]');

  /// Arma una línea: `timestamp | tipo | módulo | causa`.
  /// La causa es solo el tipo de la excepción (por ejemplo,
  /// `DatabaseException`), nunca su mensaje.
  String formatEntry({
    required ErrorType type,
    required String module,
    required Object cause,
  }) {
    final timestamp = _clock().toUtc().toIso8601String();
    final safeModule = module.replaceAll(_unsafeChars, '');
    final safeCause = cause.runtimeType.toString().replaceAll(_unsafeChars, '');
    return '$timestamp | ${type.code} | $safeModule | $safeCause';
  }

  /// Agrega una línea a la bitácora. Si no se puede escribir, se ignora:
  /// registrar un error nunca debe romper la app.
  Future<void> log({
    required ErrorType type,
    required String module,
    required Object cause,
  }) async {
    final line = formatEntry(type: type, module: module, cause: cause);
    try {
      final file = await _logFile();
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } on Object {
      // Sin bitácora no hay a dónde reportar; la app sigue funcionando.
    }
  }
}
