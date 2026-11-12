/// M-01 · Lista de movimientos (RF-07, RF-54; CA-012 a CA-015) con acceso
/// al detalle para editar o eliminar (RF-08, RF-09).
///
/// Con M-06 agrega búsqueda y filtros con conteo y suma de resultados
/// (RF-32 a RF-35; CA-083 a CA-094).
///
/// Solo usa servicios de `lib/modules/`; nunca `lib/data/` (RNF-30).
library;

import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import '../../modules/search/movement_filter.dart';
import '../widgets/filter_bar.dart';
import 'movement_detail_screen.dart';
import 'movement_form_screen.dart';
import 'ocr_review_screen.dart';
import 'scan_screen.dart';

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
    this.actions = const [],
    this.filter,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final Widget? header;
  final VoidCallback? onChanged;

  /// Recibos y cámara (M-04), para el formulario y el detalle.
  final ReceiptService? receipts;
  final CameraService? camera;

  /// Botones extra de la barra superior (por ejemplo, "Resumen anual").
  final List<Widget> actions;

  /// Búsqueda y filtros (M-06). Sin él no se muestra la barra de filtros.
  final MovementFilter? filter;

  @override
  State<MovementListScreen> createState() => _MovementListScreenState();
}

class _MovementListScreenState extends State<MovementListScreen> {
  List<MovementItem> _items = const [];
  bool _loading = true;
  String? _error;

  MovementCriteria _criteria = const MovementCriteria();
  FilterResult? _result;
  String? _filterWarning;
  List<CategoryOption> _categories = const [];

  /// Cuenta las consultas para que una respuesta vieja (por ejemplo, al
  /// escribir rápido en la búsqueda) no pise a una nueva.
  int _request = 0;

  bool get _filtering => widget.filter != null && !_criteria.isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.filter != null) _loadCategories();
  }

  Future<void> _loadCategories() async {
    final egresos = await widget.catalog.forType(MovementType.egreso);
    final ingresos = await widget.catalog.forType(MovementType.ingreso);
    if (!mounted) return;
    setState(() => _categories = [
          ...?egresos.valueOrNull,
          ...?ingresos.valueOrNull,
        ]);
  }

  Future<void> _load() async {
    final filter = widget.filter;
    if (filter != null && !_criteria.isEmpty) return _applyFilter(filter);
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.service.list();
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _items = result.valueOrNull ?? const [];
      _error = result.errorOrNull?.message;
      _result = null;
      _filterWarning = null;
    });
  }

  /// Aplica los filtros. Si el rango de fechas no es válido, avisa y deja
  /// la lista como estaba (CA-084).
  Future<void> _applyFilter(MovementFilter filter) async {
    final request = ++_request;
    final result = await filter.apply(_criteria);
    if (!mounted || request != _request) return;
    final error = result.errorOrNull;
    setState(() {
      _loading = false;
      if (error != null && error.type == ErrorType.validation) {
        _filterWarning = error.message;
        return;
      }
      _filterWarning = null;
      _error = error?.message;
      _result = result.valueOrNull;
      _items = _result?.items ?? const [];
    });
  }

  void _changeCriteria(MovementCriteria criteria) {
    setState(() => _criteria = criteria);
    _load();
  }

  void _clearFilters() => _changeCriteria(const MovementCriteria());

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

  bool get _canScan => widget.receipts != null && widget.camera != null;

  /// "Escanear recibo": cámara, lectura OCR y revisión (RF-23 a RF-26). Si
  /// no se leyó (cancelar, error o ilegible) se abre el registro manual con
  /// la foto adjunta (CA-075, CA-077 a CA-080).
  Future<void> _scanReceipt() async {
    final receipts = widget.receipts!;
    final camera = widget.camera!;
    final outcome = await Navigator.of(context).push<ScanOutcome>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          camera: camera,
          receipts: receipts,
          readReceipt: true,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _afterScan(outcome)),
    );
    if (saved != true || !mounted) return;
    _showMessage('Movimiento guardado.');
    await _refresh();
  }

  Widget _afterScan(ScanOutcome outcome) {
    final reading = outcome.reading;
    if (reading != null) {
      return OcrReviewScreen(
        service: widget.service,
        catalog: widget.catalog,
        receipts: widget.receipts,
        camera: widget.camera,
        photo: outcome.photo,
        reading: reading,
      );
    }
    return MovementFormScreen(
      service: widget.service,
      catalog: widget.catalog,
      receipts: widget.receipts,
      camera: widget.camera,
      initialReceipt: outcome.photo,
    );
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
    final showFab =
        !_loading && _error == null && (_items.isNotEmpty || _filtering);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        actions: [
          if (_canScan)
            IconButton(
              onPressed: _scanReceipt,
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Escanear recibo',
            ),
          ...widget.actions,
        ],
      ),
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
    final headers = _headers();
    final offset = headers.length;
    final showItems = !_loading && _error == null && _items.isNotEmpty;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: offset + (showItems ? _items.length : 1),
      itemBuilder: (_, i) {
        if (i < offset) return headers[i];
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

  /// Encabezado, barra de filtros (si hay movimientos o filtros activos),
  /// aviso de rango inválido y conteo con suma (RF-34).
  List<Widget> _headers() {
    final header = widget.header;
    final showBar = widget.filter != null && (_filtering || _items.isNotEmpty);
    final warning = _filterWarning;
    final result = _result;
    return [
      if (header != null) header,
      if (showBar)
        FilterBar(
          criteria: _criteria,
          categories: _categories,
          onChanged: _changeCriteria,
        ),
      if (warning != null) _FilterNotice(text: warning, isWarning: true),
      if (_filtering && result != null && warning == null)
        _FilterNotice(text: '${result.countLabel} · ${result.sumLabel}'),
    ];
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
    if (_items.isEmpty && _filtering) {
      return _CenteredMessage(
        icon: Icons.search_off,
        title: 'Sin resultados',
        text: 'Ningún movimiento cumple los filtros o la búsqueda.',
        actionLabel: 'Limpiar filtros',
        onAction: _clearFilters,
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

/// Conteo y suma de resultados, o aviso de filtro no válido.
class _FilterNotice extends StatelessWidget {
  const _FilterNotice({required this.text, this.isWarning = false});

  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isWarning ? colors.error : null,
              ),
        ),
      ),
    );
  }
}
