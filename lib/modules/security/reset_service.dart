/// M-09 / M-11 · Restablecimiento total de la app cuando se olvidó el PIN
/// (RF-50; CA-137 a CA-140).
///
/// Borra movimientos, recibos y ajustes de SQLite, todas las imágenes de
/// `recibos/` y `temp_recibos/`, y las claves del almacén seguro. Para que
/// nunca quede a medias (CA-139) usa una bandera en el almacén seguro:
/// 1. Se escribe `reset_pending`. Antes de esto no se ha borrado nada:
///    si la app se cierra, conserva todos sus datos.
/// 2. Se borra la base (una transacción), las imágenes y las claves.
///    Cada paso se puede repetir.
/// 3. Se quita la bandera.
/// Si la app se cierra entre 1 y 3, al reabrir [completePendingReset]
/// termina el borrado antes de mostrar nada.
library;

import 'package:sqflite/sqflite.dart';

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/database.dart';
import '../../data/image_store.dart';
import '../../data/secure_store.dart';

/// Mensajes del restablecimiento.
class ResetMessages {
  ResetMessages._();

  static const String failed =
      'No se pudo terminar de borrar los datos. Cierra y vuelve a abrir la '
      'app: el borrado se completará al iniciar.';
}

/// Orquesta el borrado total.
class ResetService {
  ResetService({
    required Database db,
    required ImageStore images,
    required SecureStore store,
    required ErrorLogger logger,
  })  : _db = db,
        _images = images,
        _store = store,
        _logger = logger;

  static const String module = 'M-09';

  final Database _db;
  final ImageStore _images;
  final SecureStore _store;
  final ErrorLogger _logger;

  /// Restablece la app como recién instalada (CA-137). La pantalla solo
  /// llama aquí después de las dos confirmaciones (CA-138).
  Future<Result<void>> resetAll() async {
    try {
      await _store.writeResetPending(true);
      await _wipe();
      return const Success(null);
    } on Object catch (e) {
      await _logger.log(type: ErrorType.storageWrite, module: module, cause: e);
      return const Failure(
        AppError(type: ErrorType.storageWrite, message: ResetMessages.failed),
      );
    }
  }

  /// Al iniciar la app: si un restablecimiento quedó interrumpido, lo
  /// termina (CA-139). Devuelve `true` si había uno pendiente.
  Future<bool> completePendingReset() async {
    if (!await _store.readResetPending()) return false;
    await _wipe();
    return true;
  }

  Future<void> _wipe() async {
    await wipeUserData(_db);
    await _images.deleteAllImages();
    await _store.clearSecurity();
    await _store.writeGeminiApiKey(null);
    await _store.writeResetPending(false);
  }
}
