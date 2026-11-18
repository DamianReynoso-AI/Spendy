/// M-11 · Migración v2: tabla `presupuesto` con el límite mensual de gasto
/// por categoría de egreso.
library;

import 'package:sqflite/sqflite.dart';

/// Agrega los presupuestos. No toca ninguna tabla existente, así que quien
/// actualiza desde la v1 conserva todos sus datos.
class V2Budgets {
  V2Budgets._();

  /// Versión del esquema que deja esta migración.
  static const int version = 2;

  /// Un renglón por categoría con presupuesto. Si se borra la categoría
  /// (no pasa: es catálogo fijo) se borra su presupuesto.
  static const String createPresupuesto = '''
CREATE TABLE presupuesto (
  categoria_id INTEGER PRIMARY KEY
    REFERENCES categoria(id) ON DELETE CASCADE,
  monto_centavos INTEGER NOT NULL CHECK (monto_centavos > 0),
  actualizado_en TEXT NOT NULL
)''';

  static Future<void> apply(DatabaseExecutor db) =>
      db.execute(createPresupuesto);
}
