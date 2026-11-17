// Pruebas del OCR en el teléfono con ML Kit (M-05, RNF-17, RNF-32):
// reconstrucción de renglones, adaptador y lectura de comercio, fecha y
// total con texto como el que entrega ML Kit.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/modules/ocr/mlkit_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_layout.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';

/// Pedazo de texto de 20 px de alto con su esquina superior izquierda.
TextFragment frag(String text, double left, double top, {double h = 20}) =>
    TextFragment(text, left, top, left + text.length * 10, top + h);

/// Ticket de OXXO como lo entrega ML Kit: los conceptos y los importes
/// salen en bloques separados (columna izquierda y columna derecha).
final List<TextFragment> oxxoBlocks = [
  // Bloque 1: encabezado.
  frag('OXXO TIENDA 1234', 100, 10),
  frag('RFC: CCO8605231N4', 100, 40),
  frag('FECHA: 10/11/2026 HORA: 14:32', 40, 70),
  // Bloque 2: conceptos.
  frag('COCA COLA 600ML', 20, 110),
  frag('SABRITAS', 20, 140),
  frag('SUBTOTAL', 20, 170),
  frag('IVA', 20, 200),
  frag('TOTAL', 20, 232),
  frag('EFECTIVO', 20, 260),
  // Bloque 3: importes, un poco inclinados respecto a su concepto.
  frag('18.50', 300, 112),
  frag('21.00', 300, 143),
  frag('34.05', 300, 173),
  frag('5.45', 300, 202),
  frag('\$39.50', 290, 236),
  frag('100.00', 300, 263),
];

void main() {
  final parser = ReceiptParser(clock: () => DateTime(2026, 11, 17, 12));

  group('joinFragmentsIntoLines', () {
    test('junta concepto e importe de columnas distintas', () {
      final text = joinFragmentsIntoLines(oxxoBlocks);
      final lines = text.split('\n');
      expect(lines.first, 'OXXO TIENDA 1234');
      expect(lines, contains('TOTAL \$39.50'));
      expect(lines, contains('SUBTOTAL 34.05'));
      expect(lines, hasLength(9));
    });

    test('ordena de izquierda a derecha dentro del renglón', () {
      final text = joinFragmentsIntoLines([
        frag('120.00', 300, 50),
        frag('TOTAL', 20, 52),
      ]);
      expect(text, 'TOTAL 120.00');
    });

    test('renglones que no se tocan quedan separados', () {
      final text = joinFragmentsIntoLines([
        frag('B', 20, 40),
        frag('A', 20, 10),
      ]);
      expect(text, 'A\nB');
    });

    test('ignora pedazos vacíos y sin texto devuelve vacío', () {
      expect(joinFragmentsIntoLines([]), '');
      expect(joinFragmentsIntoLines([frag('  ', 0, 0)]), '');
    });
  });

  group('lectura de un ticket leído por ML Kit', () {
    test('saca comercio, fecha y total aunque vengan en bloques', () {
      final r = parser.parse(joinFragmentsIntoLines(oxxoBlocks));
      expect(r.merchant, 'OXXO TIENDA 1234');
      expect(r.date, DateTime(2026, 11, 10));
      expect(r.amountText, '39.50');
      expect(r.missing, isEmpty);
    });

    test('sin reconstruir renglones el total se perdería', () {
      // Así se ve el texto plano de ML Kit: bloque por bloque.
      final plain = [
        'OXXO TIENDA 1234',
        'TOTAL',
        'EFECTIVO',
        '\$39.50',
        '100.00',
      ].join('\n');
      expect(parser.parse(plain).amountText, isNot('39.50'));
    });

    test('acepta T0TAL con cero y no confunde SUBT0TAL', () {
      final r = parser.parse('Farmacia Guadalajara\nSUBT0TAL 90.00\n'
          'T0TAL 104.40');
      expect(r.amountText, '104.40');
    });

    test('corrige la O leída como cero dentro del importe', () {
      expect(parser.parse('Soriana\nTOTAL \$1O0.00').amountText, '100.00');
    });

    test('corrige espacios alrededor del punto decimal', () {
      expect(parser.parse('Soriana\nTOTAL \$ 245. 90').amountText, '245.90');
    });

    test('fecha con mes en texto como la imprime una terminal', () {
      final r = parser.parse('LA MICHOACANA\n15 NOV 2026 18:04\nTOTAL 85.00');
      expect(r.date, DateTime(2026, 11, 15));
      expect(r.amountText, '85.00');
    });

    test('total con separador de miles', () {
      final r = parser.parse('LIVERPOOL\nTOTAL MXN \$1,234.50');
      expect(r.amountText, '1234.50');
    });

    test('cleanOcrDigits no toca palabras', () {
      expect(cleanOcrDigits('OXXO TOTAL 1O.5O'), 'OXXO TOTAL 10.50');
    });
  });

  group('MlKitOcrAdapter', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('spendy_ocr'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lee de un archivo temporal en la carpeta privada y lo borra',
        () async {
      String? seenPath;
      Uint8List? seenBytes;
      final adapter = MlKitOcrAdapter(
        workDir: dir,
        readLines: (path) async {
          seenPath = path;
          seenBytes = File(path).readAsBytesSync();
          return oxxoBlocks;
        },
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final text = await adapter.recognize(bytes, OcrCancelToken());
      expect(text, contains('TOTAL \$39.50'));
      expect(seenPath, startsWith(dir.path));
      expect(seenBytes, bytes);
      expect(dir.listSync(), isEmpty);
    });

    test('un error de ML Kit se vuelve OcrException(server)', () async {
      final adapter = MlKitOcrAdapter(
        workDir: dir,
        readLines: (_) async => throw StateError('falló'),
      );
      await expectLater(
        adapter.recognize(Uint8List(1), OcrCancelToken()),
        throwsA(
          isA<OcrException>()
              .having((e) => e.kind, 'kind', OcrFailureKind.server),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('si se canceló durante la lectura no devuelve texto', () async {
      final cancel = OcrCancelToken();
      final adapter = MlKitOcrAdapter(
        workDir: dir,
        readLines: (_) async {
          cancel.cancel();
          return oxxoBlocks;
        },
      );
      await expectLater(
        adapter.recognize(Uint8List(1), cancel),
        throwsA(isA<OcrException>()),
      );
    });
  });
}
