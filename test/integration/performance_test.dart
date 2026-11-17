// Cierre v1.0.0 · Rendimiento con 2,000 movimientos (RNF-09 a RNF-11) y
// revisión de la bitácora (RNF-20), con SQLite real en un archivo.
//
// Mide en el equipo donde corre la prueba (no en el teléfono): lista,
// filtros, resumen anual y exportación CSV y PDF. Imprime cada tiempo con
// el prefijo "TIEMPO" para copiarlo a docs/plan_pruebas.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/export/csv_exporter.dart';
import 'package:spendy/modules/export/exporter.dart';
import 'package:spendy/modules/export/pdf_exporter.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/search/movement_filter.dart';
import 'package:spendy/modules/summary/summary_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int year = 2026;

Future<Duration> timed(String label, Future<void> Function() action) async {
  final watch = Stopwatch()..start();
  await action();
  watch.stop();
  // ignore: avoid_print
  print('TIEMPO $label: ${watch.elapsedMilliseconds} ms');
  return watch.elapsed;
}

Future<void> seed(Database db) async {
  final batch = db.batch();
  for (var i = 0; i < 2000; i++) {
    final created = DateTime(year, 1, 1).add(Duration(minutes: i));
    final expense = i % 3 != 0;
    batch.insert(
      'movimiento',
      Movement(
        type: expense ? MovementType.egreso : MovementType.ingreso,
        amountCents: 1000 + i * 37,
        date: DateTime(year, 1, 1).add(Duration(days: i % 320)),
        categoryId: expense ? 1 + i % 6 : 7 + i % 2,
        paymentMethod: expense ? 'efectivo' : null,
        description: expense ? 'Comercio número $i' : null,
        note: i % 5 == 0 ? 'Nota de prueba $i' : null,
        createdAt: created,
        updatedAt: created,
      ).toRow(),
    );
  }
  await batch.commit(noResult: true);
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late MovementRepository repo;
  late ErrorLogger logger;
  late File logFile;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('spendy_perf_');
    db = await openSpendyDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(dir.path, databaseFileName),
    );
    logFile = File(p.join(dir.path, errorLogFileName));
    logger = ErrorLogger(() async => logFile);
    repo = MovementRepository(db);
    await seed(db);
  });

  tearDownAll(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('RNF-09: la lista de 2,000 movimientos carga en 2 s o menos', () async {
    final service = MovementService(
      repository: repo,
      catalog: CategoryCatalog(CategoryRepository(db), logger),
      logger: logger,
    );
    final elapsed = await timed('lista 2,000', () async {
      expect((await service.list()).valueOrNull, hasLength(2000));
    });
    expect(elapsed, lessThanOrEqualTo(const Duration(seconds: 2)));
  });

  test('RNF-09: cada filtro y la búsqueda responden en 1 s o menos', () async {
    final filter = MovementFilter(repository: repo, logger: logger);
    final cases = {
      'filtro fechas': MovementCriteria(
        startDate: DateTime(year, 3, 1),
        endDate: DateTime(year, 6, 30),
      ),
      'filtro categoría': const MovementCriteria(categoryId: 2),
      'filtro tipo': const MovementCriteria(type: MovementType.ingreso),
      'búsqueda texto': const MovementCriteria(text: 'numero 1'),
    };
    for (final MapEntry(key: label, value: criteria) in cases.entries) {
      final elapsed = await timed(label, () async {
        expect((await filter.apply(criteria)).isSuccess, isTrue);
      });
      expect(elapsed, lessThanOrEqualTo(const Duration(seconds: 1)));
    }
  });

  test('RNF-10 / RNF-11: resumen en 3 s y exportación en 10 s o menos',
      () async {
    final summaries = SummaryService(repository: repo, logger: logger);
    late AnnualSummary summary;
    final summaryTime = await timed('resumen anual', () async {
      summary = (await summaries.summaryFor(year)).valueOrNull!;
    });
    expect(summaryTime, lessThanOrEqualTo(const Duration(seconds: 3)));

    final now = DateTime(year, 11, 17);
    final exporters = <(String, SummaryExporter)>[
      ('exportar CSV', const CsvExporter()),
      ('exportar PDF', const PdfExporter()),
    ];
    for (final (label, exporter) in exporters) {
      final elapsed = await timed(label, () async {
        expect(await exporter.render(summary, now), isNotEmpty);
      });
      expect(elapsed, lessThanOrEqualTo(const Duration(seconds: 10)));
    }
  });

  test('RNF-20: errores.log no guarda montos, comercios ni notas', () async {
    await db.close();
    final closed = MovementService(
      repository: repo,
      catalog: CategoryCatalog(CategoryRepository(db), logger),
      logger: logger,
    );
    final result = await closed.save(MovementDraft(
      type: MovementType.egreso,
      amountText: '4321.99',
      date: DateTime(year, 11, 1),
      categoryId: 1,
      paymentMethod: PaymentMethod.efectivo,
      description: 'Farmacia Secreta',
      note: 'nota privada 123456',
    ));
    expect(result.isSuccess, isFalse);
    await closed.list();
    db = await openSpendyDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(dir.path, databaseFileName),
    );

    final log = logFile.readAsStringSync();
    expect(log.trim().split('\n'), hasLength(greaterThanOrEqualTo(2)));
    for (final secret in [
      '4321',
      '432199',
      'Farmacia',
      'Secreta',
      'nota privada',
      '123456',
      dir.path,
    ]) {
      expect(log, isNot(contains(secret)), reason: 'no debe guardar $secret');
    }
  });
}
