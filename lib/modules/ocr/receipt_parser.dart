/// M-05 · Interpreta el texto leído de un recibo y valida lo extraído
/// (RF-24, RF-27 a RF-29; CA-063, CA-070, CA-071, CA-073, CA-074).
///
/// Es lógica pura: no usa Flutter ni la red.
library;

import '../../config/app_config.dart';

/// Campos que se intentan leer del recibo.
enum ReceiptField { merchant, date, total }

/// Lo que se pudo leer, listo para prellenar el formulario de revisión.
class ParsedReceipt {
  const ParsedReceipt({
    this.merchant,
    required this.date,
    this.amountText,
    this.missing = const {},
    this.dateWarning = false,
    this.illegible = false,
  });

  /// Comercio, máximo 60 caracteres; `null` si no se leyó.
  final String? merchant;

  /// Fecha leída o, si no se leyó, era inválida o futura, la de hoy.
  final DateTime date;

  /// Total en el formato del campo de monto ("1234.50"); `null` si no se
  /// leyó o era inválido o ambiguo.
  final String? amountText;

  /// Campos que van vacíos y resaltados (CA-063, CA-071, CA-073).
  final Set<ReceiptField> missing;

  /// `true` si la fecha se reemplazó por la de hoy y hay que revisarla
  /// (RF-27, CA-070).
  final bool dateWarning;

  /// `true` si no se leyó ni comercio, ni fecha, ni total (RF-29, CA-074).
  final bool illegible;
}

/// Abreviaturas de los meses en español (sin acentos).
const Map<String, int> _months = {
  'ene': 1,
  'feb': 2,
  'mar': 3,
  'abr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'ago': 8,
  'sep': 9,
  'set': 9,
  'oct': 10,
  'nov': 11,
  'dic': 12,
};

final RegExp _numericDmy =
    RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})\b');
final RegExp _numericYmd = RegExp(r'\b(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})\b');
final RegExp _textMonth = RegExp(
  r'\b(\d{1,2})[\s/\-.]*(?:de\s+)?(ene|feb|mar|abr|may|jun|jul|ago|sep|set|oct|nov|dic)'
  r'[a-z]*\.?[\s/\-.,]*(?:de\s+)?(\d{4}|\d{2})\b',
);
final RegExp _totalWord = RegExp(r'\btotal\b');
final RegExp _notTotal = RegExp(r'subtotal|total\s+de\s+art|articulos|piezas');
final RegExp _amountToken = RegExp(r'\d[\d.,]*\d|\d');
final RegExp _merchantSkip = RegExp(
  r'\b(rfc|r\.f\.c|ticket|factura|folio|fecha|hora|tel|telefono|total|'
  r'caja|cajero|www|http|cliente|regimen)\b',
);
final RegExp _thousands = RegExp(r'^\d{1,3}(,\d{3})+(\.\d{2})?$');
final RegExp _plain = RegExp(r'^\d+(\.\d{2})?$');

/// Quita acentos y pasa a minúsculas para comparar palabras.
String normalizeForMatch(String text) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    final index = from.indexOf(char);
    buffer.write(index == -1 ? char : to[index]);
  }
  return buffer.toString().toLowerCase();
}

