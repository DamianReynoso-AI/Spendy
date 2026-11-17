// Pruebas de pantallas del incremento 3 (M-01 con M-04 simulado): cámara,
// permiso negado, fallo de cámara, vista previa, descarte al salir y
// recibo en el detalle. CA-040, CA-041, CA-044 a CA-051, CA-053 a CA-058.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/receipts/camera_service.dart';
import 'package:spendy/modules/receipts/receipt_service.dart';
import 'package:spendy/ui/screens/movement_detail_screen.dart';

import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;

class FakeHandle implements CameraHandle {
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<String> takePicture() async => '/cache/foto.jpg';

  @override
  Future<void> dispose() async {}
}

class FakeDevice implements CameraDevice {
  CameraPermissionState permission = CameraPermissionState.granted;
  Object? openError;
  int settingsOpened = 0;

  @override
  Future<CameraPermissionState> requestPermission() async => permission;

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<CameraHandle> open() async {
    final error = openError;
    if (error != null) throw error;
    return FakeHandle();
  }
}

/// M-04 en memoria: no toca el disco.
class FakeReceipts implements ReceiptService {
  final List<String> discarded = [];
  final List<int> attached = [];
  final List<int> removed = [];
  ReceiptView? view;
  int captures = 0;

  /// Lectura OCR conectada (incremento 4); `null` = sin OCR.
  OcrService? ocr;

  @override
  bool get canRead => ocr != null;

  @override
  Future<Result<OcrRequest>> startReading(TempReceipt photo) async =>
      Success(ocr!.start(Uint8List.fromList([1, 2, 3])));

  @override
  Future<Result<TempReceipt>> storeCapture(String capturedPath) async =>
      Success(
        TempReceipt(
          path: '/no/existe/captura_${captures++}.jpg',
          sizeBytes: 10,
          capturedAt: DateTime(2026, 11, 12),
        ),
      );

  @override
  Future<Result<TempReceipt>> accept(TempReceipt raw) async => Success(
        TempReceipt(
          path: raw.path,
          sizeBytes: 5,
          capturedAt: raw.capturedAt,
          compressed: true,
        ),
      );

  @override
  Future<void> discard(TempReceipt temp) async => discarded.add(temp.path);

  @override
  Future<Result<ReceiptView?>> receiptOf(int movementId) async => Success(view);

  @override
  Future<Result<void>> attach(int movementId, TempReceipt temp) async {
    attached.add(movementId);
    return const Success(null);
  }

  @override
  Future<Result<void>> remove(int movementId) async {
    removed.add(movementId);
    view = null;
    return const Success(null);
  }

  @override
  Future<int> cleanOrphans() async => 0;
}

class BusyCamera implements Exception {}

