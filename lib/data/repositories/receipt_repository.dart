/// M-11 · Lectura, reemplazo y baja de recibos (RF-19, RF-20; RNF-21;
/// CA-053 a CA-055).
///
/// Cada cambio corre en una transacción de SQLite y mueve o borra el
/// archivo físico solo cuando la base ya confirmó, para que nunca quede un
/// registro sin imagen ni una imagen sin registro.
library;

import 'package:sqflite/sqflite.dart';

import '../image_store.dart';
import '../models/receipt.dart';

/// Acceso a la tabla `recibo` y a sus archivos.
class ReceiptRepository {
  ReceiptRepository(this._db, this._store);

  final Database _db;
  final ImageStore _store;

  /// El recibo del movimiento [movementId], o `null` si no tiene.
  Future<Receipt?> findByMovement(int movementId) async {
    final rows = await _db.query(
      'recibo',
      where: 'movimiento_id = ?',
      whereArgs: [movementId],
    );
    return rows.isEmpty ? null : Receipt.fromRow(rows.first);
  }

  /// Rutas relativas registradas, para limpiar huérfanos al iniciar.
  Future<Set<String>> allPaths() async {
    final rows = await _db.query('recibo', columns: ['ruta_archivo']);
    return {for (final row in rows) row['ruta_archivo'] as String};
  }

  /// Vincula [pending] al movimiento [movementId]: si ya tenía recibo lo
  /// reemplaza (RF-20). Pasos: (1) en una transacción borra la fila
  /// anterior, inserta la nueva y mueve la imagen a `recibos/`; (2) si
  /// todo se confirmó, borra el archivo anterior (CA-055). Si algo falla,
  /// la base vuelve a su estado anterior, el recibo anterior sigue intacto
  /// y se borra la imagen nueva.
  Future<void> attach(int movementId, PendingReceipt pending) async {
    final finalPath = _store.finalPathFor(pending.file);
    String? oldPath;
    try {
      await _db.transaction((txn) async {
        oldPath = await _pathOf(txn, movementId);
        await txn.delete(
          'recibo',
          where: 'movimiento_id = ?',
          whereArgs: [movementId],
        );
        await txn.insert('recibo', _row(movementId, finalPath, pending));
        await _store.promote(pending.file);
      });
    } on Object {
      await _store.deleteQuietly(pending.file);
      await _store.deleteRelative(finalPath);
      rethrow;
    }
    final previous = oldPath;
    if (previous != null && previous != finalPath) {
      await _store.deleteRelative(previous);
    }
  }

  /// Quita el recibo del movimiento [movementId] y borra su archivo
  /// (RF-20). Devuelve `false` si no tenía recibo.
  Future<bool> remove(int movementId) async {
    String? path;
    await _db.transaction((txn) async {
      path = await _pathOf(txn, movementId);
      await txn.delete(
        'recibo',
        where: 'movimiento_id = ?',
        whereArgs: [movementId],
      );
    });
    final removed = path;
    if (removed == null) return false;
    await _store.deleteRelative(removed);
    return true;
  }

  static Future<String?> _pathOf(DatabaseExecutor db, int movementId) async {
    final rows = await db.query(
      'recibo',
      columns: ['ruta_archivo'],
      where: 'movimiento_id = ?',
      whereArgs: [movementId],
    );
    return rows.isEmpty ? null : rows.first['ruta_archivo'] as String;
  }

  static Map<String, Object?> _row(
    int movementId,
    String path,
    PendingReceipt pending,
  ) =>
      Receipt(
        movementId: movementId,
        filePath: path,
        sizeBytes: pending.sizeBytes,
        capturedAt: pending.capturedAt,
      ).toRow();

  /// Lo usa [MovementRepository] para insertar la fila del recibo dentro
  /// de su propia transacción (guardado atómico egreso + recibo).
  static Future<void> insertInTransaction(
    Transaction txn, {
    required int movementId,
    required String finalPath,
    required PendingReceipt pending,
  }) =>
      txn.insert('recibo', _row(movementId, finalPath, pending));

  /// Ruta del recibo de [movementId] dentro de una transacción ajena.
  static Future<String?> pathInTransaction(
    DatabaseExecutor db,
    int movementId,
  ) =>
      _pathOf(db, movementId);
}
