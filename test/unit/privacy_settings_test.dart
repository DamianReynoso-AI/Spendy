// Pruebas del incremento 5 para M-10 y M-11: SettingsRepository y
// OnboardingService con SQLite real, y el texto del aviso.
// RF-51; RNF-17, RNF-51; CA-141 a CA-143.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/repositories/settings_repository.dart';
import 'package:spendy/modules/privacy/onboarding_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late Database db;
  late SettingsRepository settings;
  late OnboardingService onboarding;
  late File logFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('spendy_settings_');
    logFile = File(p.join(tempDir.path, errorLogFileName));
    db = await openSpendyDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(tempDir.path, databaseFileName),
    );
    settings = SettingsRepository(db, clock: () => DateTime(2026, 11, 12, 9));
    onboarding = OnboardingService(settings, ErrorLogger(() async => logFile));
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    tempDir.deleteSync(recursive: true);
  });

  test('getSetting / setSetting crean y reemplazan con fecha ISO 8601',
      () async {
    expect(await settings.getSetting('tema'), isNull);
    await settings.setSetting('tema', 'claro');
    await settings.setSetting('tema', 'oscuro');
    expect(await settings.getSetting('tema'), 'oscuro');
    final rows = await db.query('ajuste');
    expect(rows.single['actualizado_en'], '2026-11-12T09:00:00.000');
  });

  test('CA-141: en el primer inicio el aviso no está aceptado', () async {
    expect(await onboarding.isAccepted(), isFalse);
  });

  test('CA-143: al aceptar se guarda la clave exacta y ya no se pide',
      () async {
    expect((await onboarding.accept()).isSuccess, isTrue);
    expect(await settings.getSetting('aviso_privacidad_aceptado'), 'true');
    final reopened = OnboardingService(
      SettingsRepository(db),
      ErrorLogger(() async => logFile),
    );
    expect(await reopened.isAccepted(), isTrue);
  });

  test('CA-142: si no se puede leer, se vuelve a mostrar el aviso', () async {
    await db.close();
    expect(await onboarding.isAccepted(), isFalse);
    final result = await onboarding.accept();
    expect(result.errorOrNull!.message, OnboardingMessages.saveFailed);
    expect(logFile.readAsStringSync(), contains('M-10'));
  });

  test(
      'DUP-04 / RNF-17: el aviso dice que todo es local y que solo la '
      'imagen va al OCR', () {
    final text = PrivacyTexts.paragraphs.join(' ');
    expect(text, contains('únicamente en el almacenamiento privado'));
    expect(text, contains('solo la imagen de ese recibo se envía'));
    expect(text, contains(PrivacyTexts.ocrProviderName));
    expect(text, contains('Nunca se envían tus montos, notas'));
  });
}
