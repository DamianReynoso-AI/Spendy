/// M-01 · Edición de los presupuestos mensuales por categoría de egreso
/// (M-14). Un campo vacío quiere decir "sin presupuesto".
///
/// Solo usa M-03 y M-14; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/result.dart';
import '../../core/validators.dart';
import '../../modules/budgets/budget_service.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../theme/spendy_theme.dart';

/// Pantalla de presupuestos. Devuelve `true` si se guardó algo.
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key, required this.budgets, required this.catalog});

  final BudgetService budgets;
  final CategoryCatalog catalog;

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<CategoryOption>? _categories;
  final Map<int, TextEditingController> _fields = {};
  final Map<int, String?> _errors = {};
  Map<int, int> _saved = {};
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final categories = await widget.catalog.forType(MovementType.egreso);
    final limits = await widget.budgets.limits();
    if (!mounted) return;
    final error = categories.errorOrNull ?? limits.errorOrNull;
    if (error != null) {
      setState(() => _loadError = error.message);
      return;
    }
    _saved = limits.valueOrNull!;
    for (final c in categories.valueOrNull!) {
      final cents = _saved[c.id];
      _fields[c.id] = TextEditingController(
        text: cents == null ? '' : centsToAmountText(cents),
      );
    }
    setState(() => _categories = categories.valueOrNull);
  }

  Future<void> _save() async {
    final categories = _categories;
    if (categories == null || _saving) return;
    final changes = _changes(categories);
    if (changes == null) return;
    setState(() => _saving = true);
    for (final entry in changes.entries) {
      final result = await widget.budgets.setLimit(entry.key, entry.value);
      if (result case Failure(:final error)) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(changes.isNotEmpty);
  }

  /// Valida cada campo y devuelve solo los límites que cambiaron
  /// (`null` = quitar). Si algún campo tiene error lo marca y devuelve
  /// `null`.
  Map<int, int?>? _changes(List<CategoryOption> categories) {
    final changes = <int, int?>{};
    for (final c in categories) {
      final text = _fields[c.id]!.text.trim();
      final error = text.isEmpty ? null : validateAmount(text);
      _errors[c.id] = error;
      if (error != null) continue;
      final cents = text.isEmpty ? null : amountTextToCents(text);
      if (cents != _saved[c.id]) changes[c.id] = cents;
    }
    setState(() {});
    return _errors.values.any((e) => e != null) ? null : changes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      body: _body(),
      bottomNavigationBar: _categories == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('save_budgets'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Guardando…' : 'Guardar'),
                ),
              ),
            ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_loadError!, textAlign: TextAlign.center),
        ),
      );
    }
    final categories = _categories;
    if (categories == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          'Escribe cuánto quieres gastar como máximo cada mes. Deja vacío lo '
          'que no quieras controlar. Te avisamos al llegar al 80 % y cuando '
          'te pases.',
          style: TextStyle(color: SpendyPalette.of(context).muted),
        ),
        const SizedBox(height: 16),
        for (final c in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              key: Key('budget_${c.id}'),
              controller: _fields[c.id],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: InputDecoration(
                labelText: c.name,
                prefixText: r'$ ',
                hintText: 'Sin presupuesto',
                errorText: _errors[c.id],
                border: const OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}
