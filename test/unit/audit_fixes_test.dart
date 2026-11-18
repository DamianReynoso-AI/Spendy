// Pruebas de las correcciones de la auditoría del 18/11/2026 (AUD-03,
// AUD-04, AUD-07, AUD-13, AUD-14, AUD-16, AUD-17, AUD-18, AUD-19).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/app_config.dart';
import 'package:spendy/config/categories.dart';
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/modules/export/export_service.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_adapter.dart';
import 'package:spendy/modules/security/biometric_service.dart';
import 'package:spendy/modules/security/pin_hasher.dart';
import 'package:spendy/modules/security/pin_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Device implements BiometricAuthenticator {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.available;
  @override
  Future<String> enrollment() async => 'fingerprint';
  @override
  Future<BiometricOutcome> authenticate(String reason) async =>
      BiometricOutcome.success;
}

class _KeyGuard implements BiometricKeyGuard {
  bool? valid = true;
  final List<String> calls = [];
  @override
  Future<void> create() async => calls.add('create');
  @override
  Future<bool?> isValid() async => valid;
  @override
  Future<void> delete() async => calls.add('delete');
}

Movement _movement(int i, {int cents = 1000}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: i));
  return Movement(
    type: MovementType.egreso,
    amountCents: cents,
    date: DateTime(2026, 1, 1).add(Duration(days: i % 300)),
    categoryId: 1,
    paymentMethod: 'efectivo',
    description: 'Comercio $i',
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late ErrorLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_aud_');
    logger = ErrorLogger(() async => File(p.join(tempDir.path, 'e.log')));
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  group('AUD-04 bloqueo del PIN', () {
    late MemorySecureBackend backend;
    late DateTime now;
    int? uptime;

    PinService service() => PinService(
          store: SecureStore(backend),
          logger: logger,
          hasher: PinHasher(iterations: 10, runner: (w) async => w()),
          clock: () => now,
          uptime: () async => uptime,
        );

    Future<PinCheck> failFive(PinService pins) async {
      PinCheck last = const PinAccepted();
      for (var i = 0; i < AppConfig.maxPinAttempts; i++) {
        last = await pins.verify('000000');
      }
      return last;
    }

    setUp(() async {
      backend = MemorySecureBackend();
      now = DateTime.utc(2026, 11, 18, 12);
      uptime = 1000000;
      await service().activate('123456', '123456');
    });

    test('adelantar la hora no quita el bloqueo', () async {
      final pins = service();
      expect(await failFive(pins), isA<PinLocked>());
      now = now.add(const Duration(hours: 5));
      uptime = uptime! + 5000;
      final check = await pins.verify('123456');
      expect(check, isA<PinLocked>());
      expect((check as PinLocked).remaining, const Duration(seconds: 25));
    });

    test('al pasar el tiempo real el bloqueo termina', () async {
      final pins = service();
      await failFive(pins);
      now = now.add(AppConfig.pinLockout);
      uptime = uptime! + AppConfig.pinLockout.inMilliseconds;
      expect(await pins.lockoutRemaining(), isNull);
      expect(await pins.verify('123456'), isA<PinAccepted>());
    });

    test('tras reiniciar el teléfono cuenta la hora normal', () async {
      final pins = service();
      await failFive(pins);
      uptime = 2000; // el reloj monótono volvió a empezar
      now = now.add(const Duration(seconds: 10));
      expect(await pins.lockoutRemaining(), const Duration(seconds: 20));
    });

    test('los bloqueos seguidos escalan y un PIN correcto los reinicia',
        () async {
      final pins = service();
      final steps = <Duration>[];
      for (var round = 0; round < 6; round++) {
        final locked = await failFive(pins) as PinLocked;
        steps.add(locked.remaining);
        now = now.add(locked.remaining);
        uptime = uptime! + locked.remaining.inMilliseconds;
      }
      expect(steps, [
        ...AppConfig.pinLockoutSteps,
        AppConfig.pinLockoutSteps.last,
      ]);
      expect(await pins.verify('123456'), isA<PinAccepted>());
      expect(
          (await failFive(pins) as PinLocked).remaining, AppConfig.pinLockout);
    });

    test('el aviso dice minutos desde un minuto', () {
      expect(PinMessages.locked(const Duration(minutes: 5)),
          contains('5 minutos'));
      expect(PinMessages.locked(const Duration(seconds: 61)),
          contains('2 minutos'));
      expect(PinMessages.locked(const Duration(seconds: 30)),
          contains('30 segundos'));
    });

    test('sin reloj monótono se comporta como antes', () async {
      uptime = null;
      final pins = service();
      await failFive(pins);
      now = now.add(AppConfig.pinLockout);
      expect(await pins.lockoutRemaining(), isNull);
    });
  });

  group('AUD-14 huellas nuevas', () {
    late SecureStore store;
    late _KeyGuard guard;
    late BiometricService biometrics;

    setUp(() {
      store = SecureStore(MemorySecureBackend());
      guard = _KeyGuard();
      biometrics = BiometricService(
        store: store,
        logger: logger,
        authenticator: _Device(),
        keyGuard: guard,
      );
    });

    test('activar crea la llave y desactivar la borra', () async {
      await biometrics.enable();
      await biometrics.disable();
      expect(guard.calls, ['create', 'delete']);
    });

    test('si Android invalidó la llave se pide el PIN y se apaga', () async {
      await biometrics.enable();
      guard.valid = false;
      final unlock = await biometrics.unlock();
      expect(unlock.success, isFalse);
      expect(unlock.message, BiometricMessages.changed);
      expect(await biometrics.isEnabled(), isFalse);
    });

    test('si no se puede saber, decide la lista de tipos', () async {
      await biometrics.enable();
      guard.valid = null;
      expect((await biometrics.unlock()).success, isTrue);
    });
  });

  group('AUD-17 tamaño de la respuesta del OCR', () {
    test('corta al pasar el límite', () async {
      final stream =
          Stream.fromIterable(List.generate(10, (_) => Uint8List(1024)));
      await expectLater(
        readLimited(stream, 4096),
        throwsA(isA<OcrException>()
            .having((e) => e.kind, 'kind', OcrFailureKind.server)),
      );
    });

    test('deja pasar una respuesta normal', () async {
      final bytes = await readLimited(
          Stream.fromIterable([
            [1, 2],
            [3]
          ]),
          HttpClientTransport.maxResponseBytes);
      expect(bytes, [1, 2, 3]);
    });
  });

  group('AUD-16 copias temporales para compartir', () {
    test('se borran al abrir la app', () async {
      for (final name in sharedCopyFolders) {
        File(p.join(tempDir.path, name, 'x.csv'))
          ..createSync(recursive: true)
          ..writeAsStringSync('dato');
      }
      File(p.join(tempDir.path, 'otra.txt')).writeAsStringSync('se queda');
      await cleanSharedCopies(tempDir);
      for (final name in sharedCopyFolders) {
        expect(Directory(p.join(tempDir.path, name)).existsSync(), isFalse);
      }
      expect(File(p.join(tempDir.path, 'otra.txt')).existsSync(), isTrue);
    });
  });

  group('AUD-18 y AUD-19 base de datos', () {
    late Database db;
    late MovementRepository repository;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      repository = MovementRepository(db);
    });
    tearDown(() => db.close());

    test('las páginas siguen el orden de la lista completa', () async {
      for (var i = 0; i < 25; i++) {
        await db.insert('movimiento', _movement(i).toRow());
      }
      final all = await repository.fetchAll();
      final pages = [
        ...await repository.fetchPage(limit: 10, offset: 0),
        ...await repository.fetchPage(limit: 10, offset: 10),
        ...await repository.fetchPage(limit: 10, offset: 20),
      ];
      expect(pages.map((m) => m.id), all.map((m) => m.id));
      expect(await repository.fetchPage(limit: 10, offset: 30), isEmpty);
    });

    test('la base rechaza movimientos inválidos', () async {
      final bad = <Map<String, Object?>>[
        {..._movement(1).toRow(), 'monto_centavos': 0},
        {
          ..._movement(2).toRow(),
          'monto_centavos': AppConfig.maxAmountCents + 1
        },
        {..._movement(3).toRow(), 'tipo': 'otro'},
        {..._movement(4).toRow(), 'fecha': '18/11/2026'},
        {..._movement(5).toRow(), 'nota': 'x' * (AppConfig.maxNoteLength + 1)},
      ];
      for (final row in bad) {
        await expectLater(db.insert('movimiento', row), throwsA(anything),
            reason: '$row');
      }
      expect(await db.insert('movimiento', _movement(6).toRow()), isPositive);
    });

    test('la base rechaza rutas de recibo fuera de la carpeta', () async {
      final id = await db.insert('movimiento', _movement(7).toRow());
      Map<String, Object?> receipt(String path) => {
            'movimiento_id': id,
            'ruta_archivo': path,
            'tamano_bytes': 10,
            'capturado_en': '2026-11-18T10:00:00',
          };
      await expectLater(
          db.insert('recibo', receipt('../../databases/spendy.db')),
          throwsA(anything));
      await expectLater(
          db.insert('recibo', receipt('/data/x.jpg')), throwsA(anything));
      expect(await db.insert('recibo', receipt('recibos/a.jpg')), isPositive);
    });

    test('una base v2 se actualiza a v3 sin perder datos', () async {
      // Base v2: se crea con la app y se le quita lo que agrega la v3.
      final created = await openSpendyDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: p.join(tempDir.path, 'a.db'));
      await created.insert('movimiento', _movement(1).toRow());
      for (final t in [
        'movimiento_valido_insert',
        'movimiento_valido_update',
        'recibo_valido_insert',
        'recibo_valido_update',
      ]) {
        await created.execute('DROP TRIGGER $t');
      }
      await created.setVersion(2);
      await created.close();
      final upgraded = await openSpendyDatabase(
          factory: databaseFactoryFfiNoIsolate,
          path: p.join(tempDir.path, 'a.db'));
      expect(await upgraded.getVersion(), schemaVersion);
      expect(await MovementRepository(upgraded).fetchAll(), hasLength(1));
      await expectLater(
          upgraded.insert(
              'movimiento', {..._movement(2).toRow(), 'monto_centavos': -1}),
          throwsA(anything));
      await upgraded.close();
    });
  });

  group('AUD-03, AUD-13 manifiesto de Android', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('sin respaldo automático ni transferencia', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(manifest,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final rules =
          File('android/app/src/main/res/xml/data_extraction_rules.xml')
              .readAsStringSync();
      expect(RegExp('<exclude domain="database"').allMatches(rules).length, 2);
    });

    test('quita los permisos que no se usan', () {
      for (final permission in [
        'RECORD_AUDIO',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
      ]) {
        expect(
            manifest,
            contains('android.permission.$permission" '
                'tools:node="remove"'));
      }
    });
  });

  group('AUD-06, AUD-07 aviso de privacidad', () {
    final text = PrivacyTexts.paragraphs.join('\n');

    test('incluye los elementos mínimos', () {
      for (final piece in [
        'Responsable: Zenorbak 2',
        'Qué datos y para qué',
        'respaldo automático de Android',
        'Google (Gemini)',
        'fuera de México',
        'mejorar sus productos',
        'Tus derechos (acceso, rectificación, cancelación y oposición)',
        'Ajustes > Aviso de privacidad',
        'ML Kit',
      ]) {
        expect(text, contains(piece));
      }
    });
  });
}
