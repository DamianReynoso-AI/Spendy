/// M-12 · Catálogo maestro de categorías fijas (RF-12, RF-13, RF-14).
library;

/// Tipo de movimiento. `value` es el texto que se guardará en la base (M-11).
enum MovementType {
  ingreso('ingreso'),
  egreso('egreso');

  const MovementType(this.value);
  final String value;
}

/// Listas fijas y ordenadas. Son `const`: no se pueden modificar en
/// tiempo de ejecución (el usuario no edita categorías).
class Categories {
  Categories._();

  /// Categorías de egreso (RF-12).
  static const List<String> expenseCategories = [
    'Alimentos',
    'Transporte',
    'Vivienda',
    'Servicios',
    'Entretenimiento',
    'Otros',
  ];

  /// Categorías de ingreso (RF-13).
  static const List<String> incomeCategories = [
    'Sueldos y salarios',
    'Otros ingresos',
  ];

  /// Devuelve solo las categorías del tipo pedido (RF-14).
  static List<String> forType(MovementType type) =>
      type == MovementType.egreso ? expenseCategories : incomeCategories;
}
