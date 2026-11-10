/// M-11 · Migración v1: esquema inicial y catálogo de categorías
/// (sección 13.3 y 13.4; RF-12, RF-13; RNF-09, RNF-27).
library;

import 'package:sqflite/sqflite.dart';

import '../../config/categories.dart';

/// Crea las 4 tablas del diccionario de datos, los índices y carga las
/// categorías fijas desde `lib/config/categories.dart`.
class V1Initial {
  V1Initial._();

  /// Versión del esquema que deja esta migración.
  static const int version = 1;

  static const String createCategoria = '''
CREATE TABLE categoria (
  id INTEGER PRIMARY KEY,
  nombre TEXT NOT NULL,
  tipo TEXT NOT NULL,
  orden INTEGER NOT NULL
)''';

  static const String createMovimiento = '''
CREATE TABLE movimiento (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tipo TEXT NOT NULL,
  monto_centavos INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  categoria_id INTEGER NOT NULL REFERENCES categoria(id),
  metodo_pago TEXT,
  descripcion TEXT,
  nota TEXT,
  creado_en TEXT NOT NULL,
  actualizado_en TEXT NOT NULL
)''';

  static const String createRecibo = '''
CREATE TABLE recibo (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  movimiento_id INTEGER NOT NULL UNIQUE
    REFERENCES movimiento(id) ON DELETE CASCADE,
  ruta_archivo TEXT NOT NULL,
  tamano_bytes INTEGER NOT NULL,
  capturado_en TEXT NOT NULL
)''';

  static const String createAjuste = '''
CREATE TABLE ajuste (
  clave TEXT PRIMARY KEY,
  valor TEXT NOT NULL,
  actualizado_en TEXT NOT NULL
)''';

  /// Índices para cumplir los tiempos de RNF-09.
  static const List<String> createIndexes = [
    'CREATE INDEX idx_movimiento_fecha ON movimiento(fecha)',
    'CREATE INDEX idx_movimiento_categoria ON movimiento(categoria_id)',
    'CREATE INDEX idx_movimiento_tipo_fecha ON movimiento(tipo, fecha)',
  ];

  /// Ejecuta la migración completa dentro de una transacción: si algo
  /// falla, la base queda vacía y no a medias.
  static Future<void> apply(Database db, int version) async {
    await db.transaction((txn) async {
      for (final sql in [
        createCategoria,
        createMovimiento,
        createRecibo,
        createAjuste,
        ...createIndexes,
      ]) {
        await txn.execute(sql);
      }
      await _seedCategories(txn);
    });
  }

  /// Inserta las categorías fijas. Los ids son estables: primero las de
  /// egreso (1 a 6) y luego las de ingreso (7 y 8).
  static Future<void> _seedCategories(Transaction txn) async {
    var id = 1;
    for (final type in [MovementType.egreso, MovementType.ingreso]) {
      final names = Categories.forType(type);
      for (var i = 0; i < names.length; i++) {
        await txn.insert('categoria', {
          'id': id++,
          'nombre': names[i],
          'tipo': type.value,
          'orden': i + 1,
        });
      }
    }
  }
}
