// Pruebas del incremento 4 para M-05: ReceiptParser (extracción y
// validación de comercio, fecha y total). RF-24, RF-27 a RF-29; CA-062,
// CA-063, CA-070, CA-071, CA-073, CA-074.
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';

void main() {
  final today = DateTime(2026, 11, 12);
  final parser = ReceiptParser(clock: () => DateTime(2026, 11, 12, 15, 30));

  const oxxo = '''
OXXO TIENDA 1234
RFC: CCO8605231N4
Blvd. Campestre 101, León, Gto.
FECHA: 10/11/2026 HORA: 14:32
COCA COLA 600ML        18.50
SABRITAS               21.00
SUBTOTAL               34.05
IVA                     5.45
TOTAL                 \$39.50
EFECTIVO              100.00
CAMBIO                 60.50
''';

  group('CA-062: recibo legible', () {
    test('lee comercio, fecha y total', () {
      final r = parser.parse(oxxo);
      expect(r.merchant, 'OXXO TIENDA 1234');
      expect(r.date, DateTime(2026, 11, 10));
      expect(r.amountText, '39.50');
      expect(r.missing, isEmpty);
      expect(r.dateWarning, isFalse);
      expect(r.illegible, isFalse);
    });

    test('el subtotal no se confunde con el total', () {
      final r = parser.parse('Farmacia del Ahorro\nSUBTOTAL 100.00\n'
          'Total a pagar: 116.00');
      expect(r.amountText, '116.00');
    });

    test('el total puede venir en la línea de abajo', () {
      final r = parser.parse('Tacos El Güero\nTOTAL\n\$1,250.00');
      expect(r.amountText, '1250.00');
      expect(r.merchant, 'Tacos El Güero');
    });

    test('"Total de artículos" no es el total', () {
      final r = parser.parse('Soriana\nTOTAL DE ARTICULOS 3\nTOTAL 45.00');
      expect(r.amountText, '45.00');
    });

    test('importe entero sin decimales', () {
      expect(parser.parse('Cine\nTOTAL 150').amountText, '150.00');
    });
  });

  group('fechas (RF-27)', () {
    test('formatos DD/MM/AAAA, DD-MM-AA, AAAA-MM-DD y con mes en letra', () {
      expect(parser.parse('x\n05-11-26').date, DateTime(2026, 11, 5));
      expect(parser.parse('x\n2026-10-31').date, DateTime(2026, 10, 31));
      expect(parser.parse('x\n3 nov 2026').date, DateTime(2026, 11, 3));
      expect(parser.parse('x\n07/SEP/2026').date, DateTime(2026, 9, 7));
      expect(parser.parse('x\n1 de diciembre de 2025').date,
          DateTime(2025, 12, 1));
    });

    test('CA-070: fecha futura se cambia por hoy con aviso', () {
      final r = parser.parse('Oxxo\nFECHA 20/11/2026\nTOTAL 10.00');
      expect(r.date, today);
      expect(r.dateWarning, isTrue);
      expect(r.missing, isNot(contains(ReceiptField.date)));
    });

    test('fecha inválida (31/02) se cambia por hoy con aviso', () {
      final r = parser.parse('Oxxo\n31/02/2026\nTOTAL 10.00');
      expect(r.date, today);
      expect(r.dateWarning, isTrue);
    });

    test('mes 13 no es fecha válida', () {
      expect(parser.parse('Oxxo\n01/13/2026').dateWarning, isTrue);
    });

    test('hoy sí es válida', () {
      final r = parser.parse('Oxxo\n12/11/2026\nTOTAL 1.00');
      expect(r.date, today);
      expect(r.dateWarning, isFalse);
    });

    test('CA-063: sin fecha, queda hoy resaltada y con aviso', () {
      final r = parser.parse('Oxxo\nTOTAL 10.00');
      expect(r.missing, {ReceiptField.date});
      expect(r.date, today);
      expect(r.dateWarning, isTrue);
    });
  });

  group('total (RF-28)', () {
    test('CA-073: formatos ambiguos quedan vacíos y resaltados', () {
      for (final raw in ['1,234.5', '1.234,50', '12,50', '1234.5', '1.5.0']) {
        final r = parser.parse('Oxxo\n10/11/2026\nTOTAL $raw');
        expect(r.amountText, isNull, reason: raw);
        expect(r.missing, {ReceiptField.total}, reason: raw);
      }
    });

    test('CA-071: cero o mayor a \$9,999,999.99 queda vacío', () {
      expect(parser.parse('Oxxo\nTOTAL 0.00').amountText, isNull);
      expect(parser.parse('Oxxo\nTOTAL 10,000,000.00').amountText, isNull);
      expect(parser.parse('Oxxo\nTOTAL 99999999999999').amountText, isNull);
    });

    test('el máximo \$9,999,999.99 sí se acepta', () {
      expect(parser.parse('Oxxo\nTOTAL 9,999,999.99').amountText, '9999999.99');
    });

    test('normalizeMxnAmount', () {
      expect(normalizeMxnAmount(r'$1,234.56'), '1234.56');
      expect(normalizeMxnAmount('1,234'), '1234.00');
      expect(normalizeMxnAmount('0.05'), '0.05');
      expect(normalizeMxnAmount('350 MXN'), '350.00');
      expect(normalizeMxnAmount('abc'), isNull);
      expect(normalizeMxnAmount(''), isNull);
    });

    test('línea TOTAL sin número y sin línea siguiente', () {
      final r = parser.parse('Oxxo\n10/11/2026\nTOTAL');
      expect(r.missing, {ReceiptField.total});
    });
  });

  group('comercio', () {
    test('salta líneas de RFC, folio, fecha o con pocas letras', () {
      final r = parser.parse('RFC XAXX010101000\n12345\n*** Café Tal ***\n'
          'TOTAL 50.00');
      expect(r.merchant, 'Café Tal');
    });

    test('se recorta a 60 caracteres', () {
      final long = 'Comercializadora ${'a' * 80}';
      final r = parser.parse('$long\nTOTAL 1.00');
      expect(r.merchant!.runes.length, 60);
    });

    test('CA-063: sin comercio, queda vacío y resaltado', () {
      final r = parser.parse('RFC ABC\n10/11/2026\nTOTAL 5.00');
      expect(r.merchant, isNull);
      expect(r.missing, {ReceiptField.merchant});
    });
  });

  group('CA-074: imagen ilegible', () {
    test('sin comercio, ni fecha, ni total', () {
      for (final text in ['', '   \n  ', '%%%\n12\n--', 'ab 12']) {
        final r = parser.parse(text);
        expect(r.illegible, isTrue, reason: text);
        expect(r.missing, ReceiptField.values.toSet());
      }
    });

    test('con un solo campo ya no es ilegible', () {
      expect(parser.parse('12\nTOTAL 1,234.5').illegible, isFalse);
      expect(parser.parse('Oxxo').illegible, isFalse);
    });
  });

  test('normalizeForMatch quita acentos y pasa a minúsculas', () {
    expect(normalizeForMatch('ÁRBOL Niño Café'), 'arbol nino cafe');
  });
}
