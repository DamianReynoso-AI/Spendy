/// M-01 · Detalle de un movimiento con las acciones de editar y eliminar
/// (RF-08, RF-09; CA-016 a CA-024) y, en los egresos, el recibo con zoom y
/// las acciones Agregar, Reemplazar y Quitar recibo (RF-19, RF-20;
/// CA-050 a CA-055).
///
/// Solo habla con los servicios de M-02, M-03 y M-04; nunca con
/// `lib/data/` (RNF-30).
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import '../widgets/confirm_dialog.dart';
import 'movement_form_screen.dart';
import 'scan_screen.dart';

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
    this.receipts,
    this.camera,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final MovementItem movement;

  /// Servicios de recibos y cámara (M-04). Sin ellos no se muestra la
  /// sección del recibo.
  final ReceiptService? receipts;
  final CameraService? camera;

  @override
  State<MovementDetailScreen> createState() => _MovementDetailScreenState();
}

class _MovementDetailScreenState extends State<MovementDetailScreen> {
  late MovementItem _item = widget.movement;

  ReceiptView? _receipt;
  bool _receiptLoading = false;
  String? _receiptError;
  bool _receiptBusy = false;

  bool get _showsReceipt => !_item.isIncome && widget.receipts != null;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    final receipts = widget.receipts;
    if (receipts == null || _item.isIncome) return;
    setState(() {
      _receiptLoading = true;
      _receiptError = null;
    });
    final result = await receipts.receiptOf(_item.id);
    if (!mounted) return;
    setState(() {
      _receiptLoading = false;
      _receipt = result.valueOrNull;
      _receiptError = result.errorOrNull?.message;
    });
  }

  /// "Agregar recibo" (sin confirmación) o "Reemplazar" (con confirmación
  /// modal; si cancela no cambia nada, CA-053, CA-055).
  Future<void> _addOrReplace({required bool replace}) async {
    if (replace) {
      final confirmed = await showConfirmDialog(
        context,
        title: '¿Reemplazar el recibo?',
        content: 'Tomarás una foto nueva. La foto actual se borrará al '
            'guardar la nueva.',
        confirmLabel: 'Reemplazar',
      );
      if (!confirmed || !mounted) return;
    }
    final photo = await _takePhoto();
    if (photo == null || !mounted) return;
    await _runReceiptChange(
      () => widget.receipts!.attach(_item.id, photo),
      replace ? 'Recibo reemplazado.' : 'Recibo agregado.',
    );
  }

  Future<TempReceipt?> _takePhoto() async {
    final receipts = widget.receipts!;
    final camera = widget.camera;
    if (camera == null) return null;
    final outcome = await Navigator.of(context).push<ScanOutcome>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(camera: camera, receipts: receipts),
      ),
    );
    return outcome?.photo;
  }

  /// "Quitar recibo" con confirmación modal (RF-20, CA-054).
  Future<void> _removeReceipt() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '¿Quitar el recibo?',
      content: 'Se borrará la foto del recibo. El movimiento se conserva.',
      confirmLabel: 'Quitar',
    );
    if (!confirmed || !mounted) return;
    await _runReceiptChange(
      () => widget.receipts!.remove(_item.id),
      'Recibo quitado.',
    );
  }

  Future<void> _runReceiptChange(
    Future<Result<void>> Function() change,
    String successText,
  ) async {
    setState(() => _receiptBusy = true);
    final result = await change();
    if (!mounted) return;
    setState(() => _receiptBusy = false);
    _showMessage(result.errorOrNull?.message ?? successText);
    await _loadReceipt();
  }

  void _openViewer(String path) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReceiptViewerScreen(path: path)),
    );
  }

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
            if (_showsReceipt) ...[
              const SizedBox(height: 16),
              _receiptSection(),
            ],
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

  /// Recibo del egreso: miniatura que se amplía, aviso si el archivo no
  /// existe (CA-051) y acciones Agregar, Reemplazar y Quitar (RF-20).
  Widget _receiptSection() {
    if (_receiptLoading || _receiptBusy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_receiptError != null) return Text(_receiptError!);
    final receipt = _receipt;
    if (receipt == null) {
      return _receiptButton(
        'Agregar recibo',
        Icons.add_a_photo_outlined,
        () => _addOrReplace(replace: false),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Recibo', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        receipt.exists
            ? _ReceiptThumbnail(
                path: receipt.path,
                onTap: () => _openViewer(receipt.path),
              )
            : const MissingReceiptNotice(),
        const SizedBox(height: 8),
        _receiptButton(
          'Reemplazar',
          Icons.flip_camera_android_outlined,
          () => _addOrReplace(replace: true),
        ),
        const SizedBox(height: 8),
        _receiptButton(
          'Quitar recibo',
          Icons.hide_image_outlined,
          _removeReceipt,
          needsCamera: false,
        ),
      ],
    );
  }

  Widget _receiptButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool needsCamera = true,
  }) {
    final enabled = !needsCamera || widget.camera != null;
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
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

/// Miniatura del recibo; al tocarla se abre el visor con zoom (CA-050).
class _ReceiptThumbnail extends StatelessWidget {
  const _ReceiptThumbnail({required this.path, required this.onTap});

  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Foto del recibo. Toca para ampliarla.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const MissingReceiptNotice(),
          ),
        ),
      ),
    );
  }
}

/// Aviso cuando la imagen no está en la ruta registrada: la app no se
/// cierra y el egreso sigue accesible (CA-051).
class MissingReceiptNotice extends StatelessWidget {
  const MissingReceiptNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline),
          SizedBox(width: 12),
          Expanded(child: Text(ReceiptMessages.missingFile)),
        ],
      ),
    );
  }
}

/// Visor del recibo a pantalla completa con zoom de pellizco (RF-19,
/// CA-050).
class ReceiptViewerScreen extends StatelessWidget {
  const ReceiptViewerScreen({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Recibo')),
      body: SafeArea(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Center(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              semanticLabel: 'Recibo ampliado',
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(16),
                child: MissingReceiptNotice(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
