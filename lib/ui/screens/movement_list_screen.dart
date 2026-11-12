/// M-01 · Lista de movimientos (RF-07, RF-54; CA-012 a CA-015) con acceso
/// al detalle para editar o eliminar (RF-08, RF-09).
///
/// Solo usa los servicios de M-02 y M-03; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import 'movement_detail_screen.dart';
import 'movement_form_screen.dart';

/// Colores de ingreso y egreso. Ambos tienen contraste mayor a 4.5:1 sobre
/// fondo blanco (RNF-06), y además se distinguen por ícono, signo y texto,
/// no solo por color.
class MovementColors {
  MovementColors._();

  /// Verde oscuro, contraste de 9.0:1 con blanco.
  static const Color income = Color(0xFF1B5E20);

  /// Rojo oscuro, contraste de 6.6:1 con blanco.
  static const Color expense = Color(0xFFB71C1C);
}

/// Lista de movimientos con acceso al formulario y al detalle.
///
/// [header] se muestra arriba de la lista (la pantalla principal pone ahí
/// el balance del mes). [onChanged] se llama después de crear, editar o
/// eliminar, para que quien la contiene se refresque de inmediato
/// (RF-10, RNF-08).
class MovementListScreen extends StatefulWidget {
  const MovementListScreen({
    super.key,
    required this.service,
    required this.catalog,
    this.header,
    this.onChanged,
    this.receipts,
    this.camera,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final Widget? header;
  final VoidCallback? onChanged;

  /// Recibos y cámara (M-04), para el formulario y el detalle.
  final ReceiptService? receipts;
  final CameraService? camera;

  @override
  State<MovementListScreen> createState() => _MovementListScreenState();
}

class _MovementListScreenState extends State<MovementListScreen> {
  List<MovementItem> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = result.valueOrNull ?? const [];
      _error = result.errorOrNull?.message;
    });
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MovementFormScreen(
          service: widget.service,
          catalog: widget.catalog,
          receipts: widget.receipts,
          camera: widget.camera,
        ),
      ),
    );
    if (saved != true || !mounted) return;
    _showMessage('Movimiento guardado.');
    await _refresh();
  }

  /// Abre el detalle. Al regresar siempre refresca la lista y avisa a
  /// [MovementListScreen.onChanged], porque pudo haber una edición o una
  /// baja (CA-016, CA-021).
  Future<void> _openDetail(MovementItem item) async {
    final result = await Navigator.of(context).push<MovementDetailResult>(
      MaterialPageRoute(
        builder: (_) => MovementDetailScreen(
          service: widget.service,
          catalog: widget.catalog,
          movement: item,
          receipts: widget.receipts,
          camera: widget.camera,
        ),
      ),
    );
    if (!mounted) return;
    if (result == MovementDetailResult.deleted) {
      _showMessage('Movimiento eliminado.');
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    widget.onChanged?.call();
    await _load();
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final showFab = !_loading && _error == null && _items.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Movimientos')),
      body: SafeArea(child: _body()),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('Registrar'),
            )
          : null,
    );
  }

  /// Todo va en una sola lista desplazable: el encabezado arriba y debajo
  /// los movimientos o el estado (cargando, error o vacío).
  Widget _body() {
    final header = widget.header;
    final offset = header == null ? 0 : 1;
    final showItems = !_loading && _error == null && _items.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: offset + (showItems ? _items.length : 1),
      itemBuilder: (_, i) {
        if (i < offset) return header!;
        if (!showItems) return _state();
        final item = _items[i - offset];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > offset) const Divider(height: 1),
            MovementTile(item: item, onTap: () => _openDetail(item)),
          ],
        );
      },
    );
  }

  Widget _state() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        title: 'No se pudo cargar la lista',
        text: _error!,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    if (_items.isEmpty) {
      return _CenteredMessage(
        icon: Icons.receipt_long,
        title: 'Aún no tienes movimientos',
        text: 'Registra tu primer ingreso o egreso para verlo aquí.',
        actionLabel: 'Registrar mi primer movimiento',
        onAction: _openForm,
      );
    }
    return const SizedBox.shrink();
  }
}

/// Mensaje centrado con un botón (lista vacía o error, CA-013).
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(title,
                style: textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un renglón de la lista. Todo va en columna para que con texto al 200 %
/// nada se corte (RNF-06). Al tocarlo abre el detalle.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.item, this.onTap});

  final MovementItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        item.isIncome ? MovementColors.income : MovementColors.expense;
    final typeLabel = item.isIncome ? 'Ingreso' : 'Egreso';
    return Semantics(
      label: '$typeLabel de ${item.formattedAmount}, ${item.categoryName}, '
          '${item.formattedDate}',
      hint: onTap == null ? null : 'Toca para ver, editar o eliminar',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(onTap: onTap, child: _content(context, color, typeLabel)),
    );
  }

  Widget _content(BuildContext context, Color color, String typeLabel) {
    final sign = item.isIncome ? '+' : '−';
    final textTheme = Theme.of(context).textTheme;
    final description = item.description;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.categoryName, style: textTheme.titleMedium),
                Text(
                  '$sign${item.formattedAmount}',
                  style: textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('$typeLabel · ${item.formattedDate}'),
                if (description != null) Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
