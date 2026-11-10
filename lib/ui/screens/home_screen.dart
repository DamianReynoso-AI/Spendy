/// M-01 · Pantalla principal: balance del mes en curso arriba de la lista
/// de movimientos (RF-10, RNF-08; CA-025 a CA-028).
///
/// Solo usa los servicios de M-02 y M-03; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import 'movement_list_screen.dart';

/// Pantalla principal. El balance se vuelve a calcular cada vez que la
/// lista avisa que se creó, editó o eliminó un movimiento (CA-001, CA-007,
/// CA-016, CA-021).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service, required this.catalog});

  final MovementService service;
  final CategoryCatalog catalog;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MonthlyBalance? _balance;
  String? _error;

  /// Cuenta las peticiones para que una respuesta vieja no pise a una
  /// nueva si llegan en otro orden.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final request = ++_request;
    final result = await widget.service.currentMonthBalance();
    if (!mounted || request != _request) return;
    setState(() {
      _balance = result.valueOrNull;
      _error = result.errorOrNull?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MovementListScreen(
      service: widget.service,
      catalog: widget.catalog,
      header: BalanceCard(balance: _balance, error: _error),
      onChanged: _loadBalance,
    );
  }
}

/// Tarjeta con el balance del mes. Mientras carga muestra un indicador;
/// si la lectura falla, el mensaje no técnico de M-13.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance, this.error});

  final MonthlyBalance? balance;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = balance;
    if (error != null) {
      return Text(error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error));
    }
    if (value == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final color =
        value.isNegative ? MovementColors.expense : MovementColors.income;
    final title = 'Balance de ${value.month.label}';
    return Semantics(
      label: '$title: ${value.formattedBalance}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            value.formattedBalance,
            style: textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('Ingresos menos egresos del mes'),
        ],
      ),
    );
  }
}
