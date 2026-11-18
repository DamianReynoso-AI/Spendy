// Pruebas del incremento 7 para M-09 y M-11: PinService, BiometricService,
// LockController, ResetService y SecureStore.
// RF-45 a RF-50; RNF-15, RNF-19, RNF-20, RNF-22; CA-114 a CA-140.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/app_config.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/image_store.dart';
import 'package:spendy/data/repositories/settings_repository.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/modules/security/biometric_service.dart';
import 'package:spendy/modules/security/lock_controller.dart';
import 'package:spendy/modules/security/pin_hasher.dart';
import 'package:spendy/modules/security/pin_service.dart';
import 'package:spendy/modules/security/reset_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Hasher rápido y síncrono para las pruebas (mismo algoritmo).
PinHasher fastHasher() =>
    PinHasher(iterations: 1000, runner: (work) async => work());

/// Biometría simulada.
class FakeBiometrics implements BiometricAuthenticator {
  BiometricAvailability available = BiometricAvailability.available;
  String enrolled = 'fingerprint';
  BiometricOutcome next = BiometricOutcome.success;
  int prompts = 0;

  @override
  Future<BiometricAvailability> availability() async => available;

  @override
  Future<String> enrollment() async => enrolled;

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    prompts++;
    return next;
  }
}

class RecordingShield implements ScreenShield {
  final List<bool> calls = [];
  @override
  Future<void> setProtected(bool protected) async => calls.add(protected);
}

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late File logFile;
  late ErrorLogger logger;
  late MemorySecureBackend backend;
  late SecureStore store;
  late DateTime now;
  late PinService pins;

  PinService newPinService() => PinService(
        store: SecureStore(backend),
        logger: logger,
        hasher: fastHasher(),
        clock: () => now,
      );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_pin_');
    logFile = File(p.join(tempDir.path, errorLogFileName));
    logger = ErrorLogger(() async => logFile);
    backend = MemorySecureBackend();
    store = SecureStore(backend);
    now = DateTime.utc(2026, 11, 24, 10);
    pins = newPinService();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> failTimes(int n, {String wrong = '000000'}) async {
    for (var i = 0; i < n; i++) {
      await pins.verify(wrong);
    }
  }

  group('PBKDF2 (RNF-15)', () {
    test('vectores conocidos de PBKDF2-HMAC-SHA256', () {
      String hex(Uint8List b) =>
          b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      final pass = Uint8List.fromList(utf8.encode('password'));
      final salt = Uint8List.fromList(utf8.encode('salt'));
      expect(hex(pbkdf2Sha256(pass, salt, 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(hex(pbkdf2Sha256(pass, salt, 2)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(hex(pbkdf2Sha256(pass, salt, 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('comparación en tiempo constante', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('la sal es aleatoria y del tamaño configurado', () {
      final hasher = PinHasher();
      final a = hasher.newSalt();
      expect(a, hasLength(AppConfig.pinSaltBytes));
      expect(hasher.newSalt(), isNot(equals(a)));
      expect(hasher.iterations, AppConfig.pinHashIterations);
    });

    test('el hasher por defecto calcula en otro isolate', () async {
      final hash = await PinHasher(iterations: 2).hash('123456', [1, 2, 3]);
      expect(hash, hasLength(32));
    });
  });

  group('HU-31 activar el PIN (RF-45)', () {
    test('CA-114: 6 dígitos iguales dos veces activan el PIN', () async {
      expect(await pins.isEnabled(), isFalse);
      expect((await pins.activate('482913', '482913')).isSuccess, isTrue);
      expect(await pins.isEnabled(), isTrue);
      expect(await pins.verify('482913'), isA<PinAccepted>());
    });

    test('CA-115: menos, más dígitos o letras se rechazan con el formato',
        () async {
      for (final bad in [
        '12345',
        '1234567',
        '12a456',
        '',
        ' 12345',
        '12345٦'
      ]) {
        final result = await pins.activate(bad, bad);
        expect(result.errorOrNull?.message, PinMessages.format, reason: bad);
      }
      expect(PinMessages.format, contains('6 números'));
      expect(await pins.isEnabled(), isFalse);
    });

    test('CA-116: si las capturas no coinciden no se activa', () async {
      final result = await pins.activate('111111', '111112');
      expect(result.errorOrNull?.message, PinMessages.mismatch);
      expect(await pins.isEnabled(), isFalse);
      expect(backend.values, isEmpty);
    });

    test('CA-117: si la escritura falla no queda un PIN a medias', () async {
      backend.failWrites = true;
      final result = await pins.activate('123456', '123456');
      expect(result.errorOrNull?.message, PinMessages.storageFailed);
      backend.failWrites = false;
      expect(await pins.isEnabled(), isFalse);
      expect(backend.values.containsKey(SecureStore.pinCredentialKey), isFalse);
    });

    test('CA-117: una credencial dañada cuenta como sin PIN', () async {
      backend.values[SecureStore.pinCredentialKey] = '{"alg":"pbkdf2-sha';
      expect(await pins.isEnabled(), isFalse);
      backend.values[SecureStore.pinCredentialKey] = '{"alg":"md5"}';
      expect(await pins.isEnabled(), isFalse);
    });

    test('CA-118 / RNF-15: el PIN no aparece en texto plano', () async {
      await pins.activate('482913', '482913');
      final dump = backend.values.values.join('|');
      expect(dump, isNot(contains('482913')));
      final credential =
          PinCredential.decode(backend.values[SecureStore.pinCredentialKey])!;
      expect(credential.salt, hasLength(AppConfig.pinSaltBytes));
      expect(credential.hash, hasLength(32));
      expect(credential.iterations, 1000);
    });

    test('CA-118: dos activaciones del mismo PIN usan sal distinta', () async {
      await pins.activate('482913', '482913');
      final first = backend.values[SecureStore.pinCredentialKey];
      await store.clearSecurity();
      await pins.activate('482913', '482913');
      expect(backend.values[SecureStore.pinCredentialKey], isNot(first));
    });

    test('con un PIN activo no se puede activar otro encima', () async {
      await pins.activate('111111', '111111');
      final result = await pins.activate('222222', '222222');
      expect(result.errorOrNull?.message, PinMessages.alreadyActive);
      expect(await pins.verify('111111'), isA<PinAccepted>());
    });
  });

  group('HU-34 límite de intentos (RF-48)', () {
    setUp(() => pins.activate('123456', '123456'));

    test('CA-128: el PIN correcto reinicia el contador', () async {
      await failTimes(3);
      expect(await store.readFailedAttempts(), 3);
      expect(await pins.verify('123456'), isA<PinAccepted>());
      expect(await store.readFailedAttempts(), 0);
      expect(await store.readLockoutUntil(), isNull);
    });

    test('CA-129: cada fallo informa los intentos restantes', () async {
      final remaining = <int>[];
      for (var i = 0; i < 4; i++) {
        final check = await pins.verify('000000');
        remaining.add((check as PinRejected).remainingAttempts);
      }
      expect(remaining, [4, 3, 2, 1]);
      expect(const PinRejected(3).message,
          'PIN incorrecto. Te quedan 3 intentos.');
      expect(
          const PinRejected(1).message, 'PIN incorrecto. Te queda 1 intento.');
    });

    test('CA-130: al quinto fallo se bloquea 30 segundos', () async {
      await failTimes(4);
      final fifth = await pins.verify('000000');
      expect(fifth, isA<PinLocked>());
      expect((fifth as PinLocked).remaining, AppConfig.pinLockout);
      expect(fifth.message, contains('30 segundos'));
      now = now.add(const Duration(seconds: 10));
      final during = await pins.verify('123456');
      expect(during, isA<PinLocked>());
      expect((during as PinLocked).remaining, const Duration(seconds: 20));
    });

    test('CA-131 / RNF-22: el bloqueo sigue tras cerrar y reabrir', () async {
      await failTimes(5);
      now = now.add(const Duration(seconds: 5));
      final reopened = newPinService();
      expect(await reopened.lockoutRemaining(), const Duration(seconds: 25));
      expect(await reopened.verify('123456'), isA<PinLocked>());
    });

    test('CA-131 / RNF-22: los fallos sin bloqueo también persisten', () async {
      await failTimes(3);
      final reopened = newPinService();
      final check = await reopened.verify('000000');
      expect((check as PinRejected).remainingAttempts, 1);
    });

    test('CA-132: al terminar el bloqueo hay 5 intentos nuevos', () async {
      await failTimes(5);
      now = now.add(AppConfig.pinLockout);
      expect(await pins.lockoutRemaining(), isNull);
      final check = await pins.verify('000000');
      expect((check as PinRejected).remainingAttempts, 4);
    });

    test('si el reloj se atrasa el bloqueo no pasa de 30 s', () async {
      await failTimes(5);
      now = now.subtract(const Duration(hours: 1));
      expect(await pins.lockoutRemaining(), AppConfig.pinLockout);
      now = now.add(AppConfig.pinLockout);
      expect(await pins.lockoutRemaining(), isNull);
    });

    test('un texto con otro formato no gasta intentos', () async {
      expect(await pins.verify('12'), isA<PinInvalidFormat>());
      expect(await store.readFailedAttempts(), 0);
    });

    test('sin PIN activo verify informa error', () async {
      await store.clearSecurity();
      final check = await pins.verify('123456');
      expect(check.message, PinMessages.notActive);
    });

    test('RNF-20: los fallos del almacén no registran el PIN', () async {
      backend.failWrites = true;
      final check = await pins.verify('654321');
      expect(check.message, PinMessages.storageFailed);
      final log = logFile.readAsStringSync();
      expect(log, contains('M-09'));
      expect(log, isNot(contains('654321')));
      expect(log, isNot(contains('123456')));
    });
  });

  group('HU-35 cambiar o desactivar (RF-49)', () {
    setUp(() => pins.activate('123456', '123456'));

    test('CA-133: con el PIN actual se cambia', () async {
      expect(
          (await pins.change('123456', '654321', '654321')).isSuccess, isTrue);
      expect(await pins.verify('654321'), isA<PinAccepted>());
      expect(await pins.verify('123456'), isA<PinRejected>());
    });

    test('CA-133: con el PIN actual se desactiva y se apaga la biometría',
        () async {
      await store.writeBiometricEnrollment('fingerprint');
      expect((await pins.disable('123456')).isSuccess, isTrue);
      expect(await pins.isEnabled(), isFalse);
      expect(await store.readBiometricEnrollment(), isNull);
    });

    test('CA-134: con un PIN actual incorrecto no se cambia ni se desactiva',
        () async {
      final change = await pins.change('000000', '654321', '654321');
      expect(change.errorOrNull?.message, PinMessages.wrong(4));
      final disable = await pins.disable('000000');
      expect(disable.errorOrNull?.message, PinMessages.wrong(3));
      expect(await pins.isEnabled(), isTrue);
      expect(await pins.verify('123456'), isA<PinAccepted>());
    });

    test('CA-135: si el nuevo no coincide sigue el anterior', () async {
      final result = await pins.change('123456', '654321', '654322');
      expect(result.errorOrNull?.message, PinMessages.mismatch);
      expect(await pins.verify('123456'), isA<PinAccepted>());
      expect(await pins.verify('654321'), isA<PinRejected>());
    });

    test('CA-135: un PIN nuevo con formato inválido no gasta intentos',
        () async {
      final result = await pins.change('000000', '12ab56', '12ab56');
      expect(result.errorOrNull?.message, PinMessages.format);
      expect(await store.readFailedAttempts(), 0);
    });

    test('CA-136: fallar el PIN actual 5 veces aplica el mismo bloqueo',
        () async {
      for (var i = 0; i < 4; i++) {
        await pins.disable('000000');
      }
      final fifth = await pins.change('000000', '654321', '654321');
      expect(
          fifth.errorOrNull?.message, PinMessages.locked(AppConfig.pinLockout));
      expect(await pins.lockoutRemaining(), AppConfig.pinLockout);
      final blocked = await pins.disable('123456');
      expect(blocked.isSuccess, isFalse);
      expect(await pins.isEnabled(), isTrue);
    });

    test('fallo del almacén al cambiar conserva el PIN', () async {
      final failing = PinService(
        store: SecureStore(_FailCredentialWrites(backend)),
        logger: logger,
        hasher: fastHasher(),
        clock: () => now,
      );
      final result = await failing.change('123456', '654321', '654321');
      expect(result.errorOrNull?.message, PinMessages.storageFailed);
      expect(await pins.verify('123456'), isA<PinAccepted>());
    });
  });

  group('HU-33 biometría (RF-47)', () {
    late FakeBiometrics device;
    late BiometricService biometrics;

    setUp(() {
      device = FakeBiometrics();
      biometrics = BiometricService(
        store: store,
        logger: logger,
        authenticator: device,
      );
    });

    test('CA-124: con huella registrada se activa y desbloquea', () async {
      expect((await biometrics.enable()).isSuccess, isTrue);
      expect(await biometrics.isEnabled(), isTrue);
      final unlock = await biometrics.unlock();
      expect(unlock.success, isTrue);
      expect(device.prompts, 2);
    });

    test('CA-124: si la confirmación inicial falla no se activa', () async {
      device.next = BiometricOutcome.failed;
      final result = await biometrics.enable();
      expect(result.errorOrNull?.message, BiometricMessages.failed);
      expect(await biometrics.isEnabled(), isFalse);
    });

    test('CA-125: si no reconoce, se pide el PIN', () async {
      await biometrics.enable();
      for (final outcome in [
        BiometricOutcome.failed,
        BiometricOutcome.lockedOut,
        BiometricOutcome.unavailable,
      ]) {
        device.next = outcome;
        final unlock = await biometrics.unlock();
        expect(unlock.success, isFalse);
        expect(unlock.message, BiometricMessages.failed);
      }
      device.next = BiometricOutcome.canceled;
      final canceled = await biometrics.unlock();
      expect(canceled.success, isFalse);
      expect(canceled.message, isNull);
    });

    test('CA-126: sin sensor o sin huellas la opción se explica', () async {
      device.available = BiometricAvailability.noHardware;
      expect(
          BiometricService.unavailableReason(await biometrics.availability()),
          BiometricMessages.noHardware);
      expect(
          BiometricService.unavailableReason(BiometricAvailability.notEnrolled),
          BiometricMessages.notEnrolled);
      expect(
          BiometricService.unavailableReason(BiometricAvailability.available),
          isNull);
      expect((await biometrics.enable()).isSuccess, isFalse);
      expect(device.prompts, 0);
    });

    test('CA-127: si cambian las huellas registradas se pide el PIN', () async {
      await biometrics.enable();
      device.enrolled = 'face,fingerprint';
      final unlock = await biometrics.unlock();
      expect(unlock.success, isFalse);
      expect(unlock.message, BiometricMessages.changed);
      expect(await biometrics.isEnabled(), isFalse);
      expect(device.prompts, 1);
    });

    test('CA-127: si se borraron todas las huellas se pide el PIN', () async {
      await biometrics.enable();
      device.available = BiometricAvailability.notEnrolled;
      expect((await biometrics.unlock()).message, BiometricMessages.changed);
    });

    test('sin biometría activada se usa el PIN sin preguntar', () async {
      final unlock = await biometrics.unlock();
      expect(unlock.success, isFalse);
      expect(device.prompts, 0);
    });

    test('desactivar y fallo de guardado', () async {
      await biometrics.enable();
      expect((await biometrics.disable()).isSuccess, isTrue);
      expect(await biometrics.isEnabled(), isFalse);
      backend.failWrites = true;
      final result = await biometrics.enable();
      expect(result.errorOrNull?.message, BiometricMessages.saveFailed);
    });
  });

  group('LockController (RF-46, RNF-19)', () {
    late RecordingShield shield;
    late LockController lock;
    late Database db;

    setUp(() async {
      shield = RecordingShield();
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
      lock = LockController(
        pin: pins,
        biometrics: BiometricService(
          store: store,
          logger: logger,
          authenticator: FakeBiometrics(),
        ),
        reset: ResetService(
          db: db,
          images: ImageStore(tempDir, freeSpace: (_) async => null),
          store: store,
          logger: logger,
        ),
        shield: shield,
        clock: () => now,
      );
    });

    tearDown(() async => db.close());

    test('sin PIN la app abre sin bloqueo ni protección', () async {
      await lock.init();
      expect(lock.ready, isTrue);
      expect(lock.locked, isFalse);
      expect(shield.calls.last, isFalse);
    });

    test('CA-119: con PIN activo la app abre bloqueada', () async {
      await pins.activate('123456', '123456');
      await lock.init();
      expect(lock.locked, isTrue);
      lock.unlock();
      expect(lock.locked, isFalse);
    });

    test('CA-121: más de 1 minuto en segundo plano vuelve a bloquear',
        () async {
      await pins.activate('123456', '123456');
      await lock.init();
      lock.unlock();
      lock.handleLifecycle(AppLifecycleState.inactive);
      lock.handleLifecycle(AppLifecycleState.hidden);
      lock.handleLifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 61));
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
    });

    test('CA-122 / AMB-07: 60 s o menos no pide el PIN', () async {
      await pins.activate('123456', '123456');
      await lock.init();
      lock.unlock();
      lock.handleLifecycle(AppLifecycleState.paused);
      now = now.add(AppConfig.backgroundLockAfter);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);
      // Solo "inactive" (una notificación encima) no cuenta como salir.
      lock.handleLifecycle(AppLifecycleState.inactive);
      now = now.add(const Duration(minutes: 5));
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);
    });

    test('CA-123 / RNF-19: con PIN se oculta el contenido al salir', () async {
      await pins.activate('123456', '123456');
      await lock.init();
      expect(shield.calls.last, isTrue);
      lock.handleLifecycle(AppLifecycleState.inactive);
      expect(lock.obscured, isTrue);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.obscured, isFalse);
      lock.handleLifecycle(AppLifecycleState.detached);
      expect(lock.obscured, isFalse);
    });

    test('sin PIN no se oculta ni se bloquea al volver', () async {
      await lock.init();
      lock.handleLifecycle(AppLifecycleState.paused);
      expect(lock.obscured, isFalse);
      now = now.add(const Duration(minutes: 5));
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);
    });

    test('refresh tras activar y desactivar desde Configuración', () async {
      await lock.init();
      await pins.activate('123456', '123456');
      await lock.refresh();
      expect(lock.pinEnabled, isTrue);
      expect(lock.locked, isFalse);
      expect(shield.calls.last, isTrue);
      await pins.disable('123456');
      await lock.refresh();
      expect(lock.pinEnabled, isFalse);
      expect(shield.calls.last, isFalse);
    });

    test('CA-140: restablecer desbloquea y cambia la generación', () async {
      await pins.activate('123456', '123456');
      await lock.init();
      final generation = lock.generation;
      expect((await lock.resetApp()).isSuccess, isTrue);
      expect(lock.locked, isFalse);
      expect(lock.pinEnabled, isFalse);
      expect(lock.generation, generation + 1);
      expect(shield.calls.last, isFalse);
    });

    test('si el restablecimiento falla sigue bloqueada', () async {
      await pins.activate('123456', '123456');
      await lock.init();
      backend.failWrites = true;
      final result = await lock.resetApp();
      expect(result.errorOrNull?.message, ResetMessages.failed);
      expect(lock.locked, isTrue);
    });
  });

  group('HU-36 restablecer la app (RF-50)', () {
    late Database db;
    late ImageStore images;
    late ResetService reset;
    late SettingsRepository settings;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
      images = ImageStore(tempDir, freeSpace: (_) async => null);
      settings = SettingsRepository(db);
      reset = ResetService(
        db: db,
        images: images,
        store: store,
        logger: logger,
      );
      await _seedData(db, images, settings);
      await pins.activate('123456', '123456');
      await store.writeBiometricEnrollment('fingerprint');
    });

    tearDown(() async {
      if (db.isOpen) await db.close();
    });

    Future<void> expectEmpty() async {
      for (final table in userDataTables) {
        expect(await db.query(table), isEmpty, reason: table);
      }
      expect(await db.query('categoria'), hasLength(8));
      expect(_files(images.receiptsDir), isEmpty);
      expect(_files(images.tempDir), isEmpty);
      expect(backend.values, isEmpty);
      expect(await settings.getSetting('aviso_privacidad_aceptado'), isNull);
    }

    test('CA-137: borra base, recibos y almacén seguro', () async {
      expect((await reset.resetAll()).isSuccess, isTrue);
      await expectEmpty();
      expect(
          File(p.join(images.receiptsDir.path, noMediaFileName)).existsSync(),
          isTrue);
    });

    test('CA-137: tras restablecer, los ids empiezan de nuevo', () async {
      await reset.resetAll();
      final id = await db.insert('movimiento', _movement());
      expect(id, 1);
    });

    test('CA-139: si se cerró antes de la bandera, conserva todo', () async {
      expect(await reset.completePendingReset(), isFalse);
      expect(await db.query('movimiento'), hasLength(1));
      expect(_files(images.receiptsDir), hasLength(1));
      expect(await pins.isEnabled(), isTrue);
    });

    test('CA-139: si se cerró a mitad, al reabrir termina el borrado',
        () async {
      // Simula el cierre justo después de escribir la bandera.
      await store.writeResetPending(true);
      expect(await db.query('movimiento'), hasLength(1));
      expect(await reset.completePendingReset(), isTrue);
      await expectEmpty();
    });

    test('CA-139: el borrado de la base es una sola transacción', () async {
      await db.execute('''
CREATE TRIGGER no_borrar_ajuste BEFORE DELETE ON ajuste
BEGIN SELECT RAISE(ABORT, 'falla simulada'); END''');
      final result = await reset.resetAll();
      expect(result.isSuccess, isFalse);
      expect(await db.query('movimiento'), hasLength(1));
      expect(await db.query('recibo'), hasLength(1));
      expect(await store.readResetPending(), isTrue);
      await db.execute('DROP TRIGGER no_borrar_ajuste');
      expect(await reset.completePendingReset(), isTrue);
      await expectEmpty();
    });

    test('CA-140: el aviso de privacidad vuelve a estar sin aceptar', () async {
      expect(await settings.getSetting('aviso_privacidad_aceptado'), 'true');
      await reset.resetAll();
      expect(await settings.getSetting('aviso_privacidad_aceptado'), isNull);
    });
  });

  group('SecureStore', () {
    test('valores ausentes o dañados', () async {
      expect(await store.readFailedAttempts(), 0);
      expect(await store.readLockoutUntil(), isNull);
      backend.values[SecureStore.failedAttemptsKey] = 'x';
      expect(await store.readFailedAttempts(), 0);
      expect(PinCredential.decode(null), isNull);
    });

    test('lockout_until se guarda en UTC', () async {
      await store.writeLockoutUntil(DateTime.utc(2026, 1, 1));
      expect(await store.readLockoutUntil(), DateTime.utc(2026, 1, 1));
    });
  });
}

class _FailCredentialWrites implements SecureBackend {
  _FailCredentialWrites(this._inner);
  final SecureBackend _inner;

  @override
  Future<String?> read(String key) => _inner.read(key);

  @override
  Future<void> write(String key, String value) {
    if (key == SecureStore.pinCredentialKey) {
      throw StateError('escritura simulada fallida');
    }
    return _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

Map<String, Object?> _movement() => {
      'tipo': 'egreso',
      'monto_centavos': 12550,
      'fecha': '2026-11-20',
      'categoria_id': 1,
      'descripcion': 'Super',
      'creado_en': '2026-11-20T10:00:00',
      'actualizado_en': '2026-11-20T10:00:00',
    };

Future<void> _seedData(
  Database db,
  ImageStore images,
  SettingsRepository settings,
) async {
  final id = await db.insert('movimiento', _movement());
  final temp = await images.writeTemp(Uint8List.fromList([1, 2, 3]));
  final saved = await images.promote(temp);
  await images.writeTemp(Uint8List.fromList([4, 5, 6]));
  await db.insert('recibo', {
    'movimiento_id': id,
    'ruta_archivo': images.relativePathOf(saved),
    'tamano_bytes': 3,
    'capturado_en': '2026-11-20T10:00:00',
  });
  await settings.setSetting('aviso_privacidad_aceptado', 'true');
  await settings.setSetting('aviso_privacidad_version', '2');
}

List<File> _files(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => p.basename(f.path) != noMediaFileName)
    .toList();
