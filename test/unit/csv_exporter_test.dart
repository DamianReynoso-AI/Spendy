// Pruebas del incremento 5 para M-08: CsvExporter, PdfExporter y
// ExportService (nombre del archivo, menú de compartir, errores y tiempo
// con 2,000 movimientos). RF-41 a RF-44; RNF-11, RNF-33, RNF-37, RNF-38;
// CA-107 a CA-113.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/modules/export/csv_exporter.dart';
import 'package:spendy/modules/export/export_service.dart';
import 'package:spendy/modules/export/exporter.dart';
import 'package:spendy/modules/export/pdf_exporter.dart';
import 'package:spendy/modules/summary/annual_summary_calculator.dart';

import 'annual_summary_calculator_test.dart' show sampleMovements;

const AnnualSummary summary = AnnualSummary(
  year: 2026,
  incomeCents: 1500000,
  expenseCents: 123456,
  movementCount: 4,
  byCategory: [
    CategoryTotal('Alimentos', 123456),
    CategoryTotal('Transporte', 0),
    CategoryTotal('Vivienda', 0),
    CategoryTotal('Servicios', 0),
    CategoryTotal('Entretenimiento', 0),
    CategoryTotal('Otros', 0),
  ],
);

final DateTime generated = DateTime(2026, 11, 5, 18, 30);

class FailingExporter implements SummaryExporter {
  FailingExporter(this.error);
  final Object error;

  @override
  ExportFormat get format => ExportFormat.csv;

  @override
  Future<Uint8List> render(AnnualSummary summary, DateTime generatedAt) =>
      Future.error(error);
}

