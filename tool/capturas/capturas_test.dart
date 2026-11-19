// Genera las capturas de pantalla del manual de usuario (RNF-49, v1.1) en
// docs/img/manual/. No es una prueba de aceptación: arma la app con datos
// de ejemplo y servicios simulados (cámara y OCR) y guarda una imagen PNG
// de cada paso, con la fuente Roboto real de Flutter.
//
// Uso:  flutter test --dart-define=SPENDY_GEMINI_API_KEY=x \
//         tool/capturas/capturas_test.dart
// (la definición solo hace que el aviso de privacidad salga como en el APK
// con Gemini; la clave no se usa)
//
// Ojo: en flutter test, un TextStyle sin familia usa la fuente de pruebas
// (cuadros negros) y no se puede reemplazar. Los títulos de la barra
// superior (titleTextStyle en lib/ui/theme/spendy_theme.dart) no traen
// familia; para las capturas de v1.1 se agregó ahí fontFamily 'Roboto' solo
// mientras corría este script (en el teléfono ya se ve con Roboto).
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
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/data/image_store.dart';
import 'package:spendy/modules/backup/backup_service.dart';
import 'package:spendy/modules/budgets/budget_service.dart';
import 'package:spendy/modules/insights/insights_service.dart';
import 'package:spendy/modules/security/biometric_service.dart';
import 'package:spendy/modules/security/lock_controller.dart';
import 'package:spendy/modules/security/pin_service.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../test/widget/movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import '../../test/widget/receipt_screens_test.dart'
    show FakeDevice, FakeReceipts;
import '../../test/widget/summary_screens_test.dart'
    show FakeExports, MemorySettings;
import '../../test/widget/budget_screens_test.dart' show MemoryBudgetRepository;
import '../../test/widget/security_screens_test.dart' show FakeReset;
import '../../test/unit/pin_service_test.dart' show FakeBiometrics, fastHasher;

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

