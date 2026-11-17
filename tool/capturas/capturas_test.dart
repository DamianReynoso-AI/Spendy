// Genera las capturas de pantalla del manual de usuario (RNF-49) en
// docs/img/manual/. No es una prueba de aceptación: arma la app con datos
// de ejemplo y servicios simulados (cámara y OCR) y guarda una imagen PNG
// de cada paso, con la fuente Roboto real de Flutter.
//
// Uso:  flutter test tool/capturas/capturas_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:spendy/core/result.dart';
import 'package:spendy/modules/receipts/receipt_service.dart';
import 'package:spendy/app.dart';
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/ocr/mock_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/ocr/receipt_parser.dart';
import 'package:spendy/modules/privacy/onboarding_service.dart';
import 'package:spendy/modules/receipts/camera_service.dart';
import 'package:spendy/modules/search/movement_filter.dart';
import 'package:spendy/modules/summary/summary_service.dart';

import '../../test/widget/movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import '../../test/widget/receipt_screens_test.dart'
    show FakeDevice, FakeReceipts;
import '../../test/widget/summary_screens_test.dart'
    show FakeExports, MemorySettings;

const String receiptText = 'FARMACIA SAN JUAN\nFECHA 14/11/2026\n'
    'SUBTOTAL 245.69\nTOTAL \$285.00\nEFECTIVO 300.00';

String _fontsDir() {
  final exe = Platform.resolvedExecutable;
  final root = exe.substring(0, exe.indexOf('/bin/cache/'));
  return '$root/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  final dir = _fontsDir();
  ByteData read(String name) => ByteData.sublistView(
        File('$dir/$name').readAsBytesSync(),
      );
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(Future.value(read('Roboto-$w.ttf')));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(read('MaterialIcons-Regular.otf'))))
      .load();
}

/// Foto de ejemplo de un recibo, dibujada con la fuente de mapa de bits
/// del paquete `image`.
String _sampleReceipt() {
  final picture = img.Image(width: 360, height: 520);
  img.fill(picture, color: img.ColorRgb8(238, 233, 222));
  img.fillRect(picture,
      x1: 50, y1: 30, x2: 310, y2: 490, color: img.ColorRgb8(255, 255, 255));
  var y = 60;
  for (final line in receiptText.split('\n')) {
    img.drawString(picture, line,
        font: img.arial14, x: 70, y: y, color: img.ColorRgb8(30, 30, 30));
    y += 40;
  }
  final file = File('${Directory.systemTemp.createTempSync().path}/r.jpg')
    ..writeAsBytesSync(img.encodeJpg(picture));
  return file.path;
}

/// Recibos simulados que sí devuelven una foto existente.
class _PhotoReceipts extends FakeReceipts {
  _PhotoReceipts(this.photo);
  final String photo;

  @override
  Future<Result<TempReceipt>> storeCapture(String capturedPath) async =>
      Success(
          TempReceipt(path: photo, sizeBytes: 10, capturedAt: DateTime(2026)));
}

void main() {
  autoUpdateGoldenFiles = true;
  WidgetsApp.debugAllowBannerOverride = false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('capturas del manual de usuario', (tester) async {
    await tester.runAsync(_loadFonts);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    final repo = MemoryMovementRepository();
    final catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    final service =
        MovementService(repository: repo, catalog: catalog, logger: logger);
    final photo = await tester.runAsync(() async => _sampleReceipt());
    final receipts = _PhotoReceipts(photo!)
      ..ocr = OcrService(
        adapter: MockOcrAdapter(text: receiptText),
        logger: logger,
        parser: ReceiptParser(clock: () => today),
      );

    var shot = 0;
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5)); // cierra avisos breves
      await tester.pumpAndSettle();
      shot++;
      final file = '${shot.toString().padLeft(2, '0')}_$name.png';
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../docs/img/manual/$file'),
      );
    }

    Future<void> tapText(String text) async {
      final target = find.text(text).last;
      if (find.text(text).evaluate().isEmpty) {
        await tester.dragUntilVisible(
          find.text(text),
          find.byType(ListView).last,
          const Offset(0, -300),
        );
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    Future<void> choose(Type type, String option) async {
      await tester.tap(find.byType(type).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(SpendyApp(
      service: service,
      catalog: catalog,
      receipts: receipts,
      camera: CameraService(FakeDevice(), logger),
      onboarding: OnboardingService(MemorySettings(), logger),
      summary: SummaryService(repository: repo, logger: logger),
      exports: FakeExports(),
      filter: MovementFilter(repository: repo, logger: logger),
    ));
    await capture('aviso_privacidad');
    await tapText(PrivacyTexts.acceptButton);
    await capture('inicio_vacio');

    // Registrar un ingreso y un egreso.
    await tapText('Registrar mi primer movimiento');
    await tapText('Ingreso');
    await tester.enterText(find.byType(TextField).first, '15000');
    await choose(DropdownButton<int>, 'Sueldos y salarios');
    await tapText('Guardar');
    await tapText('Registrar');
    await tester.enterText(find.byType(TextField).first, '350');
    await choose(DropdownButton<int>, 'Alimentos');
    await choose(DropdownButton<PaymentMethod>, 'Efectivo');
    await tester.enterText(find.byType(TextField).at(1), 'Tacos El Güero');
    await capture('formulario_egreso');
    await tapText('Guardar');
    await capture('inicio_con_balance');

    // Detalle, edición y eliminación.
    await tapText('Tacos El Güero');
    await capture('detalle');
    await tapText('Eliminar');
    await capture('confirmar_eliminar');
    await tapText('Cancelar');
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    // Escanear un recibo.
    await tester.tap(find.byTooltip('Escanear recibo'));
    await tester.pumpAndSettle();
    await tapText('Tomar foto');
    await tapText('Usar foto');
    await capture('revision_ocr');
    await choose(DropdownButton<int>, 'Servicios');
    await choose(DropdownButton<PaymentMethod>, 'Efectivo');
    await tapText('Guardar');

    // Búsqueda y filtros.
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar en descripción o nota'),
      'farmacia',
    );
    await capture('busqueda_filtros');
    await tapText('Limpiar filtros');

    // Resumen anual y exportación.
    await tester.tap(find.byTooltip('Resumen anual'));
    await capture('resumen_anual');
  });
}