void main() {
  group('CsvExporter', () {
    const exporter = CsvExporter();

    test('CA-108 / RNF-38: UTF-8 con BOM y acentos legibles', () async {
      final bytes = await exporter.render(summary, generated);
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.sublist(3));
      expect(text, contains('Año consultado'));
      expect(text, contains('Gastos por categoría'));
      expect(text, contains('Fecha de generación'));
    });

    test('RF-42: los cuatro bloques con formato MXN y DD/MM/AAAA', () {
      final lines = exporter.buildText(summary, generated).split('\r\n');
      expect(lines, [
        'Resumen anual SPENDY',
        'Año consultado,2026',
        'Fecha de generación,05/11/2026',
        '',
        'Totales del año,Monto',
        r'Ingresos,"$15,000.00"',
        r'Egresos,"$1,234.56"',
        r'Diferencia (ingresos - egresos),"$13,765.44"',
        '',
        'Gastos por categoría,Monto',
        r'Alimentos,"$1,234.56"',
        r'Transporte,$0.00',
        r'Vivienda,$0.00',
        r'Servicios,$0.00',
        r'Entretenimiento,$0.00',
        r'Otros,$0.00',
        '',
      ]);
    });

    test('csvField escapa comas, comillas y saltos de línea', () {
      expect(csvField('simple'), 'simple');
      expect(csvField('a,b'), '"a,b"');
      expect(csvField('dijo "hola"'), '"dijo ""hola"""');
      expect(csvField('dos\nlíneas'), '"dos\nlíneas"');
    });

    test('CA-107: nombre exacto del archivo', () {
      expect(exportFileName(2026, ExportFormat.csv), 'spendy_resumen_2026.csv');
      expect(exportFileName(2025, ExportFormat.pdf), 'spendy_resumen_2025.pdf');
    });

    test('RNF-33: los exportadores no importan la calculadora', () {
      for (final name in ['csv_exporter.dart', 'pdf_exporter.dart']) {
        final source = File('lib/modules/export/$name').readAsStringSync();
        expect(source, isNot(contains('AnnualSummaryCalculator')));
      }
    });
  });

  group('PdfExporter', () {
    test('RNF-38: genera un PDF estándar', () async {
      final bytes = await const PdfExporter().render(summary, generated);
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      final tail = latin1.decode(bytes.sublist(bytes.length - 8));
      expect(tail, contains('%%EOF'));
    });

    test('RF-42: el texto del PDF tiene los cuatro bloques', () async {
      final dir = Directory.systemTemp.createTempSync('spendy_pdf_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File(p.join(dir.path, 'r.pdf'))
        ..writeAsBytesSync(
            await const PdfExporter().render(summary, generated));
      final ProcessResult result;
      try {
        result = await Process.run('pdftotext', [file.path, '-']);
      } on ProcessException {
        markTestSkipped('pdftotext no está disponible');
        return;
      }
      final text = result.stdout as String;
      for (final expected in [
        'Año consultado: 2026',
        'Fecha de generación: 05/11/2026',
        'Totales del año',
        r'$15,000.00',
        r'$13,765.44',
        'Gastos por categoría',
        'Entretenimiento',
      ]) {
        expect(text, contains(expected));
      }
    });
  });

  group('ExportService', () {
    late Directory dir;
    late File logFile;
    late List<File> shared;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('spendy_export_');
      logFile = File(p.join(dir.path, errorLogFileName));
      shared = [];
    });

    tearDown(() => dir.deleteSync(recursive: true));

    ExportService serviceWith({
      ShareLauncher? share,
      List<SummaryExporter> exporters = const [CsvExporter(), PdfExporter()],
    }) =>
        ExportService(
          directory: () async => dir,
          logger: ErrorLogger(() async => logFile),
          share: share ?? (file, format) async => shared.add(file),
          clock: () => generated,
          exporters: exporters,
        );

    List<String> exported() => Directory(p.join(dir.path, 'exportaciones'))
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();

    test('CA-107: escribe spendy_resumen_AAAA y lo entrega al menú nativo',
        () async {
      final service = serviceWith();
      for (final format in ExportFormat.values) {
        final result = await service.export(summary, format);
        expect(p.basename(result.valueOrNull!), exportFileName(2026, format));
      }
      expect(shared.map((f) => p.basename(f.path)),
          ['spendy_resumen_2026.csv', 'spendy_resumen_2026.pdf']);
      expect(
          exported(), unorderedEquals(shared.map((f) => p.basename(f.path))));
    });

    test(
        'CA-111 / CA-112: si falla, borra el archivo, registra y permite '
        'reintentar', () async {
      final service = serviceWith(
        share: (file, format) => Future.error(StateError('menú')),
      );
      final result = await service.export(summary, ExportFormat.csv);
      expect(result.errorOrNull!.type, ErrorType.export);
      expect(result.errorOrNull!.message, ExportMessages.failed);
      expect(exported(), isEmpty);
      expect(logFile.readAsStringSync(), contains('exportacion | M-08'));
    });

    test('CA-113: sin espacio da mensaje de espacio y no deja parciales',
        () async {
      final service = serviceWith(exporters: [
        FailingExporter(const FileSystemException(
          'write',
          'x',
          OSError('No space left on device', 28),
        )),
      ]);
      final result = await service.export(summary, ExportFormat.csv);
      expect(result.errorOrNull!.type, ErrorType.storageFull);
      expect(result.errorOrNull!.message, ExportMessages.storageFull);
      expect(exported(), isEmpty);
    });

    test('si la carpeta no se puede usar, error controlado', () async {
      final service = ExportService(
        directory: () => Future.error(const FileSystemException('sin carpeta')),
        logger: ErrorLogger(() async => logFile),
        share: (file, format) async {},
      );
      final result = await service.export(summary, ExportFormat.pdf);
      expect(result.errorOrNull!.message, ExportMessages.failed);
    });

    test('CA-109 / RNF-11: con 2,000 movimientos CSV y PDF en <= 10 s',
        () async {
      final big = const AnnualSummaryCalculator()
          .calculate(2026, sampleMovements(2000));
      final service = serviceWith();
      final watch = Stopwatch()..start();
      expect((await service.export(big, ExportFormat.csv)).isSuccess, isTrue);
      expect((await service.export(big, ExportFormat.pdf)).isSuccess, isTrue);
      watch.stop();
      // ignore: avoid_print
      print('RNF-11: CSV + PDF de un año con ${big.movementCount} movimientos '
          'en ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 10)));
    });
  });
}
