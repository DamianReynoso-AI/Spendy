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
import 'data/repositories/category_repository.dart';
import 'data/repositories/movement_repository.dart';
import 'modules/categories/category_catalog.dart';
import 'modules/movements/movement_service.dart';

/// `errores.log` en el almacenamiento privado de la app (RNF-20).
Future<File> _logFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, errorLogFileName));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = ErrorLogger(_logFile);
  try {
    final db = await openSpendyDatabase();
    final catalog = CategoryCatalog(CategoryRepository(db), logger);
    final service = MovementService(
      repository: MovementRepository(db),
      catalog: catalog,
      logger: logger,
    );
    runApp(SpendyApp(service: service, catalog: catalog));
  } on Object catch (e) {
    final error = translateStorageError(e, writing: false);
    await logger.log(type: error.type, module: 'M-11', cause: e);
    runApp(StartupErrorApp(message: error.message));
  }
}
