/// M-11 · Migración v3: reglas de integridad en la base (AUD-19).
///
/// SQLite no deja agregar CHECK a una tabla que ya existe sin rehacerla,
/// así que las reglas van como disparadores: rechazan con ABORT cualquier
/// movimiento o recibo inválido, venga de un error de código o de una
/// restauración. No cambian ningún dato existente.
library;

import 'package:sqflite/sqflite.dart';

import '../../config/app_config.dart';

class V3Integrity {
  V3Integrity._();

  /// Versión del esquema que deja esta migración.
  static const int version = 3;

  /// Condición que debe cumplir cada movimiento (mismas reglas que
  /// core/validators.dart y AppConfig).
  static const String _movementRule = '''
NEW.tipo NOT IN ('ingreso', 'egreso')
OR NEW.monto_centavos IS NULL
OR NEW.monto_centavos <= 0
OR NEW.monto_centavos > ${AppConfig.maxAmountCents}
OR NEW.fecha NOT GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'
OR length(NEW.descripcion) > ${AppConfig.maxDescriptionLength}
OR length(NEW.nota) > ${AppConfig.maxNoteLength}''';

  static List<String> get statements => [
        for (final event in ['INSERT', 'UPDATE'])
          '''
CREATE TRIGGER IF NOT EXISTS movimiento_valido_${event.toLowerCase()}
BEFORE $event ON movimiento
WHEN $_movementRule
BEGIN
  SELECT RAISE(ABORT, 'movimiento inválido');
END''',
        for (final event in ['INSERT', 'UPDATE'])
          '''
CREATE TRIGGER IF NOT EXISTS recibo_valido_${event.toLowerCase()}
BEFORE $event ON recibo
WHEN NEW.tamano_bytes < 0
  OR NEW.tamano_bytes > ${AppConfig.maxReceiptBytes}
  OR NEW.ruta_archivo LIKE '%..%'
  OR substr(NEW.ruta_archivo, 1, 1) = '/'
BEGIN
  SELECT RAISE(ABORT, 'recibo inválido');
END''',
      ];

  static Future<void> apply(DatabaseExecutor db) async {
    for (final sql in statements) {
      await db.execute(sql);
    }
  }
}
