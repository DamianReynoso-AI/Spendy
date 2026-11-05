/// M-12 · Validadores puros de entrada (RF-03, RF-04, RF-05, RF-06).
///
/// Cada función devuelve `null` si el valor es válido, o un mensaje en
/// español de México si no lo es (RNF-05). Así funcionan directo con los
/// campos de formulario de Flutter (M-01) sin cambios.
library;

import '../config/app_config.dart';
import 'formatters.dart';

/// Catálogo único de mensajes de validación (D-04 / AMB-01).
class ValidationMessages {
  ValidationMessages._();

  static const String amountRequired = 'Escribe el monto.';
  static const String amountInvalid =
      'El monto debe ser mayor a 0 y tener máximo 2 decimales.';
  static const String amountComma =
      'Escribe el monto sin comas; usa punto para los decimales '
      '(por ejemplo, 1234.50).';
  static String get amountTooHigh =>
      'El monto no puede ser mayor a ${formatCents(AppConfig.maxAmountCents)}.';
  static const String dateRequired = 'Elige una fecha.';
  static const String dateFuture =
      'La fecha no puede ser futura. Elige hoy o una fecha anterior.';
  static String requiredField(String fieldName) =>
      'El campo "$fieldName" es obligatorio.';
  static String textTooLong(int maxLength) =>
      'El texto no puede tener más de $maxLength caracteres.';
}

/// Solo dígitos, con punto y 1 o 2 decimales opcionales. Rechaza signos,
/// letras, comas y más de 2 decimales.
final RegExp _amountPattern = RegExp(r'^\d+(\.\d{1,2})?$');

/// Convierte un monto ya revisado por _amountPattern a centavos.
/// Devuelve null si los pesos superan el máximo (evita desbordes).
int? _toCents(String text) {
  final parts = text.split('.');
  final pesos = int.tryParse(parts.first);
  if (pesos == null || pesos > AppConfig.maxAmountCents ~/ 100) return null;
  final decimals = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  return pesos * 100 + int.parse(decimals);
}

/// Valida el monto escrito por el usuario (RF-04, D-03: solo punto decimal).
String? validateAmount(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return ValidationMessages.amountRequired;
  if (text.contains(',')) return ValidationMessages.amountComma;
  if (!_amountPattern.hasMatch(text)) return ValidationMessages.amountInvalid;
  final cents = _toCents(text);
  if (cents == null || cents > AppConfig.maxAmountCents) {
    return ValidationMessages.amountTooHigh;
  }
  if (cents <= 0) return ValidationMessages.amountInvalid;
  return null;
}

/// Valida que la fecha exista y no sea futura (RF-03). Solo compara el día,
/// no la hora. `now` permite fijar "hoy" en las pruebas; si no se pasa,
/// se usa el reloj del dispositivo.
String? validateDate(DateTime? date, {DateTime? now}) {
  if (date == null) return ValidationMessages.dateRequired;
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final chosen = DateTime(date.year, date.month, date.day);
  return chosen.isAfter(today) ? ValidationMessages.dateFuture : null;
}

/// Valida que un campo obligatorio (categoría, método de pago) no esté
/// vacío (RF-05). Un texto con solo espacios cuenta como vacío.
String? validateRequiredField(dynamic value, String fieldName) {
  final isEmpty = value == null || (value is String && value.trim().isEmpty);
  return isEmpty ? ValidationMessages.requiredField(fieldName) : null;
}

/// Valida la longitud de un texto opcional (RF-06). Vacío o nulo es válido.
/// Cuenta caracteres reales (runes), así "é" cuenta como uno.
/// Uso: validateTextLength(nota, AppConfig.maxNoteLength).
String? validateTextLength(String? text, int maxLength) {
  if (text == null) return null;
  return text.runes.length > maxLength
      ? ValidationMessages.textTooLong(maxLength)
      : null;
}
