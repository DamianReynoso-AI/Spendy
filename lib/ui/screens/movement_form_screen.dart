/// M-01 · Formulario para registrar o editar un ingreso o un egreso
/// (RF-01 a RF-06, RF-08, RF-11, RF-14).
///
/// Solo habla con los servicios de M-02 y M-03; nunca con `lib/data/`
/// (RNF-30). Si algo falla, los datos capturados se quedan en el formulario
/// para poder reintentar (RF-05, RF-11).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../core/formatters.dart';
import '../../core/result.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../widgets/amount_field.dart';

/// Pantalla de captura. Al guardar con éxito regresa `true`.
///
/// Con [movement] abre en modo edición (RF-08): los campos vienen
/// prellenados y "Guardar" actualiza ese movimiento. Si la persona sale o
/// guarda sin cambiar nada, regresa `false` y no se escribe en la base
/// (CA-020).
class MovementFormScreen extends StatefulWidget {
  const MovementFormScreen({
    super.key,
    required this.service,
    required this.catalog,
    this.initialType = MovementType.egreso,
    this.movement,
    this.clock,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final MovementType initialType;

  /// Movimiento a editar; `null` para registrar uno nuevo.
  final MovementItem? movement;

  /// Reloj para fijar "hoy" en pruebas; por defecto, el del dispositivo.
  final DateTime Function()? clock;

  @override
  State<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends State<MovementFormScreen> {
  late final MovementItem? _original = widget.movement;
  late final _amount = TextEditingController(
    text: _original == null ? '' : centsToAmountText(_original.amountCents),
  );
  late final _description =
      TextEditingController(text: _original?.description ?? '');
  late final _note = TextEditingController(text: _original?.note ?? '');

  late MovementType _type = _original?.type ?? widget.initialType;
  late DateTime _date = _original?.date ?? _today();
  late int? _categoryId = _original?.categoryId;
  late PaymentMethod? _paymentMethod = _original?.paymentMethod;

  List<CategoryOption> _categories = const [];
  bool _loadingCategories = true;
  String? _categoriesError;

  Map<String, String> _fieldErrors = const {};
  String? _message;
  bool _canRetry = false;
  bool _saving = false;

  bool get _isExpense => _type == MovementType.egreso;
  bool get _isEditing => _original != null;

  DateTime _today() {
    final now = (widget.clock ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _loadingCategories = true;
      _categoriesError = null;
    });
    final result = await widget.catalog.forType(_type);
    if (!mounted) return;
    setState(() {
      _loadingCategories = false;
      _categories = result.valueOrNull ?? const [];
      _categoriesError = result.errorOrNull?.message;
    });
  }

  /// Cambiar de tipo solo borra la categoría (la del otro tipo ya no es
  /// válida, RF-14). Lo demás se conserva.
  void _changeType(MovementType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _categoryId = null;
      _fieldErrors = const {};
      _message = null;
    });
    _loadCategories();
  }

