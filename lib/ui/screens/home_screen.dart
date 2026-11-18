/// M-01 · Pantalla de inicio: saludo, tarjeta con el balance del mes en
/// curso, accesos rápidos y debajo la lista de movimientos (RF-10, RNF-08;
/// CA-025 a CA-028). Diseño tomado del prototipo (tarjeta azul marino).
///
/// Solo usa los servicios de M-02 y M-03; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';

import '../../modules/budgets/budget_service.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/export/export_service.dart';
import '../../modules/insights/insights_service.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import '../../modules/search/movement_filter.dart';
import '../../modules/security/lock_controller.dart';
import '../../modules/summary/summary_service.dart';
import '../theme/spendy_theme.dart';
import '../widgets/budget_cards.dart';
import 'budget_screen.dart';
import 'movement_list_screen.dart';

/// Pantalla principal. El balance se vuelve a calcular cada vez que la
/// lista avisa que se creó, editó o eliminó un movimiento (CA-001, CA-007,
/// CA-016, CA-021).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.service,
    required this.catalog,
    this.receipts,
    this.camera,
    this.summary,
    this.exports,
    this.filter,
    this.lock,
    this.budgets,
    this.insights,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final ReceiptService? receipts;
  final CameraService? camera;

  /// Resumen anual y exportación (incremento 5).
  final SummaryService? summary;
  final ExportService? exports;

  /// Búsqueda y filtros (incremento 6).
  final MovementFilter? filter;

  /// Configuración del PIN y la biometría (incremento 7).
  final LockController? lock;

  /// Presupuestos por categoría (M-14).
  final BudgetService? budgets;

  /// Indicadores del mes (M-15).
  final InsightsService? insights;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

/// Estado público para que la barra inferior pueda iniciar el escaneo.
class HomeScreenState extends State<HomeScreen> {
  final GlobalKey<MovementListScreenState> _list = GlobalKey();
  MonthlyBalance? _balance;
  String? _error;
  BudgetOverview? _budgets;
  MonthInsights? _insights;

  /// Estado de cada presupuesto en la lectura anterior, para avisar solo
  /// cuando cambia a "cerca del límite" o "excedido".
  Map<int, BudgetStatus>? _lastStatus;

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
    final budgets = await widget.budgets?.currentMonth();
    final insights = await widget.insights?.currentMonth();
    if (!mounted || request != _request) return;
    final overview = budgets?.valueOrNull;
    setState(() {
      _balance = result.valueOrNull;
      _error = result.errorOrNull?.message;
      _budgets = overview;
      _insights = insights?.valueOrNull;
    });
    if (overview != null) _alertBudgets(overview);
  }

  /// Avisa con un mensaje cuando un presupuesto llega al 80 % o se pasa
  /// por un movimiento que se acaba de guardar.
  void _alertBudgets(BudgetOverview overview) {
    final previous = _lastStatus;
    _lastStatus = {for (final l in overview.lines) l.categoryId: l.status};
    if (previous == null) return;
    for (final line in overview.lines) {
      final before = previous[line.categoryId] ?? BudgetStatus.ok;
      if (line.status.index <= before.index) continue;
      final percent = (line.ratio * 100).round();
      final text = line.status == BudgetStatus.exceeded
          ? 'Te pasaste del presupuesto de ${line.categoryName}: '
              '${budgetLineText(line).toLowerCase()}.'
          : 'Ya usaste el $percent % del presupuesto de '
              '${line.categoryName}.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text),
          backgroundColor: budgetColor(context, line.status),
        ));
      return;
    }
  }

  Future<void> _editBudgets() async {
    final budgets = widget.budgets;
    if (budgets == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BudgetScreen(budgets: budgets, catalog: widget.catalog),
      ),
    );
    if (saved == true) {
      _lastStatus = null; // un límite nuevo no debe disparar avisos
      await _loadBalance();
    }
  }

  /// "Escanear recibo" desde la barra inferior.
  Future<void> scanReceipt() async => _list.currentState?.scanReceipt();

  Widget _header() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BalanceCard(balance: _balance, error: _error),
          QuickActions(
            onIncome: () => _list.currentState?.openForm(MovementType.ingreso),
            onExpense: () => _list.currentState?.openForm(MovementType.egreso),
            onScan: widget.receipts != null && widget.camera != null
                ? scanReceipt
                : null,
          ),
          if (_insights case final insights?) InsightsCard(insights: insights),
          if (_budgets case final budgets?)
            BudgetsCard(overview: budgets, onEdit: _editBudgets),
          const _SectionTitle('Movimientos recientes'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return MovementListScreen(
      key: _list,
      title: const _Greeting(),
      service: widget.service,
      catalog: widget.catalog,
      header: _header(),
      onChanged: _loadBalance,
      receipts: widget.receipts,
      camera: widget.camera,
      filter: widget.filter,
    );
  }
}

