/// M-12 · Formateadores regionales de México (RF-54, RNF-37).
///
/// El formato se arma a mano y no depende del idioma del teléfono, así que
/// siempre sale igual ($1,234.56 y DD/MM/AAAA), aunque el dispositivo esté
/// en inglés. Solo usa la biblioteca estándar de Dart.
library;

final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Pone comas cada tres dígitos: 1234567 -> "1,234,567".
String _groupThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Da formato a un monto en centavos: 123450 -> "$1,234.50".
/// Los negativos salen como "-$500.00" (para el balance, incremento 2).
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  final pesos = absolute ~/ 100;
  final centavos = (absolute % 100).toString().padLeft(2, '0');
  return '$sign\$${_groupThousands(pesos)}.$centavos';
}

/// Da formato a un monto en pesos con decimales: 1234.5 -> "$1,234.50".
/// Primero lo convierte a centavos redondeando, para evitar errores de
/// punto flotante.
String formatAmount(num amount) => formatCents((amount * 100).round());

/// Da formato a una fecha: DateTime(2026, 1, 5) -> "05/01/2026".
String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}

/// Convierte "AAAA-MM-DD" (como se guarda en la base) a "DD/MM/AAAA".
/// Lanza FormatException si el texto no tiene ese formato o la fecha
/// no existe (por ejemplo, 2026-02-30).
String formatIsoDate(String isoDate) {
  final match = _isoDatePattern.firstMatch(isoDate.trim());
  if (match == null) {
    throw FormatException('La fecha debe tener formato AAAA-MM-DD', isoDate);
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.month != month || date.day != day) {
    throw FormatException('La fecha no existe', isoDate);
  }
  return formatDate(date);
}
