/// M-11 · Guardado y lectura de movimientos (RF-01, RF-02, RF-07, RF-53).
///
/// Los montos se guardan en centavos (INTEGER) y las fechas como
/// "AAAA-MM-DD" sin hora (TEC-09); de eso se encarga [Movement.toRow].
library;

import 'package:sqflite/sqflite.dart';

import '../models/movement.dart';

/// Acceso a la tabla `movimiento`. Las excepciones de SQLite se dejan
/// subir: el servicio (M-02) las traduce y las registra (M-13).
class MovementRepository {
  MovementRepository(this._db);

  final DatabaseExecutor _db;

  /// Lista con el nombre de la categoría. Del más reciente al más antiguo;
  /// con la misma fecha, primero el creado más tarde (CA-014). El id es el
  /// último desempate para que el orden sea siempre el mismo.
  static const String listSql = '''
SELECT m.*, c.nombre AS categoria_nombre
FROM movimiento m
JOIN categoria c ON c.id = m.categoria_id
ORDER BY m.fecha DESC, m.creado_en DESC, m.id DESC''';

  /// Inserta un movimiento ya validado y devuelve su id.
  Future<int> insert(Movement movement) =>
      _db.insert('movimiento', movement.toRow());

  /// Todos los movimientos en el orden de la lista (RF-07).
  Future<List<Movement>> fetchAll() async {
    final rows = await _db.rawQuery(listSql);
    return rows.map(Movement.fromRow).toList(growable: false);
  }
}
