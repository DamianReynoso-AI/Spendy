/// M-01 · Lista de movimientos (RF-07, RF-54; CA-012 a CA-015).
///
/// Solo usa los servicios de M-02 y M-03; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
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

/// Pantalla principal del incremento 1: lista y acceso al formulario.
class MovementListScreen extends StatefulWidget {
  const MovementListScreen({
    super.key,
    required this.service,
    required this.catalog,
  });

  final MovementService service;
  final CategoryCatalog catalog;

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
        ),
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento guardado.')),
    );
    await _load();
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

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => MovementTile(item: _items[i]),
    );
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64),
            const SizedBox(height: 16),
            Text(title, style: textTheme.titleLarge, textAlign: TextAlign.center),
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
/// nada se corte (RNF-06).
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.item});

  final MovementItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isIncome ? MovementColors.income : MovementColors.expense;
    final typeLabel = item.isIncome ? 'Ingreso' : 'Egreso';
    final sign = item.isIncome ? '+' : '−';
    final textTheme = Theme.of(context).textTheme;
    final description = item.description;
    return Semantics(
      label: '$typeLabel de ${item.formattedAmount}, ${item.categoryName}, '
          '${item.formattedDate}',
      excludeSemantics: true,
      child: Padding(
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
      ),
    );
  }
}
