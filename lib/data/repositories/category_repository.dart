/// M-11 · Lectura del catálogo de categorías (RF-12, RF-13, RF-14).
///
/// Solo lectura: el usuario no crea ni edita categorías (sección 4).
library;

import 'package:sqflite/sqflite.dart';

import '../../config/categories.dart';

/// Una fila de la tabla `categoria`.
class CategoryRecord {
  const CategoryRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.order,
  });

  final int id;
  final String name;
  final MovementType type;
  final int order;

  factory CategoryRecord.fromRow(Map<String, Object?> row) => CategoryRecord(
        id: row['id'] as int,
        name: row['nombre'] as String,
        type: MovementType.values.byName(row['tipo'] as String),
        order: row['orden'] as int,
      );
}

/// Acceso de solo lectura a la tabla `categoria`.
class CategoryRepository {
  CategoryRepository(this._db);

  final DatabaseExecutor _db;

  /// Todas las categorías, agrupadas por tipo y en su orden fijo.
  Future<List<CategoryRecord>> fetchAll() async {
    final rows = await _db.query('categoria', orderBy: 'tipo, orden');
    return rows.map(CategoryRecord.fromRow).toList(growable: false);
  }

  /// Solo las categorías de un tipo, en su orden fijo (RF-14).
  Future<List<CategoryRecord>> fetchByType(MovementType type) async {
    final rows = await _db.query(
      'categoria',
      where: 'tipo = ?',
      whereArgs: [type.value],
      orderBy: 'orden',
    );
    return rows.map(CategoryRecord.fromRow).toList(growable: false);
  }
}
