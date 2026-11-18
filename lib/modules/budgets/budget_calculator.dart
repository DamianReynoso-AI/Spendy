/// M-14 · Avance de los presupuestos mensuales por categoría.
///
/// Lógica pura: no usa Flutter ni la base.
library;

import '../../config/categories.dart';
import '../../data/models/movement.dart';

/// Qué tan cerca está una categoría de su límite.
enum BudgetStatus {
  /// Menos del [BudgetCalculator.warningRatio] del límite.
  ok,

  /// Desde el 80 % hasta el 100 % del límite.
  warning,

  /// Más del límite.
  exceeded,
}

/// Una categoría con presupuesto y lo que lleva gastado en el mes.
class BudgetLine {
  const BudgetLine({
    required this.categoryId,
    required this.categoryName,
    required this.limitCents,
    required this.spentCents,
  });

  final int categoryId;
  final String categoryName;
  final int limitCents;
  final int spentCents;

  /// Gastado entre límite (puede pasar de 1).
  double get ratio => limitCents == 0 ? 0 : spentCents / limitCents;

  /// Lo que queda; negativo si ya se pasó.
  int get remainingCents => limitCents - spentCents;

  BudgetStatus get status => spentCents > limitCents
      ? BudgetStatus.exceeded
      : ratio >= BudgetCalculator.warningRatio
          ? BudgetStatus.warning
          : BudgetStatus.ok;
}

/// Calcula el avance de cada presupuesto con los egresos del mes.
class BudgetCalculator {
  const BudgetCalculator();

  /// A partir de este avance se avisa que el presupuesto se está acabando.
  static const double warningRatio = 0.8;

  /// [limits] es id de categoría -> centavos; [names] da el nombre de cada
  /// categoría en su orden fijo. Solo cuenta egresos de [movements].
  List<BudgetLine> calculate({
    required Map<int, int> limits,
    required Map<int, String> names,
    required Iterable<Movement> movements,
  }) {
    final spent = <int, int>{};
    for (final m in movements) {
      if (m.type != MovementType.egreso) continue;
      spent[m.categoryId] = (spent[m.categoryId] ?? 0) + m.amountCents;
    }
    return [
      for (final entry in names.entries)
        if (limits[entry.key] case final limit?)
          BudgetLine(
            categoryId: entry.key,
            categoryName: entry.value,
            limitCents: limit,
            spentCents: spent[entry.key] ?? 0,
          ),
    ];
  }
}
