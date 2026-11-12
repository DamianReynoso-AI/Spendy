// Pruebas del incremento 3 para M-04 (ReceiptService, CameraService) y el
// guardado atómico de M-11 (MovementRepository + ReceiptRepository) con
// SQLite real en archivo temporal.
// CA-023, CA-041 a CA-043, CA-047, CA-048, CA-050, CA-051, CA-053 a CA-055,
// CA-057, CA-059 a CA-061; RNF-12, RNF-20, RNF-21.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:spendy/config/app_config.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/image_store.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/data/repositories/receipt_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/receipts/camera_service.dart';
import 'package:spendy/modules/receipts/receipt_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// JPEG pequeño y válido para las pruebas que no miden compresión.
Uint8List smallJpeg() =>
    img.encodeJpg(img.Image(width: 40, height: 30), quality: 90);

/// Imagen con ruido: casi no se comprime, así obliga a bajar calidad y
/// tamaño para llegar a 1.5 MB.
Uint8List noisyPng(int width, int height) {
  final random = Random(7);
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = random.nextInt(256)
      ..g = random.nextInt(256)
      ..b = random.nextInt(256);
  }
  return img.encodePng(image, level: 0);
}

class FakeHandle implements CameraHandle {
  FakeHandle(this.capturePath);
  final String capturePath;
  Object? captureError;
  bool disposed = false;

  @override
  Widget buildPreview() => const SizedBox();

