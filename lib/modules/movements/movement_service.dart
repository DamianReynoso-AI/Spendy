/// M-02 · Servicio de movimientos: validar, guardar, listar, editar,
/// eliminar y calcular el balance del mes (RF-01 a RF-05, RF-07 a RF-11).
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
import '../receipts/receipt_service.dart';
import 'balance_calculator.dart';

export '../../config/categories.dart' show MovementType;
export 'balance_calculator.dart' show CalendarMonth, MonthlyBalance;

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
  static const String notFound =
      'Este movimiento ya no existe. Regresa a la lista para ver tus '
      'movimientos actuales.';
  static const String incomeNoReceipt =
      'Los ingresos no llevan recibo. Quita la foto o cambia a egreso.';
  static const String receiptDiscarded =
      ' La foto del recibo se descartó; vuelve a escanearla.';
  static const String deleteFailed =
      'No se pudo eliminar el movimiento por un problema con el '
      'almacenamiento del teléfono. El movimiento sigue guardado; '
      'intenta de nuevo.';
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
    required this.categoryId,
    required this.categoryName,
    this.paymentMethod,
    this.description,
    this.note,
  });

  final int id;
  final MovementType type;
  final int amountCents;
  final DateTime date;
  final int categoryId;
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

/// Validación, guardado, edición, borrado y balance de movimientos.
class MovementService {
  MovementService({
    required MovementRepository repository,
    required CategoryCatalog catalog,
    required ErrorLogger logger,
    DateTime Function()? clock,
    BalanceCalculator calculator = const BalanceCalculator(),
  })  : _repository = repository,
        _catalog = catalog,
        _logger = logger,
        _clock = clock ?? DateTime.now,
        _calculator = calculator;

  static const String module = 'M-02';

  final MovementRepository _repository;
  final CategoryCatalog _catalog;
  final ErrorLogger _logger;
  final DateTime Function() _clock;
  final BalanceCalculator _calculator;

  /// Bajas en curso por id: un segundo toque sobre el mismo id recibe el
  /// mismo resultado en lugar de borrar otra vez (CA-024).
  final Map<int, Future<Result<void>>> _pendingDeletes = {};

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
  ///
  /// Con [receipt] (ya comprimido) guarda el egreso y su recibo de forma
  /// atómica (RNF-21): o se guardan los dos o ninguno. Si falla, M-11 borra
  /// la imagen temporal (CA-060, CA-061) y el mensaje lo dice.
  Future<Result<int>> save(MovementDraft draft, {TempReceipt? receipt}) async {
    final validation = await validate(draft);
    if (validation case Failure(:final error)) return Failure(error);
    if (receipt != null && draft.type == MovementType.ingreso) {
      return const Failure(_incomeReceiptError);
    }
    final movement = _toMovement(draft);
    try {
      final id = receipt == null
          ? await _repository.insert(movement)
          : await _repository.insertWithReceipt(movement, receipt.toPending());
      return Success(id);
    } on Object catch (e) {
      final error = await _storageFailure(e, writing: true);
      if (receipt == null) return Failure(error);
      return Failure(
        AppError(
          type: error.type,
          message: error.message + MovementMessages.receiptDiscarded,
        ),
      );
    }
  }