/// Convierte un total leído a texto de monto ("1234.50"), o `null` si no
/// es un número válido mayor a 0 y menor o igual a $9,999,999.99, o si es
/// ambiguo para el formato MXN, como "1,234.5" o "1.234,50" (RF-28).
String? normalizeMxnAmount(String raw) {
  final text = raw
      .replaceAll(RegExp(r'mxn|\$', caseSensitive: false), '')
      .replaceAll(' ', '');
  if (!_thousands.hasMatch(text) && !_plain.hasMatch(text)) return null;
  final clean = text.replaceAll(',', '');
  final parts = clean.split('.');
  final pesos = int.tryParse(parts.first);
  if (pesos == null || pesos > AppConfig.maxAmountCents ~/ 100) return null;
  final cents = pesos * 100 + (parts.length > 1 ? int.parse(parts[1]) : 0);
  if (cents <= 0 || cents > AppConfig.maxAmountCents) return null;
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

/// Intérprete del texto del recibo.
class ReceiptParser {
  ReceiptParser({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  ParsedReceipt parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList(growable: false);
    final merchant = extractMerchant(lines);
    final date = _readDate(lines.map(normalizeForMatch).join('\n'));
    final total = _findTotal(lines);
    final amount = total == null ? null : normalizeMxnAmount(total);
    final today = _today();
    return ParsedReceipt(
      merchant: merchant,
      date: date.value ?? today,
      amountText: amount,
      missing: {
        if (merchant == null) ReceiptField.merchant,
        if (!date.found) ReceiptField.date,
        if (amount == null) ReceiptField.total,
      },
      dateWarning: date.value == null,
      illegible: merchant == null && !date.found && total == null,
    );
  }

  DateTime _today() {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// Primera línea de las primeras 6 con al menos 3 letras que no sea un
  /// dato fiscal ni de caja; máximo 60 caracteres (RF-24).
  static String? extractMerchant(List<String> lines) {
    for (final line in lines.take(6)) {
      final normalized = normalizeForMatch(line);
      final letters = RegExp('[a-z]').allMatches(normalized).length;
      if (letters < 3 || _merchantSkip.hasMatch(normalized)) continue;
      final clean = line
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'^[^\wÁÉÍÓÚÑáéíóúñ]+|[^\wÁÉÍÓÚÑáéíóúñ.]+$'), '')
          .trim();
      if (clean.isEmpty) continue;
      final runes = clean.runes.toList();
      return runes.length <= AppConfig.maxDescriptionLength
          ? clean
          : String.fromCharCodes(
              runes.take(AppConfig.maxDescriptionLength),
            ).trim();
    }
    return null;
  }

  /// Busca la primera fecha. `found` indica que había una fecha escrita;
  /// `value` es `null` si era inválida o futura (RF-27).
  ({bool found, DateTime? value}) _readDate(String text) {
    final candidate = _dateCandidate(text);
    if (candidate == null) return (found: false, value: null);
    final (year, month, day) = candidate;
    final date = DateTime(year, month, day);
    final valid = month >= 1 &&
        month <= 12 &&
        date.month == month &&
        date.day == day &&
        !date.isAfter(_today());
    return (found: true, value: valid ? date : null);
  }

  static (int, int, int)? _dateCandidate(String text) {
    final ymd = _numericYmd.firstMatch(text);
    if (ymd != null) {
      return (_int(ymd, 1), _int(ymd, 2), _int(ymd, 3));
    }
    final dmy = _numericDmy.firstMatch(text);
    if (dmy != null) {
      return (_year(dmy.group(3)!), _int(dmy, 2), _int(dmy, 1));
    }
    final named = _textMonth.firstMatch(text);
    if (named != null) {
      return (_year(named.group(3)!), _months[named.group(2)]!, _int(named, 1));
    }
    return null;
  }

  static int _int(RegExpMatch match, int group) =>
      int.parse(match.group(group)!);

  static int _year(String text) =>
      text.length == 2 ? 2000 + int.parse(text) : int.parse(text);

  /// Texto del total: el último número de la primera línea que diga
  /// "total" (sin ser subtotal ni total de artículos), o de la línea de
  /// abajo si esa línea no trae número.
  static String? _findTotal(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = normalizeForMatch(lines[i]);
      if (!_totalWord.hasMatch(normalized) || _notTotal.hasMatch(normalized)) {
        continue;
      }
      final here = _lastAmount(lines[i]);
      if (here != null) return here;
      if (i + 1 < lines.length) return _lastAmount(lines[i + 1]);
    }
    return null;
  }

  static String? _lastAmount(String line) {
    final matches = _amountToken.allMatches(line).toList();
    return matches.isEmpty ? null : matches.last.group(0);
  }
}
