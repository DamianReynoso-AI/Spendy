/// M-11 · Modelo de un movimiento tal como se guarda en la tabla
/// `movimiento` (sección 13.4; TEC-09).
library;

import '../../config/categories.dart';

/// Convierte una fecha a "AAAA-MM-DD", sin hora (TEC-09).
String toIsoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Convierte "AAAA-MM-DD" a una fecha local sin hora.
DateTime fromIsoDate(String isoDate) {
  final parts = isoDate.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

/// Un registro de la tabla `movimiento`. El monto siempre va en centavos.
class Movement {
  const Movement({
    this.id,
    required this.type,
    required this.amountCents,
    required this.date,
    required this.categoryId,
    this.paymentMethod,
    this.description,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.categoryName,
  });

  /// `null` hasta que la base asigna el id.
  final int? id;
  final MovementType type;
  final int amountCents;

  /// Solo importa el día; la hora se descarta al guardar.
  final DateTime date;
  final int categoryId;
  final String? paymentMethod;
  final String? description;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Nombre de la categoría; solo viene lleno al listar (JOIN).
  final String? categoryName;

  /// Columnas para insertar en `movimiento` (sin id ni nombre de categoría).
  Map<String, Object?> toRow() => {
        'tipo': type.value,
        'monto_centavos': amountCents,
        'fecha': toIsoDate(date),
        'categoria_id': categoryId,
        'metodo_pago': paymentMethod,
        'descripcion': description,
        'nota': note,
        'creado_en': createdAt.toIso8601String(),
        'actualizado_en': updatedAt.toIso8601String(),
      };

  /// Crea el modelo a partir de una fila (con `categoria_nombre` opcional).
  factory Movement.fromRow(Map<String, Object?> row) => Movement(
        id: row['id'] as int?,
        type: MovementType.values.byName(row['tipo'] as String),
        amountCents: row['monto_centavos'] as int,
        date: fromIsoDate(row['fecha'] as String),
        categoryId: row['categoria_id'] as int,
        paymentMethod: row['metodo_pago'] as String?,
        description: row['descripcion'] as String?,
        note: row['nota'] as String?,
        createdAt: DateTime.parse(row['creado_en'] as String),
        updatedAt: DateTime.parse(row['actualizado_en'] as String),
        categoryName: row['categoria_nombre'] as String?,
      );
}
