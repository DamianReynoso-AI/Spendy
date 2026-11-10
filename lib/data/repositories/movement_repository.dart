/// M-11 · Guardado, lectura, edición y borrado de movimientos
/// (RF-01, RF-02, RF-07 a RF-10, RF-53).
///
/// Los montos se guardan en centavos (INTEGER) y las fechas como
/// "AAAA-MM-DD" sin hora (TEC-09); de eso se encarga [Movement.toRow].
library;

import 'package:sqflite/sqflite.dart';

import '../models/movement.dart';

/// Acceso a la tabla `movimiento`. Las excepciones de SQLite se dejan
/// subir: el servicio (M-02) las traduce y las registra en la bitácora
/// (M-13), una sola vez por fallo.
class MovementRepository {
  MovementRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _db;
  final DateTime Function() _clock;

  /// Movimientos con el nombre de su categoría.
  static const String _selectSql = '''
SELECT m.*, c.nombre AS categoria_nombre
FROM movimiento m
JOIN categoria c ON c.id = m.categoria_id''';

  /// Orden de la lista: del más reciente al más antiguo; con la misma
  /// fecha, primero el creado más tarde (CA-014). El id es el último
  /// desempate para que el orden sea siempre el mismo.
  static const String _orderSql =
      'ORDER BY m.fecha DESC, m.creado_en DESC, m.id DESC';

  /// Lista completa (RF-07).
  static const String listSql = '$_selectSql\n$_orderSql';

  /// Movimientos de un mes calendario. Compara textos "AAAA-MM-DD", así que
  /// usa el índice `idx_movimiento_fecha` (RF-10, RNF-08).
  static const String monthSql =
      '$_selectSql\nWHERE m.fecha >= ? AND m.fecha <= ?\n$_orderSql';

  /// Un movimiento por id.
  static const String byIdSql = '$_selectSql\nWHERE m.id = ?';

  /// Inserta un movimiento ya validado y devuelve su id.
  Future<int> insert(Movement movement) =>
      _db.insert('movimiento', movement.toRow());

  /// Todos los movimientos en el orden de la lista (RF-07).
  Future<List<Movement>> fetchAll() async {
    final rows = await _db.rawQuery(listSql);
    return rows.map(Movement.fromRow).toList(growable: false);
  }

  /// El movimiento con ese id, o `null` si ya no existe.
  Future<Movement?> findById(int id) async {
    final rows = await _db.rawQuery(byIdSql, [id]);
    return rows.isEmpty ? null : Movement.fromRow(rows.first);
  }

  /// Actualiza todos los campos editables del movimiento [movement.id]
  /// (RF-08) y pone `actualizado_en` con la fecha y hora actual (ISO 8601).
  /// `creado_en` no cambia. Corre dentro de una transacción: si la
  /// escritura falla, SQLite hace rollback y el registro conserva su valor
  /// anterior (CA-018); la excepción sube al servicio, que la registra.
  /// Devuelve cuántos registros cambió (0 si el id ya no existe).
  Future<int> updateMovement(Movement movement) {
    final id = movement.id;
    if (id == null) {
      throw ArgumentError.notNull('movement.id');
    }
    final values = movement.toRow()
      ..remove('creado_en')
      ..['actualizado_en'] = _clock().toIso8601String();
    return _db.transaction(
      (txn) =>
          txn.update('movimiento', values, where: 'id = ?', whereArgs: [id]),
    );
  }

  /// Borra el movimiento [id]. El esquema v1 borra en cascada su recibo
  /// (P-03, RF-09). Si el id ya no existe (doble toque), no lanza error y
  /// devuelve 0 (CA-024).
  Future<int> deleteMovement(int id) =>
      _db.delete('movimiento', where: 'id = ?', whereArgs: [id]);

  /// Movimientos con fecha dentro del mes calendario [year]-[month]
  /// ("AAAA-MM-01" a "AAAA-MM-31"), en el orden de la lista (RF-10).
  Future<List<Movement>> getMovementsByMonth(int year, int month) async {
    final prefix = '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}';
    final rows = await _db.rawQuery(monthSql, ['$prefix-01', '$prefix-31']);
    return rows.map(Movement.fromRow).toList(growable: false);
  }
}
