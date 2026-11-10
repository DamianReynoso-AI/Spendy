/// M-02 · Servicio de movimientos: validar, guardar y listar
/// (RF-01 a RF-05, RF-07, RF-11).
///
/// Es lo único que la interfaz (M-01) usa para movimientos; las pantallas
/// nunca importan `lib/data/` (RNF-30).
library;

import '../../config/app_config.dart';
import '../../core/error_logger.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../core/validators.dart';
import '../../data/models/movement.dart';
import '../../data/repositories/movement_repository.dart';
import '../categories/category_catalog.dart';

export '../../config/categories.dart' show MovementType;

/// Método de pago de un egreso (RF-01). `value` se guarda en la base.
enum PaymentMethod {
  efectivo('efectivo', 'Efectivo'),
  debito('debito', 'Débito'),
  credito('credito', 'Crédito'),
  transferencia('transferencia', 'Transferencia');

  const PaymentMethod(this.value, this.label);
  final String value;
  final String label;

  /// Busca el método por su valor guardado; `null` si no existe.
  static PaymentMethod? fromValue(String? value) {
    for (final method in values) {
      if (method.value == value) return method;
    }
    return null;
  }
}

/// Nombres de los campos del formulario. Son las llaves de
/// [AppError.fieldErrors] y de [AppError.missingFields].
class MovementFields {
  MovementFields._();

  static const String amount = 'monto';
  static const String date = 'fecha';
  static const String category = 'categoria';
  static const String paymentMethod = 'metodo_pago';
  static const String description = 'descripcion';
  static const String note = 'nota';
}

/// Mensajes propios del servicio (los demás vienen de M-12).
class MovementMessages {
  MovementMessages._();

  static const String categoryLabel = 'Categoría';
  static const String paymentMethodLabel = 'Método de pago';
  static const String categoryWrongType =
      'Elige una categoría de la lista de este tipo de movimiento.';
  static const String incomeNoPaymentMethod =
      'Los ingresos no llevan método de pago. Deja este campo vacío.';
  static const String incomeNoDescription =
      'Los ingresos no llevan descripción. Usa la nota si lo necesitas.';
}

/// Lo que la persona capturó en el formulario, tal cual.
class MovementDraft {
  const MovementDraft({
    required this.type,
    this.amountText,
    this.date,
    this.categoryId,
    this.paymentMethod,
    this.description,
    this.note,
  });

  final MovementType type;
  final String? amountText;
  final DateTime? date;
  final int? categoryId;
  final PaymentMethod? paymentMethod;
  final String? description;
  final String? note;
}

/// Un movimiento listo para mostrarse en la lista (RF-07, RF-54).
class MovementItem {
  const MovementItem({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.date,
    required this.categoryName,
    this.paymentMethod,
    this.description,
    this.note,
  });

  final int id;
  final MovementType type;
  final int amountCents;
  final DateTime date;
  final String categoryName;
  final PaymentMethod? paymentMethod;
  final String? description;
  final String? note;

  bool get isIncome => type == MovementType.ingreso;

  /// Monto con formato de México: $1,234.56 (RF-54).
  String get formattedAmount => formatCents(amountCents);

  /// Fecha con formato DD/MM/AAAA (RF-54).
  String get formattedDate => formatDate(date);
}

/// Validación y guardado de movimientos.
class MovementService {
  MovementService({
    required MovementRepository repository,
    required CategoryCatalog catalog,
    required ErrorLogger logger,
    DateTime Function()? clock,
  })  : _repository = repository,
        _catalog = catalog,
        _logger = logger,
        _clock = clock ?? DateTime.now;

  static const String module = 'M-02';

  final MovementRepository _repository;
  final CategoryCatalog _catalog;
  final ErrorLogger _logger;
  final DateTime Function() _clock;

  /// Valida los campos sin tocar la base. Devuelve los errores por campo
  /// (vacío si todo está bien). No revisa el tipo de la categoría; eso lo
  /// hace [validate] con el catálogo.
  Map<String, String> validateFields(MovementDraft draft) {
    final errors = <String, String>{};
    void add(String field, String? message) {
      if (message != null) errors[field] = message;
    }

    add(MovementFields.amount, validateAmount(draft.amountText));
    add(MovementFields.date, validateDate(draft.date, now: _clock()));
    add(
      MovementFields.category,
      validateRequiredField(draft.categoryId, MovementMessages.categoryLabel),
    );
    if (draft.type == MovementType.egreso) {
      _addExpenseErrors(draft, add);
    } else {
      _addIncomeErrors(draft, add);
    }
    add(
      MovementFields.note,
      validateTextLength(draft.note, AppConfig.maxNoteLength),
    );
    return errors;
  }

