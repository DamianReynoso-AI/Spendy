// Incremento 6 · Funcionamiento sin conexión (RF-52, CA-144).
//
// Sustituto automatizado de la prueba E2E en modo avión: (1) en lib/ solo
// el adaptador de OCR en la nube usa red, y (2) con toda conexión de red
// bloqueada se registra, lista, filtra y resume con SQLite real; el OCR
// falla con "sin conexión" y la app sigue funcionando.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/ocr/cloud_ocr_adapter.dart';
import 'package:spendy/modules/ocr/ocr_service.dart';
import 'package:spendy/modules/search/movement_filter.dart';
import 'package:spendy/modules/summary/summary_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Toda conexión saliente falla como en modo avión.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    return super.createHttpClient(context)
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Future.error(const SocketException('Network is unreachable'));
  }
}

void main() {
  sqfliteFfiInit();

  test('RF-52: en lib/ solo el adaptador de OCR usa red', () {
    final pattern = RegExp(r'HttpClient|Socket|package:http/|WebSocket');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => pattern.hasMatch(f.readAsStringSync()))
        .map((f) => p.relative(f.path))
        .toList();
    expect(
        offenders, [p.join('lib', 'modules', 'ocr', 'cloud_ocr_adapter.dart')]);
  });

  test('CA-144: sin red se registra, filtra y resume; el OCR avisa', () async {
    final network = _NoNetwork();
    await HttpOverrides.runWithHttpOverrides(() async {
      final dir = Directory.systemTemp.createTempSync('spendy_offline_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(dir.path, databaseFileName),
      );
      addTearDown(db.close);
      final logger =
          ErrorLogger(() async => File(p.join(dir.path, errorLogFileName)));
      final repo = MovementRepository(db);
      final service = MovementService(
        repository: repo,
        catalog: CategoryCatalog(CategoryRepository(db), logger),
        logger: logger,
      );
      final now = DateTime.now();
      final saved = await service.save(MovementDraft(
        type: MovementType.egreso,
        amountText: '120.50',
        date: now,
        categoryId: 1,
        paymentMethod: PaymentMethod.efectivo,
        description: 'Tacos sin señal',
      ));
      expect(saved.isSuccess, isTrue);
      expect((await service.list()).valueOrNull, hasLength(1));

      final filter = MovementFilter(repository: repo, logger: logger);
      final found = await filter.apply(const MovementCriteria(text: 'senal'));
      expect(found.valueOrNull!.sumLabel, r'Suma: $120.50');

      final summary = SummaryService(repository: repo, logger: logger);
      final annual = await summary.summaryFor(now.year);
      expect(annual.isSuccess, isTrue);

      final ocr = OcrService(
        adapter: CloudOcrAdapter(CloudOcrConfig(
          endpoint: Uri.parse('https://ocr.example.invalid/v1'),
          apiKey: 'clave-de-prueba',
        )),
        logger: logger,
      );
      final outcome = await ocr.start(Uint8List.fromList([1, 2, 3])).result;
      expect(outcome, isA<OcrFailed>());
      expect((outcome as OcrFailed).kind, OcrFailureKind.noConnection);
    }, network);
    expect(network.attempts, 1, reason: 'solo el OCR intentó usar la red');
  });
}