/// La copia de seguridad solo se abre hasta el diálogo de contraseña; no
/// toca la base.
class _NoDb implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  autoUpdateGoldenFiles = true;
  WidgetsApp.debugAllowBannerOverride = false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('capturas del manual de usuario', (tester) async {
    await tester.runAsync(_loadFonts);
    debugDisableShadows = false; // sombras reales, no bordes negros
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
    final budgetRows = MemoryBudgetRepository()
      ..limits[1] = 300000
      ..limits[2] = 80000
      ..limits[5] = 100000;
    final budgets = BudgetService(
      budgets: budgetRows,
      movements: repo,
      catalog: catalog,
      logger: logger,
    );

    // Datos de ejemplo: el mes pasado y lo que va de este mes.
    final last = DateTime(today.year, today.month - 1);
    Future<void> add(MovementType type, int pesos, DateTime date, int category,
        {String? method = 'debito', String? text}) async {
      await repo.insert(Movement(
        type: type,
        amountCents: pesos * 100,
        date: date,
        categoryId: category,
        paymentMethod: type == MovementType.egreso ? method : null,
        description: text,
        createdAt: date,
        updatedAt: date,
      ));
    }

    final day = today.day;
    DateTime thisMonth(int d) =>
        DateTime(today.year, today.month, d.clamp(1, day));
    await tester.runAsync(() async {
      await add(
          MovementType.ingreso, 15000, DateTime(last.year, last.month, 1), 7,
          text: 'Quincena');
      await add(
          MovementType.egreso, 4500, DateTime(last.year, last.month, 2), 3,
          method: 'transferencia', text: 'Renta');
      await add(
          MovementType.egreso, 2100, DateTime(last.year, last.month, 3), 1,
          text: 'Súper');
      await add(MovementType.egreso, 650, DateTime(last.year, last.month, 8), 2,
          text: 'Gasolina');
      await add(
          MovementType.egreso, 900, DateTime(last.year, last.month, 12), 5,
          text: 'Cine');
      await add(MovementType.ingreso, 15000, thisMonth(1), 7, text: 'Quincena');
      await add(MovementType.egreso, 4500, thisMonth(2), 3,
          method: 'transferencia', text: 'Renta');
      await add(MovementType.egreso, 1850, thisMonth(5), 1, text: 'Súper');
      await add(MovementType.egreso, 720, thisMonth(9), 2, text: 'Gasolina');
      await add(MovementType.egreso, 640, thisMonth(12), 4, text: 'Internet');
      await add(MovementType.egreso, 380, thisMonth(15), 5, text: 'Cine');
      await add(MovementType.egreso, 610, thisMonth(17), 1,
          method: 'efectivo', text: 'Mercado');
    });

    final photo = await tester.runAsync(() async => _sampleReceipt());
    final receipts = _PhotoReceipts(photo!)
      ..ocr = OcrService(
        adapter: MockOcrAdapter(text: receiptText),
        logger: logger,
        parser: ReceiptParser(clock: () => today),
      );

    final settings = MemorySettings();
    final backend = MemorySecureBackend();
    LockController newLock() {
      final store = SecureStore(backend);
      return LockController(
        pin: PinService(store: store, logger: logger, hasher: fastHasher()),
        biometrics: BiometricService(
          store: store,
          logger: logger,
          authenticator: FakeBiometrics(),
        ),
        reset: FakeReset(backend, settings),
        shield: const NoScreenShield(),
      );
    }

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
      if (find.text(text).evaluate().isEmpty) {
        await tester.dragUntilVisible(
          find.text(text),
          find.byType(Scrollable).last,
          const Offset(0, -300),
        );
      }
      final target = find.text(text).last;
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

    /// Deja que se decodifiquen las fotos (Image.file) antes de capturar.
    Future<void> decodeImages() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
      }
    }

    Future<void> tab(String label) async {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    Widget app(LockController lock) => SpendyApp(
          service: service,
          catalog: catalog,
          receipts: receipts,
          camera: CameraService(FakeDevice(), logger),
          onboarding: OnboardingService(settings, logger),
          summary: SummaryService(repository: repo, logger: logger),
          exports: FakeExports(),
          filter: MovementFilter(repository: repo, logger: logger),
          lock: lock,
          budgets: budgets,
          insights: InsightsService(repository: repo, logger: logger),
          backup: BackupService(
            db: _NoDb(),
            images: ImageStore(Directory.systemTemp),
            directory: () async => Directory.systemTemp,
            logger: logger,
          ),
        );

    final lock = newLock();
    await tester.runAsync(lock.init);
    await tester.pumpWidget(app(lock));
    await capture('aviso_privacidad');
    await tapText(PrivacyTexts.acceptButton);
    await capture('inicio');
    await tester.dragUntilVisible(find.byKey(const Key('budgets_card')),
        find.byType(Scrollable).first, const Offset(0, -300));
    await capture('inicio_presupuestos');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();

    // Registrar un egreso desde los accesos rápidos.
    await tester.tap(find.text('Egreso').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '350');
    await choose(DropdownButton<int>, 'Alimentos');
    await choose(DropdownButton<PaymentMethod>, 'Efectivo');
    await tester.enterText(find.byType(TextField).at(1), 'Tacos El Güero');
    await capture('formulario_egreso');
    await tapText('Guardar');

    // Movimientos: lista, detalle y eliminar.
    await tab('Movimientos');
    await capture('movimientos');
    await tapText('Tacos El Güero');
    await capture('detalle');
    await tapText('Eliminar');
    await capture('confirmar_eliminar');
    await tapText('Cancelar');
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();

    // Escanear un recibo.
    await tester.tap(find.bySemanticsLabel('Escanear recibo').last);
    await tester.pumpAndSettle();
    await tapText('Tomar foto');
    await tapText('Usar foto');
    await decodeImages();
    await capture('revision_ocr');
    await choose(DropdownButton<int>, 'Servicios');
    await choose(DropdownButton<PaymentMethod>, 'Efectivo');
    await tapText('Guardar');

    // Búsqueda y filtros.
    await tab('Movimientos');
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar en descripción o nota'),
      'super',
    );
    await capture('busqueda_filtros');
    await tapText('Limpiar filtros');

    // Resumen anual.
    await tab('Resumen');
    await capture('resumen_anual');

    // Ajustes, presupuestos, PIN y copia de seguridad.
    await tab('Ajustes');
    await capture('ajustes');
    await tapText('Presupuestos mensuales');
    await capture('presupuestos');
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pin_switch')));
    await tester.pumpAndSettle();
    await capture('activar_pin');
    // Al escribir el sexto número el PIN se envía solo.
    await tester.enterText(find.byKey(const Key('pin_field')), '482915');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin_field')), '482915');
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await capture('ajustes_pin_activo');
    await tapText('Crear copia de seguridad');
    await capture('crear_copia');
    await tapText('Cancelar');

    // Pantalla de bloqueo al volver a abrir la app.
    final locked = newLock();
    await tester.runAsync(locked.init);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(app(locked));
    await capture('bloqueo_pin');
    debugDisableShadows = true;
  });
}
