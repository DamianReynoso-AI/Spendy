/// M-01 · Tarjetas de la pantalla de inicio: indicadores del mes (M-15) y
/// avance de los presupuestos (M-14).
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../modules/budgets/budget_service.dart';
import '../../modules/insights/insights_service.dart';
import '../theme/spendy_theme.dart';

/// Color de la barra según el avance.
Color budgetColor(BuildContext context, BudgetStatus status) {
  final palette = SpendyPalette.of(context);
  return switch (status) {
    BudgetStatus.ok => palette.income,
    BudgetStatus.warning => const Color(0xFFE0A100),
    BudgetStatus.exceeded => palette.expense,
  };
}

/// Texto corto del avance de un presupuesto.
String budgetLineText(BudgetLine line) => line.status == BudgetStatus.exceeded
    ? 'Te pasaste por ${formatCents(-line.remainingCents)}'
    : 'Quedan ${formatCents(line.remainingCents)}';

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: child,
        ),
      );
}

/// "Tu mes": gasto contra el mismo avance del mes pasado, categoría con
/// más gasto y proyección al cierre.
class InsightsCard extends StatelessWidget {
  const InsightsCard({super.key, required this.insights});

  final MonthInsights insights;

  /// Renglón de la comparación contra el mes pasado.
  static _InsightRow _changeRow(int change, SpendyPalette palette) {
    if (change == 0) {
      return _InsightRow(
        icon: Icons.trending_flat,
        color: palette.muted,
        text: 'Vas igual que a estas alturas del mes pasado.',
      );
    }
    final up = change > 0;
    return _InsightRow(
      icon: up ? Icons.trending_up : Icons.trending_down,
      color: up ? palette.expense : palette.income,
      text: 'Gastas ${change.abs()} % ${up ? 'más' : 'menos'} que a estas '
          'alturas del mes pasado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SpendyPalette.of(context);
    final change = insights.changePercent;
    final rows = <Widget>[if (change != null) _changeRow(change, palette)];
    if (insights.topCategoryName case final top?) {
      rows.add(_InsightRow(
        icon: Icons.local_fire_department_outlined,
        color: palette.expense,
        text: 'Donde más gastas: $top '
            '(${formatCents(insights.topCategoryCents)}).',
      ));
    }
    if (insights.hasExpenses) {
      rows.add(_InsightRow(
        icon: Icons.insights_outlined,
        color: theme.colorScheme.primary,
        text: 'A este ritmo (${formatCents(insights.dailyAverageCents)} al '
            'día) cerrarías el mes en ${formatCents(insights.projectedCents)}.',
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return _CardShell(
      child: Column(
        key: const Key('insights_card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text('Tu mes',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// Presupuestos del mes con su barra de avance. Sin presupuestos muestra
/// una invitación a crearlos.
class BudgetsCard extends StatelessWidget {
  const BudgetsCard({super.key, required this.overview, required this.onEdit});

  final BudgetOverview overview;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              'Presupuestos de ${overview.month.label.split(' ').first}',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        TextButton(
          key: const Key('edit_budgets'),
          onPressed: onEdit,
          child: Text(overview.isEmpty ? 'Crear' : 'Editar'),
        ),
      ],
    );
    if (overview.isEmpty) {
      return _CardShell(
        child: Column(
          key: const Key('budgets_card'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(
              'Define cuánto quieres gastar al mes por categoría y te avisamos '
              'cuando te acerques al límite.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: SpendyPalette.of(context).muted),
            ),
          ],
        ),
      );
    }
    return _CardShell(
      child: Column(
        key: const Key('budgets_card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          for (final line in overview.lines) BudgetBar(line: line),
        ],
      ),
    );
  }
}

/// Una categoría: nombre, "gastado de límite" y barra de avance.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.line});

  final BudgetLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = budgetColor(context, line.status);
    final percent = (line.ratio * 100).round();
    final amounts =
        '${formatCents(line.spentCents)} de ${formatCents(line.limitCents)}';
    final ok = line.status == BudgetStatus.ok;
    return Semantics(
      label: '${line.categoryName}: $amounts, $percent por ciento. '
          '${budgetLineText(line)}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(line.categoryName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(amounts, style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: line.ratio.clamp(0, 1).toDouble(),
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              budgetLineText(line),
              style: theme.textTheme.bodySmall?.copyWith(
                color: ok ? SpendyPalette.of(context).muted : color,
                fontWeight: ok ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