  void _clearError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors = Map.of(_fieldErrors)..remove(field));
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: _date.isBefore(DateTime(2000)) ? _date : DateTime(2000),
      lastDate: today,
      helpText: 'Elige la fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    _clearError(MovementFields.date);
  }

  MovementDraft _draft() => MovementDraft(
        type: _type,
        amountText: _amount.text,
        date: _date,
        categoryId: _categoryId,
        paymentMethod: _isExpense ? _paymentMethod : null,
        description: _isExpense ? _description.text : null,
        note: _note.text,
      );

  /// `true` si algún campo es distinto del movimiento original. Compara
  /// el borrador con el original campo por campo (los ingresos no tienen
  /// método ni descripción, así que ambos quedan en `null`).
  bool _hasChanges(MovementItem original) {
    final draft = _draft();
    final differences = [
      draft.type != original.type,
      draft.amountText != centsToAmountText(original.amountCents),
      !DateUtils.isSameDay(draft.date, original.date),
      draft.categoryId != original.categoryId,
      draft.paymentMethod != original.paymentMethod,
      (draft.description ?? '') != (original.description ?? ''),
      (draft.note ?? '') != (original.note ?? ''),
    ];
    return differences.contains(true);
  }

  /// Crea o, en modo edición, actualiza. Sin cambios no escribe (CA-020).
  Future<Result<void>?> _submit() {
    final original = _original;
    if (original == null) return widget.service.save(_draft());
    if (!_hasChanges(original)) return Future.value();
    return widget.service.update(original.id, _draft());
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await _submit();
    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop(false);
      return;
    }
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(:final error):
        setState(() {
          _saving = false;
          _fieldErrors = error.fieldErrors;
          _message = error.message;
          _canRetry = error.type != ErrorType.validation;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _typeSelector(),
            const SizedBox(height: 16),
            if (_message != null) ...[
              _messageBanner(),
              const SizedBox(height: 16)
            ],
            AmountField(
              controller: _amount,
              errorText: _fieldErrors[MovementFields.amount],
              onChanged: (_) => _clearError(MovementFields.amount),
            ),
            const SizedBox(height: 16),
            _dateField(),
            const SizedBox(height: 16),
            _categoryField(),
            if (_isExpense) ...[
              const SizedBox(height: 16),
              _paymentMethodField(),
              const SizedBox(height: 16),
              _descriptionField(),
            ],
            const SizedBox(height: 16),
            _noteField(),
            const SizedBox(height: 24),
            _saveButton(),
          ],
        ),
      ),
    );
  }

  String _title() {
    final action = _isEditing ? 'Editar' : 'Registrar';
    return '$action ${_isExpense ? 'egreso' : 'ingreso'}';
  }

  Widget _typeSelector() {
    return SegmentedButton<MovementType>(
      segments: const [
        ButtonSegment(
          value: MovementType.egreso,
          label: Text('Egreso'),
          icon: Icon(Icons.arrow_upward),
        ),
        ButtonSegment(
          value: MovementType.ingreso,
          label: Text('Ingreso'),
          icon: Icon(Icons.arrow_downward),
        ),
      ],
      selected: {_type},
      onSelectionChanged: (s) => _changeType(s.first),
    );
  }

  Widget _messageBanner() {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_message!, style: TextStyle(color: colors.onErrorContainer)),
            if (_canRetry)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _saving ? null : _save,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onErrorContainer,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Reintentar'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dateField() {
    return Semantics(
      button: true,
      label: 'Fecha, ${formatDate(_date)}. Toca para cambiarla.',
      excludeSemantics: true,
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(4),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Fecha *',
            errorText: _fieldErrors[MovementFields.date],
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          child: Text(formatDate(_date)),
        ),
      ),
    );
  }

  /// Selector de categorías del tipo actual. Sin opción de crear ni
  /// editar categorías (CA-034).
  Widget _categoryField() {
    if (_loadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_categoriesError != null) {
      return _categoriesErrorView();
    }
    return _dropdown<int>(
      label: 'Categoría *',
      value: _categoryId,
      errorText: _fieldErrors[MovementFields.category],
      items: {for (final c in _categories) c.id: c.name},
      onChanged: (id) {
        setState(() => _categoryId = id);
        _clearError(MovementFields.category);
      },
    );
  }

  Widget _categoriesErrorView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _categoriesError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: _loadCategories,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Reintentar'),
        ),
      ],
    );
  }

  Widget _paymentMethodField() {
    return _dropdown<PaymentMethod>(
      label: 'Método de pago *',
      value: _paymentMethod,
      errorText: _fieldErrors[MovementFields.paymentMethod],
      items: {for (final m in PaymentMethod.values) m: m.label},
      onChanged: (method) {
        setState(() => _paymentMethod = method);
        _clearError(MovementFields.paymentMethod);
      },
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required String? errorText,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          hint: const Text('Elige una opción'),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _descriptionField() => _limitedText(
        controller: _description,
        label: 'Descripción o comercio (opcional)',
        maxLength: AppConfig.maxDescriptionLength,
        field: MovementFields.description,
      );

  Widget _noteField() => _limitedText(
        controller: _note,
        label: 'Nota (opcional)',
        maxLength: AppConfig.maxNoteLength,
        field: MovementFields.note,
        maxLines: 3,
      );

  /// Campo con contador visible (0/60, 0/200) que no deja escribir más
  /// allá del límite (RF-06, CA-006).
  Widget _limitedText({
    required TextEditingController controller,
    required String label,
    required int maxLength,
    required String field,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      minLines: 1,
      maxLines: maxLines,
      onChanged: (_) => _clearError(field),
      decoration: InputDecoration(
        labelText: label,
        errorText: _fieldErrors[field],
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _saveButton() {
    return FilledButton(
      onPressed: _saving ? null : _save,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: Text(_saving ? 'Guardando…' : 'Guardar'),
    );
  }
}
