import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/config/app_config.dart';
import 'package:spendy/core/validators.dart';

void main() {
  group('validateAmount (RF-04)', () {
    test('normal: montos válidos', () {
      expect(validateAmount('350'), isNull);
      expect(validateAmount('350.00'), isNull);
      expect(validateAmount('0.01'), isNull);
      expect(validateAmount(' 15000.5 '), isNull);
    });

    test('CA-002 error: 0, negativo, letras y 3 decimales', () {
      for (final value in ['0', '0.00', '-5.00', 'abc', '12.345']) {
        expect(validateAmount(value), ValidationMessages.amountInvalid,
            reason: 'entrada: $value');
      }
    });

    test('CA-005 límite: 9999999.99 sí, 10000000.00 no', () {
      expect(validateAmount('9999999.99'), isNull);
      expect(validateAmount('10000000.00'), ValidationMessages.amountTooHigh);
      expect(validateAmount('99999999999999999999'),
          ValidationMessages.amountTooHigh);
    });

    test('D-03 error: montos con coma se rechazan', () {
      expect(validateAmount('12,50'), ValidationMessages.amountComma);
      expect(validateAmount('1,234.50'), ValidationMessages.amountComma);
    });

    test('error: vacío o nulo', () {
      for (final value in [null, '', '   ']) {
        expect(validateAmount(value), ValidationMessages.amountRequired);
      }
    });
  });

  group('validateDate (RF-03)', () {
    final today = DateTime(2026, 11, 3);

    test('normal: hoy es válido, sin importar la hora', () {
      expect(validateDate(DateTime(2026, 11, 3, 23, 59), now: today), isNull);
    });

    test('CA-011 límite: 31/12 del año anterior es válida', () {
      expect(validateDate(DateTime(2025, 12, 31), now: today), isNull);
    });

    test('CA-003 error: mañana se rechaza', () {
      expect(validateDate(DateTime(2026, 11, 4), now: today),
          ValidationMessages.dateFuture);
    });

    test('CA-003 error con el reloj real: mañana se rechaza', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(validateDate(tomorrow), ValidationMessages.dateFuture);
    });

    test('error: fecha nula', () {
      expect(validateDate(null), ValidationMessages.dateRequired);
    });
  });

  group('validateRequiredField (RF-05)', () {
    test('normal: con valor es válido', () {
      expect(validateRequiredField('Alimentos', 'Categoría'), isNull);
      expect(validateRequiredField(1, 'Categoría'), isNull);
    });

    test('CA-004 error: vacío indica qué campo falta', () {
      for (final value in [null, '', '   ']) {
        expect(validateRequiredField(value, 'Método de pago'),
            ValidationMessages.requiredField('Método de pago'));
      }
    });
  });

  group('validateTextLength (RF-06)', () {
    const desc = AppConfig.maxDescriptionLength;
    const note = AppConfig.maxNoteLength;

    test('CA-006 límite: 60 y 200 caracteres se aceptan', () {
      expect(validateTextLength('a' * desc, desc), isNull);
      expect(validateTextLength('é' * desc, desc), isNull);
      expect(validateTextLength('a' * note, note), isNull);
    });

    test('CA-006 error: un carácter más se rechaza', () {
      expect(validateTextLength('a' * (desc + 1), desc),
          ValidationMessages.textTooLong(desc));
      expect(validateTextLength('a' * (note + 1), note),
          ValidationMessages.textTooLong(note));
    });

    test('normal: campos opcionales vacíos son válidos', () {
      expect(validateTextLength(null, note), isNull);
      expect(validateTextLength('', note), isNull);
    });
  });
}