/// Fecha de hoy y saludo, como encabezado de la pantalla de inicio.
class _Greeting extends StatelessWidget {
  const _Greeting();

  static const List<String> _days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = CalendarMonth(now.year, now.month).label.split(' ').first;
    final date = '${_days[now.weekday - 1]} ${now.day} de '
        '${month.toLowerCase()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          date,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SpendyPalette.of(context).muted,
              ),
        ),
        const Text('Hola'),
      ],
    );
  }
}

/// Título de sección.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Semantics(
          header: true,
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
}

/// Tarjeta azul marino con el balance del mes, sus ingresos y egresos y un
/// botón para ocultar los montos. Mientras carga muestra un indicador; si
/// la lectura falla, el mensaje no técnico de M-13.
class BalanceCard extends StatefulWidget {
  const BalanceCard({super.key, required this.balance, this.error});

  final MonthlyBalance? balance;
  final String? error;

  @override
  State<BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<BalanceCard> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: SpendyPalette.navyGradient,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x5515294D),
            blurRadius: 32,
            offset: Offset(0, 16),
            spreadRadius: -12,
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: SpendyPalette.onNavy),
        child: IconTheme.merge(
          data: const IconThemeData(color: SpendyPalette.onNavy),
          child: _content(context),
        ),
      ),
    );
  }

  Widget _titleRow(String title) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          IconButton(
            onPressed: () => setState(() => _hidden = !_hidden),
            icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility),
            tooltip: _hidden ? 'Mostrar montos' : 'Ocultar montos',
          ),
        ],
      );

  Widget _content(BuildContext context) {
    final value = widget.balance;
    if (widget.error != null) return Text(widget.error!);
    if (value == null) {
      return const Center(
        child: CircularProgressIndicator(color: SpendyPalette.onNavy),
      );
    }
    final title = 'Balance de ${value.month.label}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _titleRow(title),
        Semantics(
          label:
              _hidden ? '$title: oculto' : '$title: ${value.formattedBalance}',
          excludeSemantics: true,
          child: Text(
            _hidden ? r'$ •••••' : value.formattedBalance,
            key: const Key('month_balance'),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: SpendyPalette.onNavy,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MiniTotal(
              label: 'Ingresos',
              cents: value.incomeCents,
              hidden: _hidden,
              isIncome: true,
            ),
            _MiniTotal(
              label: 'Egresos',
              cents: value.expenseCents,
              hidden: _hidden,
              isIncome: false,
            ),
          ],
        ),
      ],
    );
  }
}

/// Recuadro de ingresos o egresos dentro de la tarjeta de saldo.
class _MiniTotal extends StatelessWidget {
  const _MiniTotal({
    required this.label,
    required this.cents,
    required this.hidden,
    required this.isIncome,
  });

  final String label;
  final int cents;
  final bool hidden;
  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final accent =
        isIncome ? SpendyPalette.incomeOnNavy : SpendyPalette.expenseOnNavy;
    final amount = hidden ? r'$ •••' : formatCents(cents);
    return Semantics(
      label: '$label del mes: ${hidden ? 'oculto' : amount}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 130),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isIncome
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  size: 16,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accesos rápidos: registrar ingreso o egreso y escanear un recibo.
class QuickActions extends StatelessWidget {
  const QuickActions({
    super.key,
    required this.onIncome,
    required this.onExpense,
    this.onScan,
  });

  final VoidCallback onIncome;
  final VoidCallback onExpense;

  /// Sin cámara ni recibos (pruebas) no se muestra.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final palette = SpendyPalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final scan = onScan;
    final tiles = [
      _QuickAction(
        label: 'Ingreso',
        icon: Icons.south_west_rounded,
        color: palette.income,
        background: palette.incomeSoft,
        onTap: onIncome,
      ),
      _QuickAction(
        label: 'Egreso',
        icon: Icons.north_east_rounded,
        color: palette.expense,
        background: palette.expenseSoft,
        onTap: onExpense,
      ),
      if (scan != null)
        _QuickAction(
          label: 'Escanear',
          icon: Icons.document_scanner_outlined,
          color: colors.onSurface,
          background: colors.surfaceContainerHighest,
          onTap: scan,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: background),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
