import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/core/formatters.dart';

void main() {
  group('Formato de moneda (RF-54)', () {
    test('CA-150 normal: 1234.5 y 123450 centavos dan \$1,234.50', () {
      expect(formatAmount(1234.5), r'$1,234.50');
      expect(formatCents(123450), r'$1,234.50');
    });

    test('CA-153 límite: \$0.01 y \$9,999,999.99', () {
      expect(formatAmount(0.01), r'$0.01');
      expect(formatAmount(9999999.99), r'$9,999,999.99');
      expect(formatCents(1), r'$0.01');
      expect(formatCents(999999999), r'$9,999,999.99');
    });

    test('montos sin miles y cero', () {
      expect(formatCents(0), r'$0.00');
      expect(formatCents(35000), r'$350.00');
      expect(formatCents(100000), r'$1,000.00');
    });

    test('negativos llevan el signo antes del símbolo', () {
      expect(formatCents(-50000), r'-$500.00');
    });
  });

  group('Formato de fecha (RF-54)', () {
    test('normal: DD/MM/AAAA', () {
      expect(formatDate(DateTime(2026, 10, 15)), '15/10/2026');
    });

    test('límite: día y mes de un dígito llevan cero', () {
      expect(formatDate(DateTime(2026, 1, 5)), '05/01/2026');
    });

    test('AAAA-MM-DD se convierte a DD/MM/AAAA', () {
      expect(formatIsoDate('2026-10-15'), '15/10/2026');
    });

    test('error: formato incorrecto', () {
      expect(() => formatIsoDate('15/10/2026'), throwsFormatException);
      expect(() => formatIsoDate('abc'), throwsFormatException);
    });

    test('error: fecha que no existe', () {
      expect(() => formatIsoDate('2026-02-30'), throwsFormatException);
      expect(() => formatIsoDate('2026-13-01'), throwsFormatException);
    });
  });
}
