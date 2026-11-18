/// Punto de entrada: abre la base, arma los servicios y muestra la app.
/// Es el único lugar fuera de M-11 que conoce `lib/data/` (RNF-30).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'core/error_logger.dart';
import 'data/database.dart';
import 'data/image_store.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/movement_repository.dart';
import 'data/repositories/receipt_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/secure_store.dart';
import 'modules/backup/backup_service.dart';
import 'modules/budgets/budget_service.dart';
import 'modules/categories/category_catalog.dart';
import 'modules/export/export_service.dart';
import 'modules/insights/insights_service.dart';
import 'modules/movements/movement_service.dart';
import 'modules/ocr/cloud_ocr_adapter.dart';
import 'modules/ocr/gemini_ocr_adapter.dart';
import 'modules/ocr/mlkit_ocr_adapter.dart';
import 'modules/ocr/ocr_adapter.dart';
import 'modules/ocr/ocr_key_service.dart';
import 'modules/ocr/ocr_service.dart';
import 'modules/privacy/onboarding_service.dart';
import 'modules/receipts/camera_service.dart';
import 'modules/receipts/receipt_service.dart';
import 'modules/search/movement_filter.dart';
import 'modules/security/biometric_service.dart';
import 'modules/security/lock_controller.dart';
import 'modules/security/pin_service.dart';
import 'modules/security/reset_service.dart';
import 'modules/security/uptime_clock.dart';
import 'modules/summary/summary_service.dart';

/// `errores.log` en el almacenamiento privado de la app (RNF-20).
Future<File> _logFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, errorLogFileName));
}

/// Protección de acceso (M-09). Antes de todo termina un restablecimiento
/// que se haya interrumpido (CA-139) y lee si hay PIN para iniciar
/// bloqueada (CA-119).
Future<LockController> _lockController(
  Database db,
  ImageStore store,
  ErrorLogger logger,
) async {
  final secure = SecureStore();
  final reset = ResetService(
    db: db,
    images: store,
    store: secure,
    logger: logger,
  );
  await reset.completePendingReset();
  final lock = LockController(
    pin: PinService(store: secure, logger: logger, uptime: platformUptime),
    biometrics: BiometricService(
      store: secure,
      logger: logger,
      keyGuard: const PlatformBiometricKeyGuard(),
    ),
    reset: reset,
  );
  await lock.init();
  return lock;
}

/// Proveedor de OCR (RNF-32), en este orden:
/// 1. Gemini con la clave que la persona guardó en Ajustes (se revisa en
///    cada lectura, así que aplica sin reiniciar).
/// 2. Gemini con `SPENDY_GEMINI_API_KEY` del entorno (solo desarrollo en
///    escritorio; la clave nunca se compila dentro del APK, TEC-01).
/// 3. El servicio HTTPS genérico si hay endpoint (RNF-18).
/// 4. ML Kit en el teléfono (sección 5.2 de docs/arquitectura.md).
OcrAdapter _ocrAdapter(ImageStore store, OcrKeyService keys) =>
    KeyedGeminiOcrAdapter(
      readKey: keys.read,
      fallback: _fallbackOcrAdapter(store),
      model: GeminiEnvironment.compiledModel,
    );

OcrAdapter _fallbackOcrAdapter(ImageStore store) {
  final gemini = GeminiOcrConfig.fromEnvironment();
  if (gemini != null) return GeminiOcrAdapter(gemini);
  try {
    final config = CloudOcrConfig.fromEnvironment();
    if (config != null) return CloudOcrAdapter(config);
  } on ArgumentError {
    return const UnconfiguredOcrAdapter();
  }
  return Platform.isAndroid || Platform.isIOS
      ? MlKitOcrAdapter(workDir: store.tempDir)
      : const UnconfiguredOcrAdapter();
}

BudgetService _budgetService(
  Database db,
  MovementRepository movements,
  CategoryCatalog catalog,
  ErrorLogger logger,
) =>
    BudgetService(
      budgets: BudgetRepository(db),
      movements: movements,
      catalog: catalog,
      logger: logger,
    );

BackupService _backupService(
        Database db, ImageStore store, ErrorLogger logger) =>
    BackupService(
      db: db,
      images: store,
      directory: getTemporaryDirectory,
      logger: logger,
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = ErrorLogger(_logFile);
  try {
    final db = await openSpendyDatabase();
    final store = ImageStore(await getApplicationSupportDirectory());
    await store.init();
    final lock = await _lockController(db, store, logger);
    final ocrKey = OcrKeyService(SecureStore(), logger);
    final receipts = ReceiptService(
      store: store,
      repository: ReceiptRepository(db, store),
      logger: logger,
      ocr: OcrService(adapter: _ocrAdapter(store, ocrKey), logger: logger),
    );
    // Limpia capturas temporales y recibos sin registro (TEC-06, RNF-21).
    await receipts.cleanOrphans();
    await cleanSharedCopies(await getTemporaryDirectory());
    final catalog = CategoryCatalog(CategoryRepository(db), logger);
    final movements = MovementRepository(db, imageStore: store);
    runApp(
      SpendyApp(
        service: MovementService(
            repository: movements, catalog: catalog, logger: logger),
        catalog: catalog,
        receipts: receipts,
        camera: CameraService(const PluginCameraDevice(), logger),
        onboarding: OnboardingService(SettingsRepository(db), logger),
        summary: SummaryService(repository: movements, logger: logger),
        filter: MovementFilter(repository: movements, logger: logger),
        exports:
            ExportService(directory: getTemporaryDirectory, logger: logger),
        lock: lock,
        ocrKey: ocrKey,
        budgets: _budgetService(db, movements, catalog, logger),
        insights: InsightsService(repository: movements, logger: logger),
        backup: _backupService(db, store, logger),
      ),
    );
  } on Object catch (e) {
    final error = translateStorageError(e, writing: false);
    await logger.log(type: error.type, module: 'M-11', cause: e);
    runApp(StartupErrorApp(message: error.message));
  }
}
