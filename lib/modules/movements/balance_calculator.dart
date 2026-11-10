/// M-02 · Balance del mes en curso (RF-10; CA-025 a CA-028).
///
/// "Mes en curso" es el mes y año calendario de la fecha actual en la zona
/// horaria local del dispositivo (AMB-03 / R-03). Todo se calcula en
/// centavos enteros para no tener errores de redondeo.
library;

import '../../config/categories.dart';
import '../../core/formatters.dart';
import '../../data/models/movement.dart';

/// Nombres de los meses en español de México (RF-54).
const List<String> monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Un mes calendario (año y mes, 1 a 12).
class CalendarMonth {
  const CalendarMonth(this.year, this.month);

  /// Mes calendario de [now] en la hora local del dispositivo. Si [now]
  /// viene en UTC, primero se pasa a hora local (AMB-03).
  factory CalendarMonth.of(DateTime now) {
    final local = now.isUtc ? now.toLocal() : now;
    return CalendarMonth(local.year, local.month);
  }

  final int year;
  final int month;

  /// `true` si [date] cae en este mes. El último día del mes anterior y el
  /// primero del siguiente quedan fuera (CA-028).
  bool contains(DateTime date) => date.year == year && date.month == month;

  /// Por ejemplo, "noviembre 2026".
  String get label => '${monthNames[month - 1]} $year';

  @override
  bool operator ==(Object other) =>
      other is CalendarMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Resultado del cálculo, listo para mostrarse.
class MonthlyBalance {
  const MonthlyBalance({
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
  });

  final CalendarMonth month;
  final int incomeCents;
  final int expenseCents;

  /// Ingresos menos egresos, en centavos; negativo si los egresos son
  /// mayores (RF-10, CA-027).
  int get balanceCents => incomeCents - expenseCents;

  bool get isNegative => balanceCents < 0;

  /// Balance con formato de México: "$11,000.00" o "-$500.00" (CA-027).
  String get formattedBalance => formatCents(balanceCents);
}

/// Calcula el balance del mes en curso.
class BalanceCalculator {
  const BalanceCalculator();

  /// Suma ingresos y egresos de [movements] que caen en [month]. Los
  /// movimientos de otros meses se ignoran, aunque vengan en la lista
  /// (CA-028). Sin movimientos el balance es 0 (CA-026).
  MonthlyBalance calculate(
    Iterable<Movement> movements,
    CalendarMonth month,
  ) {
    var income = 0;
    var expense = 0;
    for (final movement in movements) {
      if (!month.contains(movement.date)) continue;
      if (movement.type == MovementType.ingreso) {
        income += movement.amountCents;
      } else {
        expense += movement.amountCents;
      }
    }
    return MonthlyBalance(
      month: month,
      incomeCents: income,
      expenseCents: expense,
    );
  }
}
