/// M-15 · Indicadores del mes para la pantalla de inicio.
library;

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/repositories/movement_repository.dart';
import 'insights_calculator.dart';

export 'insights_calculator.dart' show MonthInsights;

/// Lee los movimientos de este mes y del pasado y arma los indicadores.
class InsightsService {
  InsightsService({
    required MovementRepository repository,
    required ErrorLogger logger,
    DateTime Function()? clock,
    InsightsCalculator calculator = const InsightsCalculator(),
  })  : _repository = repository,
        _logger = logger,
        _clock = clock ?? DateTime.now,
        _calculator = calculator;

  static const String module = 'M-15';

  final MovementRepository _repository;
  final ErrorLogger _logger;
  final DateTime Function() _clock;
  final InsightsCalculator _calculator;

  Future<Result<MonthInsights>> currentMonth() async {
    final now = _clock();
    final today = now.isUtc ? now.toLocal() : now;
    final previous = DateTime(today.year, today.month - 1);
    try {
      final current =
          await _repository.getMovementsByMonth(today.year, today.month);
      final past =
          await _repository.getMovementsByMonth(previous.year, previous.month);
      return Success(
        _calculator.calculate(today: today, current: current, previous: past),
      );
    } on Object catch (e) {
      final error = translateStorageError(e, writing: false);
      await _logger.log(type: error.type, module: module, cause: e);
      return Failure(error);
    }
  }
}
