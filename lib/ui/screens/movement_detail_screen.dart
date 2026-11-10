/// M-01 · Detalle de un movimiento con las acciones de editar y eliminar
/// (RF-08, RF-09; CA-016 a CA-024).
///
/// Solo habla con los servicios de M-02 y M-03; nunca con `lib/data/`
/// (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import 'movement_form_screen.dart';

/// Lo que pasó en el detalle, para que la lista avise y se refresque.
enum MovementDetailResult { deleted }

/// Muestra todos los campos del movimiento. Al eliminarlo regresa
/// [MovementDetailResult.deleted].
class MovementDetailScreen extends StatefulWidget {
  const MovementDetailScreen({
    super.key,
    required this.service,
    required this.catalog,
    required this.movement,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final MovementItem movement;

  @override
  State<MovementDetailScreen> createState() => _MovementDetailScreenState();
}

class _MovementDetailScreenState extends State<MovementDetailScreen> {
  late MovementItem _item = widget.movement;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Abre el formulario en modo edición. Si se guardó, vuelve a leer el
  /// movimiento para que el detalle muestre los datos nuevos (CA-019).
  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MovementFormScreen(
          service: widget.service,
          catalog: widget.catalog,
          movement: _item,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final result = await widget.service.findById(_item.id);
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        setState(() => _item = value);
        _showMessage('Cambios guardados.');
      case Failure(:final error):
        _showMessage(error.message);
    }
  }

  /// Pide confirmación en un diálogo modal. "Cancelar" no cambia nada
  /// (CA-022); "Eliminar" borra y regresa a la lista (CA-021).
  Future<void> _delete() async {
    final result = await showDialog<Result<void>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteMovementDialog(
        onConfirm: () => widget.service.delete(_item.id),
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(MovementDetailResult.deleted);
      case Failure(:final error):
        _showMessage(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del movimiento')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ..._fields(),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _edit,
              icon: const Icon(Icons.edit),
              label: const Text('Editar'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            _deleteButton(),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() {
    final item = _item;
    return [
      _DetailField(label: 'Tipo', value: item.isIncome ? 'Ingreso' : 'Egreso'),
      _DetailField(label: 'Monto', value: item.formattedAmount),
      _DetailField(label: 'Fecha', value: item.formattedDate),
      _DetailField(label: 'Categoría', value: item.categoryName),
      if (item.paymentMethod case final method?)
        _DetailField(label: 'Método de pago', value: method.label),
      if (item.description case final description?)
        _DetailField(label: 'Descripción o comercio', value: description),
      if (item.note case final note?) _DetailField(label: 'Nota', value: note),
    ];
  }

  Widget _deleteButton() {
    final error = Theme.of(context).colorScheme.error;
    return OutlinedButton.icon(
      onPressed: _delete,
      icon: const Icon(Icons.delete_outline),
      label: const Text('Eliminar'),
      style: OutlinedButton.styleFrom(
        foregroundColor: error,
        side: BorderSide(color: error),
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}

/// Un dato del detalle: etiqueta arriba y valor abajo, para que con texto
/// al 200 % nada se corte (RNF-06).
class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textTheme.labelLarge),
            Text(value, style: textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Diálogo modal de confirmación (RF-09). "Eliminar" se deshabilita al
/// primer toque y ejecuta [onConfirm] una sola vez (CA-024); al terminar,
/// cierra el diálogo con el resultado. "Cancelar" cierra con `null`.
class DeleteMovementDialog extends StatefulWidget {
  const DeleteMovementDialog({super.key, required this.onConfirm});

  final Future<Result<void>> Function() onConfirm;

  @override
  State<DeleteMovementDialog> createState() => _DeleteMovementDialogState();
}

class _DeleteMovementDialogState extends State<DeleteMovementDialog> {
  bool _deleting = false;

  Future<void> _confirm() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final result = await widget.onConfirm();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Eliminar este movimiento?'),
      content: const Text(
        'Se borrará el movimiento y su recibo, si tiene. Esta acción no se '
        'puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _deleting ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            minimumSize: const Size(48, 48),
          ),
          child: Text(_deleting ? 'Eliminando…' : 'Eliminar'),
        ),
      ],
    );
  }
}