void main() {
  late MemoryMovementRepository repo;
  late MovementService service;
  late CategoryCatalog catalog;
  late FakeDevice device;
  late FakeReceipts receipts;
  late CameraService camera;

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
    );
    device = FakeDevice();
    receipts = FakeReceipts();
    camera = CameraService(device, logger);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SpendyApp(
        service: service,
        catalog: catalog,
        receipts: receipts,
        camera: camera,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFormWithAmount(WidgetTester tester) async {
    await tester.tap(find.text('Registrar mi primer movimiento'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '350');
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Type type, String option) async {
    await tester.tap(find.byType(type));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'CA-044 a CA-046: permiso negado explica, ofrece Ajustes y '
      'registro manual', (tester) async {
    device.permission = CameraPermissionState.permanentlyDenied;
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await tapText(tester, 'Escanear recibo');

    expect(find.text('Sin permiso para usar la cámara'), findsOneWidget);
    expect(find.text(CameraMessages.permissionDenied), findsOneWidget);
    await tapText(tester, 'Abrir Ajustes');
    expect(device.settingsOpened, 1);

    await tapText(tester, 'Registrar manualmente');
    expect(find.text('Registrar egreso'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
  });

  testWidgets('permiso negado una vez permite volver a pedirlo',
      (tester) async {
    device.permission = CameraPermissionState.denied;
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await tapText(tester, 'Escanear recibo');
    expect(find.text('Permitir cámara'), findsOneWidget);
    device.permission = CameraPermissionState.granted;
    await tapText(tester, 'Permitir cámara');
    expect(find.text('Tomar foto'), findsOneWidget);
  });

  testWidgets('CA-047 a CA-049: cámara ocupada, Reintentar y datos intactos',
      (tester) async {
    device.openError = BusyCamera();
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await tapText(tester, 'Escanear recibo');

    expect(find.text(CameraMessages.cameraFailed), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    device.openError = null;
    await tapText(tester, 'Reintentar');
    expect(find.text('Tomar foto'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('350'), findsOneWidget);
  });

  testWidgets(
      'CA-040 / CA-041: vista previa, Repetir descarta y Usar foto '
      'adjunta; se guarda con el recibo', (tester) async {
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await choose(tester, DropdownButton<int>, 'Alimentos');
    await choose(tester, DropdownButton<PaymentMethod>, 'Efectivo');
    await tapText(tester, 'Escanear recibo');
    await tapText(tester, 'Tomar foto');

    expect(find.text('Usar foto'), findsOneWidget);
    expect(find.text('Repetir'), findsOneWidget);
    await tapText(tester, 'Repetir');
    expect(receipts.discarded, ['/no/existe/captura_0.jpg']);
    await tapText(tester, 'Tomar foto');
    await tapText(tester, 'Usar foto');

    expect(find.text('Foto del recibo adjunta'), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
    await tapText(tester, 'Guardar');
    expect(repo.rows, hasLength(1));
    expect(receipts.discarded, hasLength(1));
  });

  testWidgets(
      'CA-056 a CA-058: salir con foto pregunta; Seguir editando no '
      'cambia nada y Descartar borra la foto', (tester) async {
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await tapText(tester, 'Escanear recibo');
    await tapText(tester, 'Tomar foto');
    await tapText(tester, 'Usar foto');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar este registro?'), findsOneWidget);
    await tapText(tester, 'Seguir editando');
    expect(find.text('Foto del recibo adjunta'), findsOneWidget);
    expect(receipts.discarded, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tapText(tester, 'Descartar');
    expect(receipts.discarded, ['/no/existe/captura_0.jpg']);
    expect(find.text('Aún no tienes movimientos'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('"Quitar foto" en el formulario borra la foto temporal',
      (tester) async {
    await pumpApp(tester);
    await openFormWithAmount(tester);
    await tapText(tester, 'Escanear recibo');
    await tapText(tester, 'Tomar foto');
    await tapText(tester, 'Usar foto');
    await tapText(tester, 'Quitar foto');
    expect(receipts.discarded, hasLength(1));
    expect(find.text('Escanear recibo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar este registro?'), findsNothing);
  });

  group('detalle del egreso', () {
    late MovementItem item;

    setUp(() async {
      await service.save(
        MovementDraft(
          type: MovementType.egreso,
          amountText: '99.50',
          date: DateTime(2026, 11, 1),
          categoryId: 1,
          paymentMethod: PaymentMethod.efectivo,
        ),
      );
      item = (await service.list()).valueOrNull!.single;
    });

    Future<void> pumpDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MovementDetailScreen(
            service: service,
            catalog: catalog,
            movement: item,
            receipts: receipts,
            camera: camera,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sin recibo ofrece "Agregar recibo" (CA-053)', (tester) async {
      await pumpDetail(tester);
      await tapText(tester, 'Agregar recibo');
      await tapText(tester, 'Tomar foto');
      await tapText(tester, 'Usar foto');
      expect(receipts.attached, [item.id]);
      expect(find.text('Recibo agregado.'), findsOneWidget);
    });

    testWidgets('CA-051: si falta el archivo muestra aviso y no se cierra',
        (tester) async {
      receipts.view = const ReceiptView(path: '/no/existe.jpg', exists: false);
      await pumpDetail(tester);
      expect(find.text(ReceiptMessages.missingFile), findsOneWidget);
      expect(find.text('Detalle del movimiento'), findsOneWidget);
      expect(find.text('Reemplazar'), findsOneWidget);
    });

    testWidgets('CA-050: la miniatura abre el visor con zoom', (tester) async {
      receipts.view = const ReceiptView(path: '/no/existe.jpg', exists: true);
      await pumpDetail(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('Toca para ampliarla')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('CA-054: Quitar recibo pide confirmación; cancelar no cambia',
        (tester) async {
      receipts.view = const ReceiptView(path: '/no/existe.jpg', exists: false);
      await pumpDetail(tester);
      await tapText(tester, 'Quitar recibo');
      expect(find.text('¿Quitar el recibo?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(receipts.removed, isEmpty);

      await tapText(tester, 'Quitar recibo');
      await tapText(tester, 'Quitar');
      expect(receipts.removed, [item.id]);
      expect(find.text('Agregar recibo'), findsOneWidget);
    });

    testWidgets('CA-055: Reemplazar pide confirmación antes de la cámara',
        (tester) async {
      receipts.view = const ReceiptView(path: '/no/existe.jpg', exists: false);
      await pumpDetail(tester);
      await tapText(tester, 'Reemplazar');
      expect(find.text('¿Reemplazar el recibo?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(find.text('Tomar foto'), findsNothing);
      expect(receipts.attached, isEmpty);

      await tapText(tester, 'Reemplazar');
      await tester.tap(find.widgetWithText(FilledButton, 'Reemplazar'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Tomar foto');
      await tapText(tester, 'Usar foto');
      expect(receipts.attached, [item.id]);
      expect(find.text('Recibo reemplazado.'), findsOneWidget);
    });
  });
}
