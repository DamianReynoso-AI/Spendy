/// M-01 · Estructura principal con barra inferior, como en el prototipo:
/// Inicio, Movimientos, Escanear (botón central), Resumen y Ajustes.
///
/// Solo se construye la pestaña activa: al volver a Inicio se recalcula el
/// balance con lo que se haya cambiado en otra pestaña (RF-10).
library;

import 'package:flutter/material.dart';

import '../../modules/backup/backup_service.dart';
import '../../modules/budgets/budget_service.dart';
import '../../modules/categories/category_catalog.dart';
import '../../modules/export/export_service.dart';
import '../../modules/insights/insights_service.dart';
import '../../modules/movements/movement_service.dart';
import '../../modules/ocr/ocr_key_service.dart';
import '../../modules/receipts/camera_service.dart';
import '../../modules/receipts/receipt_service.dart';
import '../../modules/search/movement_filter.dart';
import '../../modules/security/lock_controller.dart';
import '../../modules/summary/summary_service.dart';
import '../theme/spendy_theme.dart';
import 'home_screen.dart';
import 'movement_list_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

enum _Tab { home, movements, summary, settings }

/// Pantalla raíz con la barra inferior.
class SpendyShell extends StatefulWidget {
  const SpendyShell({
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
    this.backup,
    this.ocrKey,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final ReceiptService? receipts;
  final CameraService? camera;
  final SummaryService? summary;
  final ExportService? exports;
  final MovementFilter? filter;
  final LockController? lock;
  final BudgetService? budgets;
  final InsightsService? insights;
  final BackupService? backup;
  final OcrKeyService? ocrKey;

  @override
  State<SpendyShell> createState() => _SpendyShellState();
}

class _SpendyShellState extends State<SpendyShell> {
  final GlobalKey<HomeScreenState> _home = GlobalKey();
  _Tab _tab = _Tab.home;

  bool get _canScan => widget.receipts != null && widget.camera != null;
  bool get _hasSummary => widget.summary != null && widget.exports != null;

  /// El botón central abre el escaneo desde Inicio, que al terminar
  /// refresca el balance y la lista.
  Future<void> _scan() async {
    if (_tab != _Tab.home) {
      setState(() => _tab = _Tab.home);
      await WidgetsBinding.instance.endOfFrame;
    }
    await _home.currentState?.scanReceipt();
  }

  Widget _page() => switch (_tab) {
        _Tab.home => HomeScreen(
            key: _home,
            service: widget.service,
            catalog: widget.catalog,
            receipts: widget.receipts,
            camera: widget.camera,
            summary: widget.summary,
            exports: widget.exports,
            filter: widget.filter,
            lock: widget.lock,
            budgets: widget.budgets,
            insights: widget.insights,
          ),
        _Tab.movements => MovementListScreen(
            service: widget.service,
            catalog: widget.catalog,
            receipts: widget.receipts,
            camera: widget.camera,
            filter: widget.filter,
          ),
        _Tab.summary => SummaryScreen(
            summary: widget.summary!,
            exports: widget.exports!,
          ),
        _Tab.settings => SettingsScreen(
            lock: widget.lock!,
            ocrKey: widget.ocrKey,
            backup: widget.backup,
            budgets: widget.budgets,
            catalog: widget.catalog,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _page(),
      bottomNavigationBar: SpendyBottomBar(
        items: [
          _item(_Tab.home, 'Inicio', Icons.home_outlined, Icons.home_rounded),
          _item(_Tab.movements, 'Movimientos', Icons.receipt_long_outlined,
              Icons.receipt_long),
          if (_canScan)
            BottomBarItem(
              label: 'Escanear',
              icon: Icons.document_scanner_outlined,
              selected: false,
              onTap: _scan,
              center: true,
            ),
          if (_hasSummary)
            _item(_Tab.summary, 'Resumen', Icons.pie_chart_outline,
                Icons.pie_chart,
                tooltip: 'Resumen anual'),
          if (widget.lock != null)
            _item(_Tab.settings, 'Ajustes', Icons.settings_outlined,
                Icons.settings,
                tooltip: 'Configuración'),
        ],
      ),
    );
  }

  BottomBarItem _item(
    _Tab tab,
    String label,
    IconData icon,
    IconData active, {
    String? tooltip,
  }) =>
      BottomBarItem(
        label: label,
        icon: _tab == tab ? active : icon,
        selected: _tab == tab,
        tooltip: tooltip,
        onTap: () => setState(() => _tab = tab),
      );
}

/// Un botón de la barra inferior.
class BottomBarItem {
  const BottomBarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.center = false,
    this.tooltip,
  });

  final String label;

  /// Texto de ayuda al mantener presionado (nombre completo).
  final String? tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  /// Botón central redondo y azul marino (Escanear).
  final bool center;
}

/// Barra inferior. Las etiquetas se reducen si no caben con texto grande,
/// en vez de cortarse (RNF-06); cada botón mide al menos 48 × 48.
class SpendyBottomBar extends StatelessWidget {
  const SpendyBottomBar({super.key, required this.items});

  final List<BottomBarItem> items;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final item in items)
                Expanded(
                  child: item.center ? _CenterButton(item) : _BarButton(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton(this.item);

  final BottomBarItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color =
        item.selected ? colors.primary : SpendyPalette.of(context).muted;
    final button = Semantics(
      selected: item.selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 30,
                decoration: BoxDecoration(
                  color: item.selected
                      ? colors.surfaceContainerHighest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(item.icon, color: color, size: 24),
              ),
              const SizedBox(height: 2),
              _Label(item.label, color: color, bold: item.selected),
            ],
          ),
        ),
      ),
    );
    final tooltip = item.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton(this.item);

  final BottomBarItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Escanear recibo',
      excludeSemantics: true,
      child: InkWell(
        onTap: item.onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: SpendyPalette.navyGradient,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x5515294D),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                    spreadRadius: -6,
                  ),
                ],
              ),
              child: Icon(item.icon, color: SpendyPalette.onNavy, size: 28),
            ),
            const SizedBox(height: 2),
            _Label(item.label, color: SpendyPalette.of(context).muted),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.color, this.bold = false});

  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
}
