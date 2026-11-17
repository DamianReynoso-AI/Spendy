/// M-06 · Búsqueda y filtros de movimientos con conteo y suma (RF-32 a
/// RF-35; RNF-09; CA-083 a CA-094; AMB-04, AMB-05).
///
/// La interfaz usa este servicio; nunca lee `lib/data/` (RNF-30).
library;

import '../../core/error_logger.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../data/models/movement.dart';
import '../../data/repositories/movement_repository.dart';
import '../movements/movement_service.dart';

/// Mensajes de M-06.
class FilterMessages {
  FilterMessages._();

  /// Fecha final anterior a la inicial (CA-084).
  static const String invalidRange = 'El rango de fechas no es válido';
}

/// Criterios combinables. Los que van en `null` (o el texto vacío) no
/// filtran.
class MovementCriteria {
  const MovementCriteria({
    this.startDate,
    this.endDate,
    this.categoryId,
    this.type,
    this.text = '',
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final int? categoryId;
  final MovementType? type;

  /// Texto a buscar en la descripción y en la nota.
  final String text;

  /// `true` si no hay ningún filtro activo.
  bool get isEmpty =>
      startDate == null &&
      endDate == null &&
      categoryId == null &&
      type == null &&
      text.trim().isEmpty;

  MovementCriteria copyWith({
    DateTime? Function()? startDate,
    DateTime? Function()? endDate,
    int? Function()? categoryId,
    MovementType? Function()? type,
    String? text,
  }) =>
      MovementCriteria(
        startDate: startDate == null ? this.startDate : startDate(),
        endDate: endDate == null ? this.endDate : endDate(),
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        type: type == null ? this.type : type(),
        text: text ?? this.text,
      );
}

/// Movimientos encontrados con su conteo y sumas en centavos (RF-34).
class FilterResult {
  const FilterResult({
    required this.items,
    required this.incomeCents,
    required this.expenseCents,
  });

  final List<MovementItem> items;
  final int incomeCents;
  final int expenseCents;

  /// Número de resultados; 0 si no hay (CA-093).
  int get count => items.length;

  bool get hasIncome => items.any((i) => i.isIncome);
  bool get hasExpense => items.any((i) => !i.isIncome);

  /// `true` si hay ingresos y egresos: entonces las sumas se muestran
  /// separadas para no mezclar (CA-094, AMB-05).
  bool get isMixed => hasIncome && hasExpense;

  /// Suma de todos los montos (útil cuando solo hay un tipo); $0.00 sin
  /// resultados (CA-093).
  int get totalCents => incomeCents + expenseCents;

  /// "1 resultado" o "4 resultados".
  String get countLabel => count == 1 ? '1 resultado' : '$count resultados';

  /// Resumen de sumas listo para mostrarse (CA-092 a CA-094).
  String get sumLabel => isMixed
      ? 'Ingresos: ${formatCents(incomeCents)} · '
          'Egresos: ${formatCents(expenseCents)}'
      : 'Suma: ${formatCents(totalCents)}';
}

/// Quita acentos y diéresis (áéíóúüñ) y pasa a minúsculas, para que
/// "cafe" encuentre "Café" (CA-087, CA-090, AMB-04).
String normalizeForSearch(String text) {
  const from = 'áéíóúüñàèìòùâêîôûäëïö';
  const to = 'aeiouunaeiouaeiouaeio';
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    final index = from.indexOf(char);
    buffer.write(index == -1 ? char : to[index]);
  }
  return buffer.toString();
}

/// Servicio de filtrado.
class MovementFilter {
  MovementFilter({
    required MovementRepository repository,
    required ErrorLogger logger,
  })  : _repository = repository,
        _logger = logger;

  static const String module = 'M-06';

  final MovementRepository _repository;
  final ErrorLogger _logger;

  /// Error si la fecha final es anterior a la inicial (CA-084).
  AppError? validate(MovementCriteria criteria) {
    final start = criteria.startDate;
    final end = criteria.endDate;
    if (start == null || end == null) return null;
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    if (!endDay.isBefore(startDay)) return null;
    return const AppError(
      type: ErrorType.validation,
      message: FilterMessages.invalidRange,
    );
  }

  /// Aplica todos los criterios a la vez (CA-083, CA-091) y calcula conteo
  /// y sumas (RF-34). Con un rango inválido no consulta nada.
  Future<Result<FilterResult>> apply(MovementCriteria criteria) async {
    final invalid = validate(criteria);
    if (invalid != null) return Failure(invalid);
    try {
      final rows = await _repository.queryFilteredMovements(
        startDate: _iso(criteria.startDate),
        endDate: _iso(criteria.endDate),
        categoryId: criteria.categoryId,
        type: criteria.type?.value,
      );
      return Success(summarize(_matchText(rows, criteria.text)));
    } on Object catch (e) {
      final error = translateStorageError(e, writing: false);
      await _logger.log(type: error.type, module: module, cause: e);
      return Failure(error);
    }
  }

  /// Coincidencia parcial en descripción o nota, sin distinguir mayúsculas
  /// ni acentos. Todo carácter (`%`, `_`, `'`) cuenta como literal
  /// (CA-087, CA-088, CA-090).
  static List<Movement> _matchText(List<Movement> rows, String text) {
    final query = normalizeForSearch(text.trim());
    if (query.isEmpty) return rows;
    return rows.where((m) {
      final haystack = normalizeForSearch('${m.description ?? ''}\n'
          '${m.note ?? ''}');
      return haystack.contains(query);
    }).toList(growable: false);
  }

  /// Cuenta y suma en centavos enteros.
  static FilterResult summarize(List<Movement> rows) {
    var income = 0;
    var expense = 0;
    for (final m in rows) {
      if (m.type == MovementType.ingreso) {
        income += m.amountCents;
      } else {
        expense += m.amountCents;
      }
    }
    return FilterResult(
      items: rows.map(toMovementItem).toList(growable: false),
      incomeCents: income,
      expenseCents: expense,
    );
  }

  static String? _iso(DateTime? date) => date == null ? null : toIsoDate(date);
}
