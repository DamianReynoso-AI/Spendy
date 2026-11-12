/// M-01 · Resumen anual y exportación (RF-36 a RF-44; CA-095 a CA-113).
///
/// Selector de años, tarjetas de totales, lista de gastos por categoría
/// (sin gráficas, sección 4) y botones para exportar a CSV y PDF. Se
/// vuelve a calcular cada vez que la pantalla queda activa de nuevo
/// (CA-100, CA-104). Solo usa M-07 y M-08; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/export/export_service.dart';
import '../../modules/summary/summary_service.dart';

/// Observador de rutas de la app: avisa al resumen cuando vuelve a quedar
/// arriba de la pila.
final RouteObserver<ModalRoute<void>> spendyRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Pantalla del resumen anual.
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({
    super.key,
    required this.summary,
    required this.exports,
  });

  final SummaryService summary;
  final ExportService exports;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen>
    with RouteAware, WidgetsBindingObserver {
  YearOptions? _years;
  int? _year;
  AnnualSummary? _summary;
  String? _error;
  String? _exportError;
  ExportFormat? _lastFormat;
  bool _exporting = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) spendyRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    spendyRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Volvió a quedar arriba (por ejemplo, tras editar un movimiento).
  @override
  void didPopNext() => _load();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  /// Lee los años y el resumen del año elegido (el actual la primera vez).
  Future<void> _load() async {
    final request = ++_request;
    final years = await widget.summary.yearOptions();
    if (!mounted || request != _request) return;
    if (years case Failure(:final error)) {
      return setState(() => _error = error.message);
    }
    final options = years.valueOrNull!;
    final year = _year ?? options.selected;
    final summary = await widget.summary.summaryFor(year);
    if (!mounted || request != _request) return;
    setState(() {
      _years = options;
      _year = year;
      _summary = summary.valueOrNull;
      _error = summary.errorOrNull?.message;
    });
  }

  void _selectYear(int? year) {
    if (year == null || year == _year) return;
    setState(() {
      _year = year;
      _summary = null;
      _exportError = null;
    });
    _load();
  }

  Future<void> _export(ExportFormat format) async {
    final summary = _summary;
    if (summary == null || _exporting) return;
    setState(() {
      _exporting = true;
      _exportError = null;
      _lastFormat = format;
    });
    final result = await widget.exports.export(summary, format);
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _exportError = result.errorOrNull?.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resumen anual')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final error = _error;
    if (error != null) {
      return _Message(text: error, actionLabel: 'Reintentar', onAction: _load);
    }
    final years = _years;
    final summary = _summary;
    if (years == null || summary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _yearSelector(years),
        const SizedBox(height: 16),
        if (!summary.hasMovements)
          _Message(text: 'No hay movimientos registrados en ${summary.year}.')
        else ...[
          ..._totals(summary),
          const SizedBox(height: 16),
          _categories(summary),
          const SizedBox(height: 16),
          ..._exportButtons(),
        ],
      ],
    );
  }

  Widget _yearSelector(YearOptions years) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Año',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _year,
          isExpanded: true,
          isDense: true,
          items: [
            for (final year in years.years)
              DropdownMenuItem(value: year, child: Text('$year')),
          ],
          onChanged: _selectYear,
        ),
      ),
    );
  }

  List<Widget> _totals(AnnualSummary summary) => [
        _TotalCard(label: 'Ingresos del año', value: summary.formattedIncome),
        _TotalCard(label: 'Egresos del año', value: summary.formattedExpense),
        _TotalCard(
          label: 'Diferencia (ingresos - egresos)',
          value: summary.formattedDifference,
        ),
      ];

  Widget _categories(AnnualSummary summary) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Gastos por categoría',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final total in summary.byCategory)
            ListTile(
              title: Text(total.name),
              trailing: Text(total.formatted),
            ),
        ],
      ),
    );
  }

  List<Widget> _exportButtons() {
    final exportError = _exportError;
    return [
      if (exportError != null)
        _Message(
          text: exportError,
          actionLabel: 'Reintentar',
          onAction: () => _export(_lastFormat ?? ExportFormat.csv),
        ),
      for (final format in ExportFormat.values) ...[
        OutlinedButton.icon(
          onPressed: _exporting ? null : () => _export(format),
          icon: const Icon(Icons.ios_share),
          label: Text('Exportar ${format.extension.toUpperCase()}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (_exporting) const LinearProgressIndicator(),
    ];
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Aviso informativo o de error, con botón opcional.
class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
