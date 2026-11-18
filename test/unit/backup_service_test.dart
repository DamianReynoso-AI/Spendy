// Pruebas de la copia de seguridad cifrada (M-16; TEC-02).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/categories.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/image_store.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/models/receipt.dart';
import 'package:spendy/data/repositories/budget_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/data/repositories/receipt_repository.dart';
import 'package:spendy/modules/backup/backup_codec.dart';
import 'package:spendy/modules/backup/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String password = 'mi-clave-segura';

Movement expense(int cents, DateTime date) => Movement(
      type: MovementType.egreso,
      amountCents: cents,
      date: date,
      categoryId: 1,
      paymentMethod: 'efectivo',
      description: 'OXXO',
      createdAt: date,
      updatedAt: date,
    );

void main() {
  sqfliteFfiInit();
  final codec = BackupCodec(iterations: 1000);

  group('BackupCodec', () {
    final payload = BackupPayload(
      data: {'app': 'spendy', 'n': 1},
      images: {
        'a.jpg': Uint8List.fromList([1, 2, 3])
      },
    );

    test('cifra y descifra con la misma contraseña', () async {
      final bytes = await codec.encode(payload, password);
      expect(String.fromCharCodes(bytes.sublist(0, 8)), 'SPENDYBK');
      final back = await codec.decode(bytes, password);
      expect(back.data, payload.data);
      expect(back.images['a.jpg'], [1, 2, 3]);
    });

    test('el archivo no contiene los datos en claro', () async {
      final bytes = await codec.encode(
          const BackupPayload(data: {'nota': 'SECRETO-123'}, images: {}),
          password);
      expect(String.fromCharCodes(bytes).contains('SECRETO-123'), isFalse);
    });

    test('contraseña incorrecta, bytes alterados u otro archivo', () async {
      final bytes = await codec.encode(payload, password);
      Future<BackupError> errorOf(Uint8List b, String pw) async {
        try {
          await codec.decode(b, pw);
        } on BackupFormatException catch (e) {
          return e.error;
        }
        fail('debió fallar');
      }

      expect(await errorOf(bytes, 'otra-clave'), BackupError.wrongPassword);
      final tampered = Uint8List.fromList(bytes)..[60] ^= 0xFF;
      expect(await errorOf(tampered, password), BackupError.wrongPassword);
      expect(await errorOf(Uint8List.fromList([1, 2, 3]), password),
          BackupError.notBackup);
    });
  });

  group('BackupService con SQLite y archivos reales', () {
    late Directory tempDir;
    late Database db;
    late ImageStore images;
    late BackupService service;
    File? shared;

    Future<Database> openDb(String name) => openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate, path: p.join(tempDir.path, name));

    BackupService serviceFor(Database db, ImageStore images) => BackupService(
          db: db,
          images: images,
          directory: () async => tempDir,
          logger: ErrorLogger(
              () async => File(p.join(tempDir.path, errorLogFileName))),
          codec: codec,
          share: (file) async => shared = file,
          clock: () => DateTime(2026, 11, 18, 10),
        );

    setUp(() async {
      shared = null;
      tempDir = Directory.systemTemp.createTempSync('spendy_backup_');
      db = await openDb('a.db');
      images = ImageStore(Directory(p.join(tempDir.path, 'a')),
          freeSpace: (_) async => null);
      await images.init();
      service = serviceFor(db, images);
    });

    tearDown(() async {
      await db.close();
      tempDir.deleteSync(recursive: true);
    });

    Future<void> seed() async {
      final repo = MovementRepository(db, imageStore: images);
      await repo.insert(expense(15000, DateTime(2026, 11, 1)));
      final temp = await images.writeTemp(Uint8List.fromList([9, 9, 9, 9]));
      await repo.insertWithReceipt(
        expense(39950, DateTime(2026, 11, 2)),
        PendingReceipt(
          file: temp,
          sizeBytes: 4,
          capturedAt: DateTime(2026, 11, 2),
        ),
      );
      await BudgetRepository(db).setLimit(1, 300000);
    }

    test('exporta con el nombre del día y lo entrega a compartir', () async {
      await seed();
      final r = await service.export(password);
      expect(r.isSuccess, isTrue);
      expect(p.basename(shared!.path), 'spendy_respaldo_2026-11-18.spendy');
    });

    test('contraseña corta no exporta', () async {
      final r = await service.export('corta');
      expect(r.errorOrNull!.message, BackupMessages.shortPassword);
      expect(shared, isNull);
    });

    test('restaura todo en otro "teléfono", fotos incluidas', () async {
      await seed();
      await service.export(password);
      final bytes = await shared!.readAsBytes();

      final db2 = await openDb('b.db');
      final images2 = ImageStore(Directory(p.join(tempDir.path, 'b')),
          freeSpace: (_) async => null);
      final other = serviceFor(db2, images2);
      final r = await other.restore(bytes, password);
      final summary = r.valueOrNull!;
      expect(summary.movements, 2);
      expect(summary.receipts, 1);
      expect(summary.budgets, 1);

      final movements = await MovementRepository(db2).fetchAll();
      expect(movements.map((m) => m.amountCents), containsAll([15000, 39950]));
      final receipt = await ReceiptRepository(db2, images2).findByMovement(
          movements.firstWhere((m) => m.amountCents == 39950).id!);
      expect(
          await images2.resolve(receipt!.filePath).readAsBytes(), [9, 9, 9, 9]);
      expect(await BudgetRepository(db2).fetchAll(), {1: 300000});
      await db2.close();
    });

    test('restaurar reemplaza los datos y borra las fotos anteriores',
        () async {
      await MovementRepository(db).insert(expense(100, DateTime(2026, 1, 1)));
      final empty = await service.export(password);
      expect(empty.isSuccess, isTrue);
      final backup = await shared!.readAsBytes();

      await seed();
      final r = await service.restore(backup, password);
      expect(r.isSuccess, isTrue);
      final all = await MovementRepository(db).fetchAll();
      expect(all.single.amountCents, 100);
      expect(await BudgetRepository(db).fetchAll(), isEmpty);
      final files = images.receiptsDir
          .listSync()
          .where((f) => p.basename(f.path) != noMediaFileName);
      expect(files, isEmpty);
    });

    test('contraseña incorrecta no toca los datos actuales', () async {
      await seed();
      await service.export(password);
      final bytes = await shared!.readAsBytes();
      await MovementRepository(db).insert(expense(1, DateTime(2026, 1, 1)));
      final r = await service.restore(bytes, 'equivocada');
      expect(r.errorOrNull!.message, BackupMessages.wrongPassword);
      expect(await MovementRepository(db).fetchAll(), hasLength(3));
    });

    test('rechaza nombres de foto que salen de la carpeta', () async {
      final evil = await codec.encode(
        BackupPayload(
          data: {
            'app': 'spendy',
            'formato': 1,
            'movimientos': [
              {
                ...expense(100, DateTime(2026, 1, 1)).toRow(),
                'id': 1,
              },
            ],
            'recibos': [
              {
                'id': 1,
                'movimiento_id': 1,
                'archivo': '../../evil.jpg',
                'capturado_en': '2026-01-01T00:00:00.000',
              },
            ],
            'presupuestos': [],
          },
          images: {
            '../../evil.jpg': Uint8List.fromList([1])
          },
        ),
        password,
      );
      final r = await service.restore(evil, password);
      expect(r.errorOrNull!.message, BackupMessages.corrupted);
      expect(File(p.join(tempDir.path, 'evil.jpg')).existsSync(), isFalse);
    });

    test('un respaldo de una versión más nueva pide actualizar', () async {
      final newer = await codec.encode(
        const BackupPayload(data: {'app': 'spendy', 'formato': 99}, images: {}),
        password,
      );
      final r = await service.restore(newer, password);
      expect(r.errorOrNull!.message, BackupMessages.newerVersion);
    });
  });
}
