/// M-01 · Gráfica de dona (por ejemplo, egresos por categoría). Es solo
/// visual: los mismos datos van en texto junto a ella para lectores de
/// pantalla (RNF-06).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un segmento de la dona.
class DonutSlice {
  const DonutSlice(this.value, this.color);

  final double value;
  final Color color;
}

/// Dona con [slices] y [center] en medio.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.center,
    this.size = 200,
    this.thickness = 26,
    this.emptyColor,
  });

  final List<DonutSlice> slices;
  final Widget? center;
  final double size;
  final double thickness;

  /// Color del anillo cuando no hay datos.
  final Color? emptyColor;

  @override
  Widget build(BuildContext context) {
    final empty =
        emptyColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _DonutPainter(slices, thickness, empty),
          child: center == null
              ? null
              : Center(
                  child: Padding(
                    padding: EdgeInsets.all(thickness + 8),
                    child: FittedBox(fit: BoxFit.scaleDown, child: center),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.thickness, this.empty);

  final List<DonutSlice> slices;
  final double thickness;
  final Color empty;

  /// Separación entre segmentos, en radianes.
  static const double _gap = 0.04;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(thickness / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    final total =
        slices.fold<double>(0, (sum, s) => sum + math.max(0, s.value));
    if (total <= 0) {
      canvas.drawArc(arc, 0, 2 * math.pi, false, paint..color = empty);
      return;
    }
    final visible = slices.where((s) => s.value > 0).toList();
    final gap = visible.length > 1 ? _gap : 0.0;
    var start = -math.pi / 2;
    for (final slice in visible) {
      final sweep = 2 * math.pi * slice.value / total;
      final drawn = math.max(0.0, sweep - gap);
      canvas.drawArc(
          arc, start + gap / 2, drawn, false, paint..color = slice.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.slices != slices || old.thickness != thickness || old.empty != empty;
}
