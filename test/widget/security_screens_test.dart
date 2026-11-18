// Pruebas de pantallas del incremento 7: bloqueo con PIN, Configuración,
// biometría y restablecimiento (M-01 con M-09).
// CA-114, CA-116, CA-119, CA-120, CA-123 a CA-126, CA-129, CA-130,
// CA-133 a CA-135, CA-137, CA-138, CA-140.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/privacy/onboarding_service.dart';
import 'package:spendy/modules/security/biometric_service.dart';
import 'package:spendy/modules/security/lock_controller.dart';
import 'package:spendy/modules/security/pin_service.dart';
import 'package:spendy/modules/security/reset_service.dart';
import 'package:spendy/ui/screens/pin_screen.dart';
import 'package:spendy/ui/screens/settings_screen.dart';

import '../unit/pin_service_test.dart' show FakeBiometrics, fastHasher;
import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import 'summary_screens_test.dart' show MemorySettings;

/// Restablecimiento en memoria: borra el almacén seguro y los ajustes.
class FakeReset implements ResetService {
  FakeReset(this.backend, this.settings);
  final MemorySecureBackend backend;
  final MemorySettings settings;
  int calls = 0;

  @override
  Future<Result<void>> resetAll() async {
    calls++;
    backend.values.clear();
    settings.values.clear();
    return const Success(null);
  }

  @override
  Future<bool> completePendingReset() async => false;
}

