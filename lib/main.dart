/// Punto de entrada: abre la base, arma los servicios y muestra la app.
/// Es el único lugar fuera de M-11 que conoce `lib/data/` (RNF-30).
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/error_logger.dart';
import 'data/database.dart';
import 'data/image_store.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/movement_repository.dart';
import 'data/repositories/receipt_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'modules/categories/category_catalog.dart';
import 'modules/export/export_service.dart';
import 'modules/movements/movement_service.dart';
import 'modules/ocr/cloud_ocr_adapter.dart';
import 'modules/ocr/ocr_adapter.dart';
import 'modules/ocr/ocr_service.dart';
import 'modules/privacy/onboarding_service.dart';
import 'modules/receipts/camera_service.dart';
import 'modules/receipts/receipt_service.dart';
import 'modules/summary/summary_service.dart';

/// `errores.log` en el almacenamiento privado de la app (RNF-20).
Future<File> _logFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, errorLogFileName));
}

/// Proveedor de OCR leído de la configuración externa (RNF-18). Sin
/// configuración, o con un endpoint que no es HTTPS (RNF-16), la lectura
/// no está disponible y la persona registra a mano con la foto.
OcrAdapter _ocrAdapter() {
  try {
    final config = CloudOcrConfig.fromEnvironment();
    return config == null
        ? const UnconfiguredOcrAdapter()
        : CloudOcrAdapter(config);
  } on ArgumentError {
    return const UnconfiguredOcrAdapter();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = ErrorLogger(_logFile);
  try {
    final db = await openSpendyDatabase();
    final store = ImageStore(await getApplicationSupportDirectory());
    await store.init();
    final receipts = ReceiptService(
      store: store,
      repository: ReceiptRepository(db, store),
      logger: logger,
      ocr: OcrService(adapter: _ocrAdapter(), logger: logger),
    );
    // Limpia capturas temporales y recibos sin registro (TEC-06, RNF-21).
    await receipts.cleanOrphans();
    final catalog = CategoryCatalog(CategoryRepository(db), logger);
    final movements = MovementRepository(db, imageStore: store);
    final service = MovementService(
      repository: movements,
      catalog: catalog,
      logger: logger,
    );
    runApp(
      SpendyApp(
        service: service,
        catalog: catalog,
        receipts: receipts,
        camera: CameraService(const PluginCameraDevice(), logger),
        onboarding: OnboardingService(SettingsRepository(db), logger),
        summary: SummaryService(repository: movements, logger: logger),
        exports: ExportService(
          directory: getTemporaryDirectory,
          logger: logger,
        ),
      ),
    );
  } on Object catch (e) {
    final error = translateStorageError(e, writing: false);
    await logger.log(type: error.type, module: 'M-11', cause: e);
    runApp(StartupErrorApp(message: error.message));
  }
}
