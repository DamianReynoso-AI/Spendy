/// M-07 · Servicio del resumen anual: lee los movimientos del año (M-11) y
/// los pasa a [AnnualSummaryCalculator] (RF-36 a RF-40, RNF-10).
///
/// La interfaz usa este servicio; nunca lee `lib/data/` (RNF-30).
library;

import '../../core/error_logger.dart';
import '../../core/result.dart';
import '../../data/repositories/movement_repository.dart';
import 'annual_summary_calculator.dart';

export 'annual_summary_calculator.dart'
    show AnnualSummary, CategoryTotal, YearOptions;

/// Lectura y cálculo del resumen anual.
class SummaryService {
  SummaryService({
    required MovementRepository repository,
    required ErrorLogger logger,
    DateTime Function()? clock,
    AnnualSummaryCalculator calculator = const AnnualSummaryCalculator(),
  })  : _repository = repository,
        _logger = logger,
        _clock = clock ?? DateTime.now,
        _calculator = calculator;

  static const String module = 'M-07';

  final MovementRepository _repository;
  final ErrorLogger _logger;
  final DateTime Function() _clock;
  final AnnualSummaryCalculator _calculator;

  /// Años del selector con el actual seleccionado (RF-36).
  Future<Result<YearOptions>> yearOptions() async {
    try {
      final years = await _repository.getYearsWithMovements();
      return Success(_calculator.yearOptions(years, _clock()));
    } on Object catch (e) {
      return Failure(await _readFailure(e));
    }
  }

  /// Resumen de [year] (RF-37 a RF-40).
  Future<Result<AnnualSummary>> summaryFor(int year) async {
    try {
      final movements = await _repository.getMovementsByYear(year);
      return Success(_calculator.calculate(year, movements));
    } on Object catch (e) {
      return Failure(await _readFailure(e));
    }
  }

  Future<AppError> _readFailure(Object e) async {
    final error = translateStorageError(e, writing: false);
    await _logger.log(type: error.type, module: module, cause: e);
    return error;
  }
}
