/// M-05 · Reconstruye los renglones de un recibo a partir de los pedazos de
/// texto que entrega un OCR en el teléfono (RF-24).
///
/// ML Kit devuelve el texto por bloques: en un ticket, la columna de
/// conceptos ("TOTAL") y la de importes ("$39.50") suelen salir en bloques
/// distintos. El intérprete necesita "TOTAL $39.50" en el mismo renglón,
/// así que aquí se vuelven a juntar por su posición en la foto.
///
/// Es lógica pura: no usa Flutter ni ML Kit, para poder probarla.
library;

/// Un pedazo de texto leído y su caja en la foto (en píxeles).
class TextFragment {
  const TextFragment(this.text, this.left, this.top, this.right, this.bottom);

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

/// Renglón en construcción.
class _Row {
  _Row(TextFragment first)
      : top = first.top,
        bottom = first.bottom,
        fragments = [first];

  double top;
  double bottom;
  final List<TextFragment> fragments;

  /// `true` si el centro de [f] cae dentro de la franja del renglón, o la
  /// franja cae dentro de [f] (pedazos de distinta altura).
  bool accepts(TextFragment f) {
    final center = (top + bottom) / 2;
    return (f.centerY >= top && f.centerY <= bottom) ||
        (center >= f.top && center <= f.bottom);
  }

  void add(TextFragment f) {
    fragments.add(f);
    if (f.top < top) top = f.top;
    if (f.bottom > bottom) bottom = f.bottom;
  }

  String join() {
    fragments.sort((a, b) => a.left.compareTo(b.left));
    return fragments.map((f) => f.text.trim()).join(' ');
  }
}

/// Junta [fragments] en renglones de arriba a abajo y, dentro de cada uno,
/// de izquierda a derecha. Devuelve el texto con un renglón por línea.
String joinFragmentsIntoLines(List<TextFragment> fragments) {
  final sorted = fragments.where((f) => f.text.trim().isNotEmpty).toList()
    ..sort((a, b) => a.centerY.compareTo(b.centerY));
  final rows = <_Row>[];
  for (final fragment in sorted) {
    final row = rows.isEmpty ? null : rows.last;
    if (row != null && row.accepts(fragment)) {
      row.add(fragment);
    } else {
      rows.add(_Row(fragment));
    }
  }
  return rows.map((r) => r.join()).join('\n');
}