  /// Todos los movimientos, del más reciente al más antiguo (RF-07).
  Future<Result<List<MovementItem>>> list() async {
    try {
      final movements = await _repository.fetchAll();
      return Success(movements.map(toMovementItem).toList(growable: false));
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: false));
    }
  }

  /// El movimiento [id] con sus datos actuales (para el detalle y para
  /// prellenar la edición). Falla con [MovementMessages.notFound] si ya no
  /// existe.
  Future<Result<MovementItem>> findById(int id) async {
    try {
      final movement = await _repository.findById(id);
      if (movement == null) return const Failure(_notFoundError);
      return Success(toMovementItem(movement));
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: false));
    }
  }

  /// Valida con las mismas reglas que al crear (RF-01 a RF-06, RF-14;
  /// CA-017, CA-019) y guarda los cambios del movimiento [id] (RF-08).
  /// Si la escritura falla, el registro conserva su valor anterior y se
  /// devuelve un error para la persona (CA-018).
  Future<Result<void>> update(int id, MovementDraft draft) async {
    final validation = await validate(draft);
    if (validation case Failure(:final error)) return Failure(error);
    final movement = _toMovement(draft, id: id);
    try {
      final changed = await _repository.updateMovement(movement);
      return changed == 0 ? const Failure(_notFoundError) : const Success(null);
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: true));
    }
  }

  /// Elimina el movimiento [id] y, en cascada, su recibo (RF-09). Si llega
  /// otra petición para el mismo id mientras la primera sigue en curso
  /// (doble toque), se devuelve el mismo resultado: solo hay una baja y no
  /// hay error (CA-024). Un id que ya no existe también cuenta como éxito.
  Future<Result<void>> delete(int id) {
    final pending = _pendingDeletes[id];
    if (pending != null) return pending;
    final operation = _deleteOnce(id);
    _pendingDeletes[id] = operation;
    return operation.whenComplete(() => _pendingDeletes.remove(id));
  }

  Future<Result<void>> _deleteOnce(int id) async {
    try {
      await _repository.deleteMovement(id);
      return const Success(null);
    } on Object catch (e) {
      final error = await _storageFailure(e, writing: true);
      return Failure(
        AppError(type: error.type, message: MovementMessages.deleteFailed),
      );
    }
  }

  /// Balance del mes en curso, según la hora local del dispositivo
  /// (RF-10; AMB-03). Sin movimientos devuelve $0.00 (CA-026).
  Future<Result<MonthlyBalance>> currentMonthBalance() async {
    final month = CalendarMonth.of(_clock());
    try {
      final movements =
          await _repository.getMovementsByMonth(month.year, month.month);
      return Success(_calculator.calculate(movements, month));
    } on Object catch (e) {
      return Failure(await _storageFailure(e, writing: false));
    }
  }

  static const AppError _incomeReceiptError = AppError(
    type: ErrorType.validation,
    message: MovementMessages.incomeNoReceipt,
  );

  static const AppError _notFoundError = AppError(
    type: ErrorType.unexpected,
    message: MovementMessages.notFound,
  );

  Future<AppError> _storageFailure(Object e, {required bool writing}) async {
    final error = translateStorageError(e, writing: writing);
    await _logger.log(type: error.type, module: module, cause: e);
    return error;
  }

  /// Convierte el borrador ya validado al modelo de la base. Con [id] es
  /// una edición: el repositorio no cambia `creado_en` y pone su propio
  /// `actualizado_en`.
  Movement _toMovement(MovementDraft draft, {int? id}) {
    final now = _clock();
    final isExpense = draft.type == MovementType.egreso;
    final date = draft.date!;
    return Movement(
      id: id,
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
}

/// Convierte un monto ya validado por [validateAmount] a centavos, con
/// enteros para no tener errores de redondeo: "1234.5" -> 123450.
int amountTextToCents(String amountText) {
  final parts = amountText.trim().split('.');
  final decimals = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return int.parse(parts.first) * 100 + int.parse(decimals);
}

/// Convierte centavos al texto que acepta el campo de monto, para
/// prellenar la edición: 123450 -> "1234.50".
String centsToAmountText(int cents) {
  final centavos = (cents % 100).toString().padLeft(2, '0');
  return '${cents ~/ 100}.$centavos';
}

/// Quita espacios de los extremos; un texto vacío se guarda como `null`.
String? _clean(String? text) {
  final trimmed = text?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Convierte un registro de la base en un elemento de la lista (también
/// lo usa M-06 para los resultados filtrados).
MovementItem toMovementItem(Movement m) => MovementItem(
      id: m.id!,
      type: m.type,
      amountCents: m.amountCents,
      date: m.date,
      categoryId: m.categoryId,
      categoryName: m.categoryName ?? '',
      paymentMethod: PaymentMethod.fromValue(m.paymentMethod),
      description: m.description,
      note: m.note,
    );