  @override
  Future<String> takePicture() async {
    final error = captureError;
    if (error != null) throw error;
    return capturePath;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeDevice implements CameraDevice {
  CameraPermissionState permission = CameraPermissionState.granted;
  Object? openError;
  Object? permissionError;
  late FakeHandle handle = FakeHandle('/tmp/captura.jpg');
  int requests = 0;

  @override
  Future<CameraPermissionState> requestPermission() async {
    requests++;
    final error = permissionError;
    if (error != null) throw error;
    return permission;
  }

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<CameraHandle> open() async {
    final error = openError;
    if (error != null) throw error;
    return handle;
  }
}

class CameraBusyException implements Exception {
  @override
  String toString() => 'CameraBusyException: monto 350.00 comercio Oxxo';
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late File logFile;
  late ErrorLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_receipts_');
    logFile = File(p.join(tempDir.path, errorLogFileName));
    logger = ErrorLogger(() async => logFile);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('RNF-12 / CA-043: compresión a 1.5 MB o menos', () {
    test('una foto grande con ruido queda en 1.5 MB o menos', () {
      final input = noisyPng(3000, 2000);
      expect(input.length, greaterThan(AppConfig.maxReceiptBytes));
      final output = compressReceiptImage(input);
      expect(output.length, lessThanOrEqualTo(AppConfig.maxReceiptBytes));
      final decoded = img.decodeJpg(output)!;
      expect(decoded.width, lessThanOrEqualTo(AppConfig.receiptMaxSidePx));
    });

    test('el lado mayor se limita y se conserva la proporción vertical', () {
      final input = img.encodeJpg(img.Image(width: 1500, height: 3000));
      final decoded = img.decodeJpg(compressReceiptImage(input))!;
      expect(decoded.height, AppConfig.receiptMaxSidePx);
      expect(decoded.width, AppConfig.receiptMaxSidePx ~/ 2);
    });

    test('con un límite pequeño también reduce el tamaño en píxeles', () {
      final output = compressReceiptImage(noisyPng(800, 600), maxBytes: 30000);
      expect(output.length, lessThanOrEqualTo(30000));
    });

    test('una imagen pequeña se vuelve JPEG sin crecer de tamaño', () {
      final output = compressReceiptImage(smallJpeg());
      expect(img.decodeJpg(output), isNotNull);
      expect(output.length, lessThanOrEqualTo(AppConfig.maxReceiptBytes));
    });

    test('un archivo que no es imagen lanza FormatException', () {
      expect(
        () => compressReceiptImage(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('si no cabe ni a tamaño mínimo lanza FormatException', () {
      expect(
        () => compressReceiptImage(noisyPng(100, 100), maxBytes: 10),
        throwsFormatException,
      );
    });
  });

  group('con SQLite real y archivos', () {
    late Database db;
    late ImageStore store;
    late ReceiptService receipts;
    late MovementService movements;
    late MovementRepository movementRepo;
    late int compressCalls;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: factory,
        path: p.join(tempDir.path, databaseFileName),
      );
      store = ImageStore(
        Directory(p.join(tempDir.path, 'privado')),
        freeSpace: (_) async => null,
      );
      await store.init();
      compressCalls = 0;
      receipts = ReceiptService(
        store: store,
        repository: ReceiptRepository(db, store),
        logger: logger,
        compressor: (bytes) async {
          compressCalls++;
          return compressReceiptImage(bytes);
        },
        clock: () => DateTime(2026, 11, 12, 10),
      );
      movementRepo = MovementRepository(db, imageStore: store);
      movements = MovementService(
        repository: movementRepo,
        catalog: CategoryCatalog(CategoryRepository(db), logger),
        logger: logger,
        clock: () => DateTime(2026, 11, 12, 10),
      );
    });

    tearDown(() => db.close());

    MovementDraft expense() => MovementDraft(
          type: MovementType.egreso,
          amountText: '350.00',
          date: DateTime(2026, 11, 12),
          categoryId: 1,
          paymentMethod: PaymentMethod.efectivo,
          description: 'Oxxo',
        );

    /// Simula la foto que deja la cámara en la caché del sistema.
    Future<String> cameraFile() async {
      final file = File(p.join(tempDir.path, 'cache_${compressCalls}_x.jpg'));
      await file.writeAsBytes(smallJpeg());
      return file.path;
    }

    Future<TempReceipt> acceptedPhoto() async {
      final raw = (await receipts.storeCapture(await cameraFile())).valueOrNull!;
      return (await receipts.accept(raw)).valueOrNull!;
    }

    Future<int> count(String table) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table'))!;

    List<String> filesIn(Directory dir) => dir
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n != noMediaFileName)
        .toList();

    test('CA-040 / CA-043: capturar y "Usar foto" deja un JPEG comprimido',
        () async {
      final source = await cameraFile();
      final raw = (await receipts.storeCapture(source)).valueOrNull!;
      expect(File(source).existsSync(), isFalse);
      expect(raw.compressed, isFalse);
      final accepted = (await receipts.accept(raw)).valueOrNull!;
      expect(accepted.compressed, isTrue);
      expect(File(raw.path).existsSync(), isFalse);
      expect(accepted.sizeBytes, File(accepted.path).lengthSync());
      expect(accepted.sizeBytes, lessThanOrEqualTo(AppConfig.maxReceiptBytes));
      expect((await receipts.accept(accepted)).valueOrNull, same(accepted));
      expect(compressCalls, 1);
    });

    test('CA-041: "Repetir" descarta la captura anterior', () async {
      final raw = (await receipts.storeCapture(await cameraFile())).valueOrNull!;
      await receipts.discard(raw);
      expect(File(raw.path).existsSync(), isFalse);
    });

    test('una foto dañada da un mensaje para repetirla', () async {
      final bad = File(p.join(tempDir.path, 'mala.jpg'))
        ..writeAsBytesSync([0, 1, 2]);
      final raw = (await receipts.storeCapture(bad.path)).valueOrNull!;
      final result = await receipts.accept(raw);
      expect(result.errorOrNull!.message, ReceiptMessages.processFailed);
    });

    test('CA-059: sin espacio al capturar, mensaje claro y nada a medias',
        () async {
      final full = ImageStore(store.root, freeSpace: (_) async => 10);
      final service = ReceiptService(
        store: full,
        repository: ReceiptRepository(db, full),
        logger: logger,
      );
      final source = await cameraFile();
      final result = await service.storeCapture(source);
      expect(result.errorOrNull!.type, ErrorType.storageFull);
      expect(result.errorOrNull!.message, ReceiptMessages.storageFull);
      expect(filesIn(store.tempDir), isEmpty);
      expect(File(source).existsSync(), isFalse);
      expect(logFile.readAsStringSync(), contains('almacenamiento_lleno'));
    });

    test('RNF-21 / CA-031: egreso con foto se guarda junto con su recibo',
        () async {
      final photo = await acceptedPhoto();
      final saved = await movements.save(expense(), receipt: photo);
      final id = saved.valueOrNull!;
      expect(await count('movimiento'), 1);
      expect(await count('recibo'), 1);
      expect(File(photo.path).existsSync(), isFalse);
      expect(filesIn(store.tempDir), isEmpty);
      expect(filesIn(store.receiptsDir), [p.basename(photo.path)]);
      final view = (await receipts.receiptOf(id)).valueOrNull!;
      expect(view.exists, isTrue);
      expect(File(view.path).existsSync(), isTrue);
    });

    test('CA-060 / CA-061: si falla un paso, rollback y sin archivos',
        () async {
      final photo = await acceptedPhoto();
      // El archivo temporal desaparece: el paso 3 (mover) falla.
      File(photo.path).deleteSync();
      final result = await movements.save(expense(), receipt: photo);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorOrNull!.message,
        endsWith(MovementMessages.receiptDiscarded),
      );
      expect(await count('movimiento'), 0);
      expect(await count('recibo'), 0);
      expect(filesIn(store.receiptsDir), isEmpty);
    });

    test('si falla la base, se borra la foto temporal (CA-060)', () async {
      final photo = await acceptedPhoto();
      await db.execute('DROP TABLE recibo');
      final result = await movements.save(expense(), receipt: photo);
      expect(result.isSuccess, isFalse);
      expect(File(photo.path).existsSync(), isFalse);
      expect(await count('movimiento'), 0);
    });

    test('los ingresos no llevan recibo', () async {
      final photo = await acceptedPhoto();
      final result = await movements.save(
        MovementDraft(
          type: MovementType.ingreso,
          amountText: '100',
          date: DateTime(2026, 11, 12),
          categoryId: 7,
        ),
        receipt: photo,
      );
      expect(result.errorOrNull!.message, MovementMessages.incomeNoReceipt);
      expect(await count('movimiento'), 0);
    });

    test('egreso sin foto se guarda como antes y no tiene recibo', () async {
      final id = (await movements.save(expense())).valueOrNull!;
      expect((await receipts.receiptOf(id)).valueOrNull, isNull);
    });

    test('CA-023: eliminar el egreso borra su recibo y su archivo', () async {
      final id =
          (await movements.save(expense(), receipt: await acceptedPhoto()))
              .valueOrNull!;
      expect(filesIn(store.receiptsDir), hasLength(1));
      expect((await movements.delete(id)).isSuccess, isTrue);
      expect(await count('recibo'), 0);
      expect(filesIn(store.receiptsDir), isEmpty);
    });

    test('CA-053: agregar recibo a un egreso que no tenía', () async {
      final id = (await movements.save(expense())).valueOrNull!;
      final raw = (await receipts.storeCapture(await cameraFile())).valueOrNull!;
      expect((await receipts.attach(id, raw)).isSuccess, isTrue);
      expect((await receipts.receiptOf(id)).valueOrNull!.exists, isTrue);
      expect(filesIn(store.tempDir), isEmpty);
    });

    test('CA-055: reemplazar borra el archivo anterior', () async {
      final first = await acceptedPhoto();
      final id = (await movements.save(expense(), receipt: first)).valueOrNull!;
      final oldPath = (await receipts.receiptOf(id)).valueOrNull!.path;
      expect((await receipts.attach(id, await acceptedPhoto())).isSuccess,
          isTrue);
      final newPath = (await receipts.receiptOf(id)).valueOrNull!.path;
      expect(newPath, isNot(oldPath));
      expect(File(oldPath).existsSync(), isFalse);
      expect(File(newPath).existsSync(), isTrue);
      expect(await count('recibo'), 1);
    });

    test('si reemplazar falla, el recibo anterior sigue intacto', () async {
      final id =
          (await movements.save(expense(), receipt: await acceptedPhoto()))
              .valueOrNull!;
      final oldPath = (await receipts.receiptOf(id)).valueOrNull!.path;
      final next = await acceptedPhoto();
      File(next.path).deleteSync();
      final result = await receipts.attach(id, next);
      expect(result.errorOrNull!.message, ReceiptMessages.saveFailed);
      expect((await receipts.receiptOf(id)).valueOrNull!.path, oldPath);
      expect(File(oldPath).existsSync(), isTrue);
    });

    test('CA-054: quitar recibo borra la fila y el archivo', () async {
      final id =
          (await movements.save(expense(), receipt: await acceptedPhoto()))
              .valueOrNull!;
      expect((await receipts.remove(id)).isSuccess, isTrue);
      expect((await receipts.receiptOf(id)).valueOrNull, isNull);
      expect(filesIn(store.receiptsDir), isEmpty);
      expect(await count('movimiento'), 1);
      expect((await receipts.remove(id)).isSuccess, isTrue);
    });

    test('CA-051: si falta el archivo, el detalle lo sabe sin fallar',
        () async {
      final id =
          (await movements.save(expense(), receipt: await acceptedPhoto()))
              .valueOrNull!;
      final view = (await receipts.receiptOf(id)).valueOrNull!;
      File(view.path).deleteSync();
      final again = (await receipts.receiptOf(id)).valueOrNull!;
      expect(again.exists, isFalse);
      expect((await movements.findById(id)).isSuccess, isTrue);
    });

    test('si la tabla no se puede leer, mensaje no técnico', () async {
      await db.execute('DROP TABLE recibo');
      final result = await receipts.receiptOf(1);
      expect(result.errorOrNull!.message, ReceiptMessages.loadFailed);
      expect((await receipts.remove(1)).isSuccess, isFalse);
      expect(await receipts.cleanOrphans(), 0);
    });

    test('TEC-06: cleanOrphans conserva solo los recibos registrados',
        () async {
      final id =
          (await movements.save(expense(), receipt: await acceptedPhoto()))
              .valueOrNull!;
      await acceptedPhoto(); // queda en temp_recibos/
      final orphan = await store.promote(await store.writeTemp(smallJpeg()));
      expect(await receipts.cleanOrphans(), 2);
      expect(orphan.existsSync(), isFalse);
      expect((await receipts.receiptOf(id)).valueOrNull!.exists, isTrue);
    });
  });

  group('CameraService (RF-15 a RF-17, RNF-20)', () {
    late FakeDevice device;
    late CameraService camera;

    setUp(() {
      device = FakeDevice();
      camera = CameraService(device, logger);
    });

    test('CA-042: pide el permiso al usarla por primera vez', () async {
      expect(await camera.ensurePermission(), CameraPermissionState.granted);
      expect(device.requests, 1);
    });

    test('CA-044: permiso negado se informa sin registrarse como fallo',
        () async {
      device.permission = CameraPermissionState.permanentlyDenied;
      expect(
        await camera.ensurePermission(),
        CameraPermissionState.permanentlyDenied,
      );
      device.openError = const CameraPermissionException();
      final result = await camera.open();
      expect(result.errorOrNull!.type, ErrorType.cameraPermission);
      expect(logFile.existsSync(), isFalse);
    });

    test('si pedir el permiso falla, cuenta como negado y se registra',
        () async {
      device.permissionError = StateError('plugin');
      expect(await camera.ensurePermission(), CameraPermissionState.denied);
      expect(logFile.readAsStringSync(), contains('camara'));
    });

    test('CA-047 / CA-048: cámara ocupada da mensaje no técnico y se '
        'registra solo el tipo de la excepción (RNF-20)', () async {
      device.openError = CameraBusyException();
      final result = await camera.open();
      expect(result.errorOrNull!.type, ErrorType.camera);
      expect(result.errorOrNull!.message, CameraMessages.cameraFailed);
      final log = logFile.readAsStringSync();
      expect(log, contains('camara | M-04 | CameraBusyException'));
      expect(log, isNot(contains('350')));
      expect(log, isNot(contains('Oxxo')));
    });

    test('captura correcta y fallo al capturar', () async {
      final handle = (await camera.open()).valueOrNull! as FakeHandle;
      expect((await camera.capture(handle)).valueOrNull, '/tmp/captura.jpg');
      handle.captureError = CameraBusyException();
      expect((await camera.capture(handle)).errorOrNull!.type, ErrorType.camera);
      await camera.close(handle);
      expect(handle.disposed, isTrue);
      expect(await camera.openSettings(), isTrue);
    });

    test('mapPermissionStatus traduce los estados del plugin', () {
      expect(
        mapPermissionStatus(PermissionStatus.granted),
        CameraPermissionState.granted,
      );
      expect(
        mapPermissionStatus(PermissionStatus.limited),
        CameraPermissionState.granted,
      );
      expect(
        mapPermissionStatus(PermissionStatus.denied),
        CameraPermissionState.denied,
      );
      expect(
        mapPermissionStatus(PermissionStatus.permanentlyDenied),
        CameraPermissionState.permanentlyDenied,
      );
      expect(
        mapPermissionStatus(PermissionStatus.restricted),
        CameraPermissionState.permanentlyDenied,
      );
    });
  });
}
