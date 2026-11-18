/// M-11 · Lectura y escritura de la tabla `presupuesto` (migración v2).
library;

import 'package:sqflite/sqflite.dart';

/// Límite mensual de gasto por categoría de egreso, en centavos.
class BudgetRepository {
  BudgetRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DatabaseExecutor _db;
  final DateTime Function() _clock;

  /// Límites guardados: id de categoría -> centavos.
  Future<Map<int, int>> fetchAll() async {
    final rows = await _db.query('presupuesto');
    return {
      for (final row in rows)
        row['categoria_id'] as int: row['monto_centavos'] as int,
    };
  }

  /// Guarda el límite de [categoryId]; con `null` lo quita.
  Future<void> setLimit(int categoryId, int? cents) async {
    if (cents == null) {
      await _db.delete(
        'presupuesto',
        where: 'categoria_id = ?',
        whereArgs: [categoryId],
      );
      return;
    }
    await _db.insert(
      'presupuesto',
      {
        'categoria_id': categoryId,
        'monto_centavos': cents,
        'actualizado_en': _clock().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
