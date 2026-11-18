/// M-14 · Presupuestos mensuales por categoría de egreso: se fija un
/// límite y la app muestra cuánto lleva gastado en el mes en curso y
/// avisa al acercarse o pasarse.
///
/// La interfaz pide aquí los datos; nunca lee la base (RNF-30).
library;

import '../../config/app_config.dart';
import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/movement_repository.dart';
import '../categories/category_catalog.dart';
import '../movements/balance_calculator.dart';
import 'budget_calculator.dart';

export 'budget_calculator.dart' show BudgetLine, BudgetStatus;

/// Mensajes de presupuestos (RNF-05).
class BudgetMessages {
  BudgetMessages._();

  static const String saveFailed =
      'No se pudo guardar el presupuesto por un problema con el '
      'almacenamiento del teléfono. Toca "Guardar" de nuevo.';
  static const String tooBig = 'El monto máximo es \$9,999,999.99.';
}

/// Presupuestos del mes en curso.
class BudgetOverview {
  const BudgetOverview({required this.month, required this.lines});

  final CalendarMonth month;

  /// Solo las categorías que tienen presupuesto, en su orden fijo.
  final List<BudgetLine> lines;

  bool get isEmpty => lines.isEmpty;
  int get limitCents => lines.fold(0, (sum, l) => sum + l.limitCents);
  int get spentCents => lines.fold(0, (sum, l) => sum + l.spentCents);
}

/// Orquesta los presupuestos.
class BudgetService {
  BudgetService({
    required BudgetRepository budgets,
    required MovementRepository movements,
    required CategoryCatalog catalog,
    required ErrorLogger logger,
    DateTime Function()? clock,
    BudgetCalculator calculator = const BudgetCalculator(),
  })  : _budgets = budgets,
        _movements = movements,
        _catalog = catalog,
        _logger = logger,
        _clock = clock ?? DateTime.now,
        _calculator = calculator;

  static const String module = 'M-14';

  final BudgetRepository _budgets;
  final MovementRepository _movements;
  final CategoryCatalog _catalog;
  final ErrorLogger _logger;
  final DateTime Function() _clock;
  final BudgetCalculator _calculator;

  /// Límites guardados: id de categoría -> centavos.
  Future<Result<Map<int, int>>> limits() async {
    try {
      return Success(await _budgets.fetchAll());
    } on Object catch (e) {
      return Failure(await _fail(e, writing: false));
    }
  }

  /// Avance de cada presupuesto en el mes en curso.
  Future<Result<BudgetOverview>> currentMonth() async {
    final month = CalendarMonth.of(_clock());
    final categories = await _catalog.forType(MovementType.egreso);
    if (categories case Failure(:final error)) return Failure(error);
    try {
      final limits = await _budgets.fetchAll();
      final movements =
          await _movements.getMovementsByMonth(month.year, month.month);
      final lines = _calculator.calculate(
        limits: limits,
        names: {for (final c in categories.valueOrNull!) c.id: c.name},
        movements: movements,
      );
      return Success(BudgetOverview(month: month, lines: lines));
    } on Object catch (e) {
      return Failure(await _fail(e, writing: false));
    }
  }

  /// Guarda el límite de una categoría. `null` o cero lo quita.
  Future<Result<void>> setLimit(int categoryId, int? cents) async {
    if (cents != null && cents > AppConfig.maxAmountCents) {
      return const Failure(
        AppError(type: ErrorType.validation, message: BudgetMessages.tooBig),
      );
    }
    try {
      await _budgets.setLimit(
          categoryId, (cents == null || cents <= 0) ? null : cents);
      return const Success(null);
    } on Object catch (e) {
      final error = await _fail(e, writing: true);
      return Failure(
        AppError(type: error.type, message: BudgetMessages.saveFailed),
      );
    }
  }

  Future<AppError> _fail(Object e, {required bool writing}) async {
    final error = translateStorageError(e, writing: writing);
    await _logger.log(type: error.type, module: module, cause: e);
    return error;
  }
}
