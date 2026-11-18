/// M-15 · Indicadores del mes: comparación del gasto contra el mismo
/// avance del mes pasado, categoría con más gasto y proyección al cierre.
///
/// Lógica pura: no usa Flutter ni la base.
library;

import '../../config/categories.dart';
import '../../data/models/movement.dart';

/// Indicadores del mes en curso hasta [day].
class MonthInsights {
  const MonthInsights({
    required this.day,
    required this.daysInMonth,
    required this.expenseCents,
    required this.previousExpenseCents,
    this.topCategoryName,
    this.topCategoryCents = 0,
  });

  /// Día de hoy (1 a 31).
  final int day;
  final int daysInMonth;

  /// Egresos del mes en curso hasta hoy.
  final int expenseCents;

  /// Egresos del mes pasado del día 1 al mismo [day] (o a su último día si
  /// el mes pasado fue más corto). Comparar contra el mes completo sería
  /// injusto a mitad de mes.
  final int previousExpenseCents;

  /// Categoría de egreso con más gasto este mes; `null` si no hay egresos.
  final String? topCategoryName;
  final int topCategoryCents;

  bool get hasExpenses => expenseCents > 0;

  /// Cambio en porcentaje contra el mes pasado, redondeado. `null` si el
  /// mes pasado no hubo gasto en ese periodo (no hay contra qué comparar).
  int? get changePercent => previousExpenseCents == 0
      ? null
      : (((expenseCents - previousExpenseCents) * 100) / previousExpenseCents)
          .round();

  /// Gasto diario promedio en lo que va del mes.
  int get dailyAverageCents => day == 0 ? 0 : expenseCents ~/ day;

  /// Gasto estimado al cierre si se sigue al mismo ritmo.
  int get projectedCents => dailyAverageCents * daysInMonth;
}

/// Calcula [MonthInsights].
class InsightsCalculator {
  const InsightsCalculator();

  static int daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  /// [current] son los movimientos del mes de [today]; [previous], los del
  /// mes anterior.
  MonthInsights calculate({
    required DateTime today,
    required Iterable<Movement> current,
    required Iterable<Movement> previous,
  }) {
    final day = today.day;
    final byCategory = <String, int>{};
    for (final m in _expensesUpTo(current, day)) {
      final name = m.categoryName ?? '';
      byCategory[name] = (byCategory[name] ?? 0) + m.amountCents;
    }
    final top = _top(byCategory);
    return MonthInsights(
      day: day,
      daysInMonth: daysIn(today.year, today.month),
      expenseCents: byCategory.values.fold(0, (a, b) => a + b),
      previousExpenseCents:
          _expensesUpTo(previous, day).fold(0, (sum, m) => sum + m.amountCents),
      topCategoryName: top?.key,
      topCategoryCents: top?.value ?? 0,
    );
  }

  /// Egresos con fecha del día 1 al [day] del mes.
  static Iterable<Movement> _expensesUpTo(Iterable<Movement> all, int day) =>
      all.where((m) => m.type == MovementType.egreso && m.date.day <= day);

  /// Categoría con más gasto, o `null` si no hay.
  static MapEntry<String, int>? _top(Map<String, int> byCategory) {
    MapEntry<String, int>? top;
    for (final entry in byCategory.entries) {
      if (top == null || entry.value > top.value) top = entry;
    }
    return top;
  }
}