void main() {
  late ErrorLogger logger;
  late MovementService service;
  late CategoryCatalog catalog;
  late MemorySettings settings;
  late MemorySecureBackend backend;
  late PinService pins;
  late FakeBiometrics device;
  late FakeReset reset;
  late LockController lock;

  setUp(() {
    logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    service = MovementService(
      repository: MemoryMovementRepository(),
      catalog: catalog,
      logger: logger,
    );
    settings = MemorySettings()
      ..values['aviso_privacidad_aceptado'] = 'true'
      ..values['aviso_privacidad_version'] = PrivacyTexts.version;
    backend = MemorySecureBackend();
    final store = SecureStore(backend);
    pins = PinService(store: store, logger: logger, hasher: fastHasher());
    device = FakeBiometrics();
    reset = FakeReset(backend, settings);
    lock = LockController(
      pin: pins,
      biometrics: BiometricService(
        store: store,
        logger: logger,
        authenticator: device,
      ),
      reset: reset,
      shield: const NoScreenShield(),
    );
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await lock.init();
    await tester.pumpWidget(
      SpendyApp(
        service: service,
        catalog: catalog,
        onboarding: OnboardingService(settings, logger),
        lock: lock,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typePin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byKey(const Key('pin_field')), pin);
    await tester.pump();
    await tester.pump();
  }

  final data = find.textContaining('Balance de');

  group('desbloqueo (RF-46, RF-48)', () {
    testWidgets('sin PIN la app abre directo', (tester) async {
      await pumpApp(tester);
      expect(data, findsOneWidget);
      expect(find.byType(PinUnlockScreen), findsNothing);
      expect(find.byTooltip('Configuración'), findsOneWidget);
    });

    testWidgets('CA-119 / CA-120: sin el PIN correcto no se ve ningún dato',
        (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      expect(find.text(PinTexts.unlockTitle), findsOneWidget);
      expect(data, findsNothing);

      await typePin(tester, '000000');
      expect(find.text(PinMessages.wrong(4)), findsOneWidget);
      expect(data, findsNothing);

      // "Atrás" no cierra pantallas ocultas debajo.
      expect(await tester.binding.handlePopRoute(), isTrue);

      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      expect(find.byType(PinUnlockScreen), findsNothing);
      expect(data, findsOneWidget);
    });

    testWidgets('CA-129 / CA-130: intentos restantes y bloqueo con tiempo',
        (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      for (var i = 0; i < 5; i++) {
        await typePin(tester, '000000');
      }
      expect(find.textContaining('Espera 30 segundos'), findsOneWidget);
      final field =
          tester.widget<TextField>(find.byKey(const Key('pin_field')));
      expect(field.enabled, isFalse);
      expect(data, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('CA-121: al volver tras más de 1 minuto se pide el PIN',
        (tester) async {
      var now = DateTime(2026, 11, 24, 10);
      lock = LockController(
        pin: pins,
        biometrics: lock.biometrics,
        reset: reset,
        shield: const NoScreenShield(),
        clock: () => now,
      );
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      expect(data, findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // CA-123: mientras no está en primer plano, el contenido se cubre.
      expect(find.byKey(const Key('privacy_cover')), findsOneWidget);

      now = now.add(const Duration(seconds: 61));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy_cover')), findsNothing);
      expect(find.text(PinTexts.unlockTitle), findsOneWidget);
      expect(data, findsNothing);
    });
  });

  group('biometría (RF-47)', () {
    testWidgets('CA-124: con biometría activa se desbloquea sola',
        (tester) async {
      await pins.activate('123456', '123456');
      await lock.biometrics.enable();
      await pumpApp(tester);
      expect(data, findsOneWidget);
    });

    testWidgets('CA-125: si falla se queda en el PIN con aviso',
        (tester) async {
      await pins.activate('123456', '123456');
      await lock.biometrics.enable();
      device.next = BiometricOutcome.failed;
      await pumpApp(tester);
      expect(find.text(BiometricMessages.failed), findsOneWidget);
      expect(find.text(PinTexts.useBiometrics), findsOneWidget);
      expect(data, findsNothing);
      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      expect(data, findsOneWidget);
    });
  });

  group('restablecer (RF-50)', () {
    Future<void> openReset(WidgetTester tester) async {
      await tester.tap(find.text(PinTexts.forgot));
      await tester.pumpAndSettle();
    }

    testWidgets('CA-138: cancelar en cualquiera de las dos no borra nada',
        (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);

      await openReset(tester);
      expect(find.text(PinTexts.reset1Body), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      await openReset(tester);
      await tester.tap(find.text(PinTexts.reset1Confirm).last);
      await tester.pumpAndSettle();
      expect(find.text(PinTexts.reset2Body), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(reset.calls, 0);
      expect(await pins.isEnabled(), isTrue);
      expect(find.text(PinTexts.unlockTitle), findsOneWidget);
    });

    testWidgets(
        'CA-137 / CA-140: dos confirmaciones borran y muestran '
        'el aviso', (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      await openReset(tester);
      await tester.tap(find.text(PinTexts.reset1Confirm).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(PinTexts.reset2Confirm));
      await tester.pumpAndSettle();

      expect(reset.calls, 1);
      expect(find.byType(PinUnlockScreen), findsNothing);
      expect(find.text(PrivacyTexts.title), findsOneWidget);
      expect(data, findsNothing);
    });
  });

  group('Configuración (RF-45, RF-47, RF-49)', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Configuración'));
      await tester.pumpAndSettle();
    }

    testWidgets('CA-126: sin sensor la biometría aparece deshabilitada',
        (tester) async {
      device.available = BiometricAvailability.noHardware;
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text(BiometricMessages.noHardware), findsOneWidget);
      final tile = tester
          .widget<SwitchListTile>(find.byKey(const Key('biometrics_switch')));
      expect(tile.onChanged, isNull);
    });

    testWidgets('CA-116 y CA-114: activar con error y luego bien',
        (tester) async {
      await pumpApp(tester);
      await openSettings(tester);
      expect(find.text(SettingsTexts.biometricsNeedsPin), findsOneWidget);
      await tester.tap(find.byKey(const Key('pin_switch')));
      await tester.pumpAndSettle();

      await typePin(tester, '12');
      await tester.tap(find.text(PinTexts.continueLabel));
      await tester.pump();
      expect(find.text(PinMessages.format), findsOneWidget);

      await typePin(tester, '111111');
      expect(find.text(PinTexts.confirmPin), findsOneWidget);
      await typePin(tester, '222222');
      await tester.pumpAndSettle();
      expect(find.text(PinMessages.mismatch), findsOneWidget);
      expect(await pins.isEnabled(), isFalse);

      await typePin(tester, '111111');
      await typePin(tester, '111111');
      await tester.pumpAndSettle();
      expect(find.text(SettingsTexts.activated), findsOneWidget);
      expect(await pins.isEnabled(), isTrue);
      expect(lock.pinEnabled, isTrue);
      expect(lock.locked, isFalse);
    });

    testWidgets('CA-134, CA-135 y CA-133: cambiar el PIN', (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tester.tap(find.byKey(const Key('change_pin')));
      await tester.pumpAndSettle();

      await typePin(tester, '000000');
      expect(find.text(PinMessages.wrong(4)), findsOneWidget);
      expect(find.text(PinTexts.currentPin), findsOneWidget);

      await typePin(tester, '123456');
      await typePin(tester, '654321');
      await typePin(tester, '654320');
      await tester.pumpAndSettle();
      expect(find.text(PinMessages.mismatch), findsOneWidget);
      expect(await pins.verify('123456'), isA<PinAccepted>());

      await typePin(tester, '654321');
      await typePin(tester, '654321');
      await tester.pumpAndSettle();
      expect(find.text(SettingsTexts.changed), findsOneWidget);
      expect(await pins.verify('654321'), isA<PinAccepted>());
    });

    testWidgets('CA-133 y CA-124: biometría y desactivar el PIN',
        (tester) async {
      await pins.activate('123456', '123456');
      await pumpApp(tester);
      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      await openSettings(tester);

      await tester.tap(find.byKey(const Key('biometrics_switch')));
      await tester.pumpAndSettle();
      expect(await lock.biometrics.isEnabled(), isTrue);

      await tester.tap(find.byKey(const Key('pin_switch')));
      await tester.pumpAndSettle();
      expect(find.text(PinSetupMode.disable.title), findsOneWidget);
      await typePin(tester, '123456');
      await tester.pumpAndSettle();
      expect(find.text(SettingsTexts.deactivated), findsOneWidget);
      expect(await pins.isEnabled(), isFalse);
      expect(await lock.biometrics.isEnabled(), isFalse);
      expect(lock.pinEnabled, isFalse);
    });
  });
}
