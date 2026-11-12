// Prueba de flujo completo del incremento 4 con MockOcrAdapter: escanear,
// leer, revisar y guardar, más las salidas manuales, el reintento y la
// cancelación. Usa la cámara y el almacenamiento simulados y el OcrService
// real. CA-062 a CA-082 y CA-145, CA-146.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/ocr/mock_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';
import 'package:spendy/modules/receipts/camera_service.dart';
import 'package:spendy/ui/screens/ocr_review_screen.dart';

import '../widget/movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import '../widget/receipt_screens_test.dart' show FakeDevice, FakeReceipts;

const String legible = 'OXXO TIENDA 1234\nFECHA 10/11/2026\nSUBTOTAL 34.05\n'
    'TOTAL \$39.50\nEFECTIVO 100.00';

void main() {
  late MemoryMovementRepository repo;
  late MovementService service;
  late CategoryCatalog catalog;
  late FakeReceipts receipts;
  late MockOcrAdapter ocr;

  setUp(() {
    final logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    repo = MemoryMovementRepository();
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    service = MovementService(
      repository: repo,
      catalog: catalog,
      logger: logger,
      clock: () => DateTime(2026, 11, 12, 12),
    );
    ocr = MockOcrAdapter(text: legible);
    receipts = FakeReceipts()
      ..ocr = OcrService(
        adapter: ocr,
        logger: logger,
        parser: ReceiptParser(clock: () => DateTime(2026, 11, 12)),
      );
    // La cámara simulada se crea en cada prueba con pumpApp.
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    await tester.pumpWidget(
      SpendyApp(
        service: service,
        catalog: catalog,
        receipts: receipts,
        camera: CameraService(FakeDevice(), logger),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      await tester.dragUntilVisible(
        find.text(text),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// Abre el escáner, toma la foto y toca "Usar foto" sin esperar a que
  /// termine la lectura.
  Future<void> scanAndUse(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Escanear recibo'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Tomar foto');
    await tester.tap(find.text('Usar foto'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, Type type, String option) async {
    await tester.tap(find.byType(type));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'CA-062, CA-064, CA-066 a CA-069: lee, prellena, no guarda solo y '
      'guarda lo confirmado con el recibo', (tester) async {
    ocr.delay = const Duration(seconds: 2);
    await pumpApp(tester);
    await scanAndUse(tester);
    expect(find.text('Leyendo el recibo…'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(OcrReviewTexts.title), findsOneWidget);
    expect(find.text(OcrReviewTexts.intro), findsOneWidget);
    expect(find.text('39.50'), findsOneWidget);
    expect(find.text('OXXO TIENDA 1234'), findsOneWidget);
    expect(find.text('10/11/2026'), findsOneWidget);
    expect(find.text('Foto del recibo adjunta'), findsOneWidget);
    expect(repo.rows, isEmpty, reason: 'RF-25: nunca se guarda solo');

    await tester.enterText(find.byType(TextField).first, '40.00');
    await tapText(tester, 'Guardar');
    expect(repo.rows, isEmpty, reason: 'CA-067: faltan categoría y método');
    await choose(tester, DropdownButton<int>, 'Alimentos');
    await choose(tester, DropdownButton<PaymentMethod>, 'Efectivo');
    await tapText(tester, 'Guardar');

    final saved = repo.rows.single;
    expect(saved.amountCents, 4000);
    expect(saved.description, 'OXXO TIENDA 1234');
    expect(saved.date, DateTime(2026, 11, 10));
    expect(find.text('Movimiento guardado.'), findsOneWidget);
  });

  testWidgets('CA-063 / CA-070: campos no leídos resaltados y aviso de fecha',
      (tester) async {
    ocr.text = 'RFC ABC\nFECHA 30/12/2026\nTOTAL 1,234.5';
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pumpAndSettle();
    expect(find.text(OcrReviewTexts.dateWarning), findsOneWidget);
    expect(find.text(OcrReviewTexts.notRead), findsNWidgets(2));
    expect(find.text('12/11/2026'), findsOneWidget);
  });

  testWidgets('CA-074 a CA-076: ilegible, Repetir foto vuelve a leer',
      (tester) async {
    ocr.text = '%%%';
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pumpAndSettle();
    expect(find.text(OcrMessages.illegible), findsOneWidget);

    ocr.text = legible;
    await tapText(tester, 'Repetir foto');
    expect(receipts.discarded, hasLength(1));
    await tapText(tester, 'Tomar foto');
    await tapText(tester, 'Usar foto');
    expect(find.text(OcrReviewTexts.title), findsOneWidget);
    expect(ocr.received, hasLength(2));
  });

  testWidgets('CA-075: ilegible y Registrar manualmente conserva la foto',
      (tester) async {
    ocr.text = '';
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pumpAndSettle();
    await tapText(tester, 'Registrar manualmente');
    expect(find.text('Registrar egreso'), findsOneWidget);
    expect(find.text('Foto del recibo adjunta'), findsOneWidget);
    expect(receipts.discarded, isEmpty);
  });

  testWidgets(
      'CA-077 / CA-145 / CA-146: sin internet, Reintentar al volver '
      'la red, sin reiniciar la app', (tester) async {
    ocr.error = const OcrException(OcrFailureKind.noConnection);
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pumpAndSettle();
    expect(find.text(OcrMessages.noConnection), findsOneWidget);
    expect(find.text('Registrar manualmente'), findsOneWidget);

    ocr.error = null;
    await tapText(tester, 'Reintentar');
    expect(find.text(OcrReviewTexts.title), findsOneWidget);
  });

  testWidgets('CA-078: error del servicio y Registrar manualmente con foto',
      (tester) async {
    ocr.error = const OcrException(OcrFailureKind.server);
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pumpAndSettle();
    expect(find.text(OcrMessages.server), findsOneWidget);
    await tapText(tester, 'Registrar manualmente');
    expect(find.text('Foto del recibo adjunta'), findsOneWidget);
  });

  testWidgets('CA-079: más de 10 s es tiempo agotado', (tester) async {
    ocr.delay = const Duration(seconds: 30);
    await pumpApp(tester);
    await scanAndUse(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Leyendo el recibo…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(OcrMessages.timeout), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
      'CA-080 / CA-081: Cancelar abre el registro manual con la foto '
      'y la respuesta tardía se ignora', (tester) async {
    ocr.delay = const Duration(seconds: 3);
    await pumpApp(tester);
    await scanAndUse(tester);
    await tapText(tester, 'Cancelar');
    expect(find.text('Registrar egreso'), findsOneWidget);
    expect(find.text('Foto del recibo adjunta'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text(OcrReviewTexts.title), findsNothing);
    expect(find.text('39.50'), findsNothing);
    expect(repo.rows, isEmpty);
  });
}