  /// Egreso (RF-01): método de pago obligatorio y descripción ≤ 60.
  void _addExpenseErrors(
    MovementDraft draft,
    void Function(String, String?) add,
  ) {
    add(
      MovementFields.paymentMethod,
      validateRequiredField(
        draft.paymentMethod,
        MovementMessages.paymentMethodLabel,
      ),
    );
    add(
      MovementFields.description,
      validateTextLength(draft.description, AppConfig.maxDescriptionLength),
    );
  }

  /// Ingreso (RF-02): sin método de pago ni descripción.
  void _addIncomeErrors(
    MovementDraft draft,
    void Function(String, String?) add,
  ) {
    if (draft.paymentMethod != null) {
      add(MovementFields.paymentMethod, MovementMessages.incomeNoPaymentMethod);
    }
    if (_clean(draft.description) != null) {
      add(MovementFields.description, MovementMessages.incomeNoDescription);
    }
  }

  /// Campos obligatorios vacíos, para resaltarlos (RF-05).
  List<String> missingFields(MovementDraft draft) {
    final amountText = draft.amountText?.trim() ?? '';
    return [
      if (amountText.isEmpty) MovementFields.amount,
      if (draft.date == null) MovementFields.date,
      if (draft.categoryId == null) MovementFields.category,
      if (draft.type == MovementType.egreso && draft.paymentMethod == null)
        MovementFields.paymentMethod,
    ];
  }

  /// Valida todo, incluida la regla de RF-14 (categoría del mismo tipo).
  /// Devuelve `Success(null)` si se puede guardar.
  Future<Result<void>> validate(MovementDraft draft) async {
    final errors = validateFields(draft);
    final categoryId = draft.categoryId;
    if (categoryId != null) {
      final check = await _catalog.belongsToType(categoryId, draft.type);
      if (check case Failure(:final error)) return Failure(error);
      if (check.valueOrNull == false) {
        errors[MovementFields.category] = MovementMessages.categoryWrongType;
      }
    }
    if (errors.isEmpty) return const Success(null);
    final missing = missingFields(draft);
    return Failure(
      AppError(
        type: ErrorType.validation,
        message: missing.isEmpty
            ? ErrorMessages.invalidFields
            : ErrorMessages.missingFields,
        fieldErrors: errors,
        missingFields: missing,
      ),
    );
  }

  /// Valida y guarda. Devuelve el id nuevo, o un error con el mensaje para
  /// la persona. Si falla, no se guarda nada y el formulario conserva lo
  /// capturado (RF-05, RF-11).
  Future<Result<int>> save(MovementDraft draft) async {
    final validation = await validate(draft);
    if (validation case Failure(:final error)) return Failure(error);
    final movement = _toMovement(draft);
    try {
      return Success(await _repository.insert(movement));
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: true));
    }
  }

  /// Todos los movimientos, del más reciente al más antiguo (RF-07).
  Future<Result<List<MovementItem>>> list() async {
    try {
      final movements = await _repository.fetchAll();
      return Success(movements.map(_toItem).toList(growable: false));
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: false));
    }
  }

  Future<AppError> _storageFailure(Object e, {required bool writing}) async {
    final error = translateStorageError(e, writing: writing);
    await _logger.log(type: error.type, module: module, cause: e);
    return error;
  }

  /// Convierte el borrador ya validado al modelo de la base.
  Movement _toMovement(MovementDraft draft) {
    final now = _clock();
    final isExpense = draft.type == MovementType.egreso;
    final date = draft.date!;
    return Movement(
      type: draft.type,
      amountCents: amountTextToCents(draft.amountText!),
      date: DateTime(date.year, date.month, date.day),
      categoryId: draft.categoryId!,
      paymentMethod: isExpense ? draft.paymentMethod?.value : null,
      description: isExpense ? _clean(draft.description) : null,
      note: _clean(draft.note),
      createdAt: now,
      updatedAt: now,
    );
  }

  MovementItem _toItem(Movement m) => MovementItem(
        id: m.id!,
        type: m.type,
        amountCents: m.amountCents,
        date: m.date,
        categoryName: m.categoryName ?? '',
        paymentMethod: PaymentMethod.fromValue(m.paymentMethod),
        description: m.description,
        note: m.note,
      );
}

/// Convierte un monto ya validado por [validateAmount] a centavos, con
/// enteros para no tener errores de redondeo: "1234.5" -> 123450.
int amountTextToCents(String amountText) {
  final parts = amountText.trim().split('.');
  final decimals = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return int.parse(parts.first) * 100 + int.parse(decimals);
}

/// Quita espacios de los extremos; un texto vacío se guarda como `null`.
String? _clean(String? text) {
  final trimmed = text?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
