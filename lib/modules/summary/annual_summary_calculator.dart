/// M-07 · Cálculo del resumen anual (RF-36 a RF-40; RNF-10, RNF-33;
/// CA-095 a CA-106).
///
/// Lógica pura: no importa Flutter ni widgets (RNF-33). Todo se suma en
/// centavos enteros para no tener errores de redondeo.
library;

import '../../config/categories.dart';
import '../../core/formatters.dart';
import '../../data/models/movement.dart';

/// Total de egresos de una categoría.
class CategoryTotal {
  const CategoryTotal(this.name, this.cents);

  final String name;
  final int cents;

  /// Por ejemplo, "$1,234.56"; las categorías sin gastos salen "$0.00"
  /// (CA-106).
  String get formatted => formatCents(cents);
}

/// Resumen de un año, listo para mostrarse o exportarse (M-08 no
/// recalcula nada, RNF-33).
class AnnualSummary {
  const AnnualSummary({
    required this.year,
    required this.incomeCents,
    required this.expenseCents,
    required this.byCategory,
    required this.movementCount,
  });

  final int year;
  final int incomeCents;
  final int expenseCents;

  /// Las 6 categorías de egreso, en su orden fijo, aunque sumen 0.
  final List<CategoryTotal> byCategory;
  final int movementCount;

  /// Ingresos menos egresos (RF-37, CA-099).
  int get differenceCents => incomeCents - expenseCents;

  /// `false` si el año no tiene movimientos: se muestra un aviso en lugar
  /// de un resumen vacío (RF-40, CA-096, CA-098).
  bool get hasMovements => movementCount > 0;

  String get formattedIncome => formatCents(incomeCents);
  String get formattedExpense => formatCents(expenseCents);
  String get formattedDifference => formatCents(differenceCents);
}

/// Años para el selector y el seleccionado por defecto (RF-36).
class YearOptions {
  const YearOptions({required this.years, required this.selected});

  /// Años con movimientos más el actual, de mayor a menor.
  final List<int> years;

  /// El año calendario actual (CA-095, CA-097).
  final int selected;
}

/// Calculadora del resumen anual.
class AnnualSummaryCalculator {
  const AnnualSummaryCalculator();

  /// Une los años con movimientos con el año actual de [now], sin
  /// repetir y de mayor a menor (CA-095, CA-097).
  YearOptions yearOptions(Iterable<int> yearsWithMovements, DateTime now) {
    final current = now.year;
    final years = {...yearsWithMovements, current}.toList()
      ..sort((a, b) => b.compareTo(a));
    return YearOptions(years: years, selected: current);
  }

  /// Suma ingresos, egresos y egresos por categoría de [year]. Ignora los
  /// movimientos de otros años aunque vengan en la lista. La suma por
  /// categoría siempre es igual al total de egresos (RF-39, CA-100,
  /// CA-104, CA-105): un egreso con una categoría que no es de egreso se
  /// cuenta en "Otros".
  AnnualSummary calculate(int year, Iterable<Movement> movements) {
    final byCategory = {
      for (final name in Categories.expenseCategories) name: 0,
    };
    var income = 0;
    var expense = 0;
    var count = 0;
    for (final movement in movements) {
      if (movement.date.year != year) continue;
      count++;
      if (movement.type == MovementType.ingreso) {
        income += movement.amountCents;
        continue;
      }
      expense += movement.amountCents;
      final name = byCategory.containsKey(movement.categoryName)
          ? movement.categoryName!
          : Categories.expenseCategories.last;
      byCategory[name] = byCategory[name]! + movement.amountCents;
    }
    return AnnualSummary(
      year: year,
      incomeCents: income,
      expenseCents: expense,
      movementCount: count,
      byCategory: [
        for (final entry in byCategory.entries)
          CategoryTotal(entry.key, entry.value),
      ],
    );
  }
}
