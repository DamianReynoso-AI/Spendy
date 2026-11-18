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
import '../theme/spendy_theme.dart';
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

  /// Verde azulado del tema claro, contraste de 5.7:1 con blanco.
  static const Color income = Color(0xFF0A7368);

  /// Coral del tema claro, contraste de 5.4:1 con blanco.
  static const Color expense = Color(0xFFBF3A2B);

  /// Color de ingreso del tema actual (claro u oscuro).
  static Color incomeOf(BuildContext context) =>
      SpendyPalette.of(context).income;

  /// Color de egreso del tema actual (claro u oscuro).
  static Color expenseOf(BuildContext context) =>
      SpendyPalette.of(context).expense;
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
    this.title,
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

  /// Título de la barra superior; por defecto, "Movimientos".
  final Widget? title;

  @override
  State<MovementListScreen> createState() => MovementListScreenState();
}

/// Estado público para que la pantalla de inicio abra el formulario o el
/// escaneo desde sus accesos rápidos.
class MovementListScreenState extends State<MovementListScreen> {
  List<MovementItem> _items = const [];
  bool _loading = true;

  /// AUD-18: la lista se carga por páginas para no traer miles de
  /// movimientos de golpe.
  static const int pageSize = 200;
  bool _hasMore = false;
  bool _loadingMore = false;
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
    final result = await widget.service.list(limit: pageSize);
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      _items = result.valueOrNull ?? const [];
      _hasMore = _items.length == pageSize;
      _error = result.errorOrNull?.message;
      _result = null;
      _filterWarning = null;
    });
  }

  /// Trae la siguiente página al acercarse al final de la lista.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _filtering) return;
    _loadingMore = true;
    final request = _request;
    final result =
        await widget.service.list(limit: pageSize, offset: _items.length);
    _loadingMore = false;
    final page = result.valueOrNull;
    if (!mounted || request != _request || page == null) return;
    setState(() {
      _items = [..._items, ...page];
      _hasMore = page.length == pageSize;
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
      _hasMore = false;
    });
  }

  void _changeCriteria(MovementCriteria criteria) {
    setState(() => _criteria = criteria);
    _load();
  }

  void _clearFilters() => _changeCriteria(const MovementCriteria());

  /// Abre el formulario de registro, con [type] ya elegido si se indica.
  Future<void> openForm([MovementType? type]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MovementFormScreen(
          service: widget.service,
          catalog: widget.catalog,
          receipts: widget.receipts,
          camera: widget.camera,
          initialType: type ?? MovementType.egreso,
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

  bool get canScan => widget.receipts != null && widget.camera != null;

  /// "Escanear recibo": cámara, lectura OCR y revisión (RF-23 a RF-26). Si
  /// no se leyó (cancelar, error o ilegible) se abre el registro manual con
  /// la foto adjunta (CA-075, CA-077 a CA-080).
  Future<void> scanReceipt() async {
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
        title: widget.title ?? const Text('Movimientos'),
        actions: [
          if (canScan)
            IconButton(
              onPressed: scanReceipt,
              icon: const Icon(Icons.document_scanner_outlined),
              tooltip: 'Escanear recibo',
            ),
          ...widget.actions,
        ],
      ),
      body: SafeArea(child: _body()),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: openForm,
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
        if (i - offset >= _items.length - 20) _loadMore();
        final item = _items[i - offset];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > offset) const Divider(height: 1, indent: 74, endIndent: 16),
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
        onAction: openForm,
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

/// Un renglón de la lista: ícono del tipo, categoría, fecha y monto. Con
/// texto grande (más de 130 %) el monto baja a su propia línea para que
/// nada se corte (RNF-06). Al tocarlo abre el detalle.
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.item, this.onTap});

  final MovementItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final typeLabel = item.isIncome ? 'Ingreso' : 'Egreso';
    return Semantics(
      label: '$typeLabel de ${item.formattedAmount}, ${item.categoryName}, '
          '${item.formattedDate}',
      hint: onTap == null ? null : 'Toca para ver, editar o eliminar',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _content(context, typeLabel),
      ),
    );
  }

  Widget _content(BuildContext context, String typeLabel) {
    final palette = SpendyPalette.of(context);
    final color = item.isIncome ? palette.income : palette.expense;
    final textTheme = Theme.of(context).textTheme;
    final description = item.description;
    final amount = Text(
      '${item.isIncome ? '+' : '−'}${item.formattedAmount}',
      style: textTheme.titleMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w700),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.categoryName,
            style:
                textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text('$typeLabel · ${item.formattedDate}',
            style: textTheme.bodySmall?.copyWith(color: palette.muted)),
        if (description != null) Text(description, style: textTheme.bodyMedium),
        if (stacked) amount,
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _TypeIcon(isIncome: item.isIncome),
          const SizedBox(width: 14),
          Expanded(child: details),
          if (!stacked) ...[const SizedBox(width: 8), amount],
        ],
      ),
    );
  }
}

/// Círculo suave con la flecha del tipo de movimiento.
class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.isIncome});

  final bool isIncome;

  @override
  Widget build(BuildContext context) {
    final palette = SpendyPalette.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isIncome ? palette.incomeSoft : palette.expenseSoft,
      ),
      child: Icon(
        isIncome ? Icons.south_west_rounded : Icons.north_east_rounded,
        color: isIncome ? palette.income : palette.expense,
        size: 22,
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
