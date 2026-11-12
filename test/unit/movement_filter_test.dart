// Pruebas del incremento 6 para M-06 (MovementFilter) y la consulta
// filtrada de M-11, con SQLite real. RF-32 a RF-35; RNF-09; CA-083 a
// CA-094.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/categories.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/search/movement_filter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const int alimentos = 1;
const int transporte = 2;
const int servicios = 4;
const int sueldos = 7;

Movement row(
  MovementType type,
  int cents,
  DateTime date,
  int category, {
  String? description,
  String? note,
}) =>
    Movement(
      type: type,
      amountCents: cents,
      date: date,
      categoryId: category,
      paymentMethod: type == MovementType.egreso ? 'efectivo' : null,
      description: description,
      note: note,
      createdAt: date,
      updatedAt: date,
    );

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late Database db;
  late MovementRepository repository;
  late MovementFilter filter;
  late File logFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('spendy_filter_');
    logFile = File(p.join(tempDir.path, errorLogFileName));
    db = await openSpendyDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(tempDir.path, databaseFileName),
    );
    repository = MovementRepository(db);
    filter = MovementFilter(
      repository: repository,
      logger: ErrorLogger(() async => logFile),
    );
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> insertAll(List<Movement> movements) async {
    final batch = db.batch();
    for (final m in movements) {
      batch.insert('movimiento', m.toRow());
    }
    await batch.commit(noResult: true);
  }

  Future<FilterResult> run(MovementCriteria criteria) async =>
      (await filter.apply(criteria)).valueOrNull!;

  Future<void> seed() => insertAll([
        row(MovementType.egreso, 4550, DateTime(2026, 10, 3), alimentos,
            description: 'Café Tal'),
        row(MovementType.egreso, 120000, DateTime(2026, 10, 15), transporte,
            description: 'Gasolina', note: 'Viaje a León'),
        row(MovementType.egreso, 35000, DateTime(2026, 11, 2), servicios,
            description: 'Farmacia del Ahorro', note: 'descuento 50% y_más'),
        row(MovementType.egreso, 8000, DateTime(2026, 11, 5), transporte,
            description: "Taxi O'Hara"),
        row(MovementType.ingreso, 1500000, DateTime(2026, 11, 1), sueldos,
            note: 'Quincena CAFÉ'),
        row(MovementType.egreso, 999, DateTime(2025, 12, 31), alimentos,
            description: 'cafeteria vieja'),
      ]);

  test('CA-083: rango de fechas y categoría se combinan', () async {
    await seed();
    final result = await run(MovementCriteria(
      startDate: DateTime(2026, 10, 1),
      endDate: DateTime(2026, 11, 30),
      categoryId: transporte,
    ));
    expect(result.items.map((i) => i.description), ["Taxi O'Hara", 'Gasolina']);
  });

  test('los extremos del rango se incluyen', () async {
    await seed();
    final result = await run(MovementCriteria(
      startDate: DateTime(2026, 10, 3),
      endDate: DateTime(2026, 10, 3),
    ));
    expect(result.count, 1);
  });

  test('CA-084: fecha final anterior a la inicial no aplica el filtro',
      () async {
    await seed();
    final result = await filter.apply(MovementCriteria(
      startDate: DateTime(2026, 11, 10),
      endDate: DateTime(2026, 11, 1),
    ));
    expect(result.errorOrNull!.type, ErrorType.validation);
    expect(result.errorOrNull!.message, 'El rango de fechas no es válido');
    expect(
      filter.validate(MovementCriteria(startDate: DateTime(2026, 1, 1))),
      isNull,
    );
  });

  test('CA-087 / CA-090: sin distinguir mayúsculas ni acentos', () async {
    await seed();
    final cafe = await run(const MovementCriteria(text: 'cafe'));
    expect(cafe.count, 3, reason: 'Café Tal, Quincena CAFÉ, cafeteria');
    final farmacia = await run(const MovementCriteria(text: 'farmacia'));
    expect(farmacia.items.single.description, 'Farmacia del Ahorro');
    final leon = await run(const MovementCriteria(text: 'LEON'));
    expect(leon.items.single.note, 'Viaje a León');
    expect(normalizeForSearch('ÁÉÍÓÚÜÑ ñandú'), 'aeiouun nandu');
  });

  test("CA-088: '%', '_' y comillas son literales y no fallan", () async {
    await seed();
    expect((await run(const MovementCriteria(text: '50%'))).count, 1);
    expect((await run(const MovementCriteria(text: 'y_m'))).count, 1);
    expect((await run(const MovementCriteria(text: "O'Ha"))).count, 1);
    expect((await run(const MovementCriteria(text: '%'))).count, 1);
    expect((await run(const MovementCriteria(text: '_'))).count, 1);
    expect(
        (await run(const MovementCriteria(text: "'; DROP TABLE x"))).count, 0);
    expect(await repository.fetchAll(), hasLength(6));
  });

  test('CA-091: tipo, rango y texto a la vez', () async {
    await seed();
    final result = await run(MovementCriteria(
      type: MovementType.egreso,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      text: 'café',
    ));
    expect(result.items.single.description, 'Café Tal');
  });

  test('CA-092: conteo y suma de un solo tipo', () async {
    await seed();
    final result = await run(const MovementCriteria(type: MovementType.egreso));
    expect(result.count, 5);
    expect(result.countLabel, '5 resultados');
    expect(result.totalCents, 4550 + 120000 + 35000 + 8000 + 999);
    expect(result.sumLabel, r'Suma: $1,685.49');
    expect(result.isMixed, isFalse);
  });

  test('CA-093: sin resultados, 0 y \$0.00', () async {
    await seed();
    final result = await run(const MovementCriteria(text: 'no existe'));
    expect(result.count, 0);
    expect(result.countLabel, '0 resultados');
    expect(result.sumLabel, r'Suma: $0.00');
  });

  test('CA-094: con ingresos y egresos, sumas separadas', () async {
    await seed();
    final result = await run(MovementCriteria(
      startDate: DateTime(2026, 11, 1),
      endDate: DateTime(2026, 11, 30),
    ));
    expect(result.isMixed, isTrue);
    expect(result.incomeCents, 1500000);
    expect(result.expenseCents, 43000);
    expect(result.sumLabel, r'Ingresos: $15,000.00 · Egresos: $430.00');
    final one = await run(const MovementCriteria(text: 'gasolina'));
    expect(one.countLabel, '1 resultado');
  });

  test('criterios vacíos y copyWith', () {
    const empty = MovementCriteria();
    expect(empty.isEmpty, isTrue);
    expect(const MovementCriteria(text: '   ').isEmpty, isTrue);
    final changed = empty.copyWith(categoryId: () => 3, text: 'x');
    expect(changed.categoryId, 3);
    expect(changed.copyWith(categoryId: () => null).categoryId, isNull);
    expect(changed.isEmpty, isFalse);
  });

  test('RNF-09: la consulta usa los índices', () async {
    for (final (where, index) in [
      ('m.fecha >= ?', 'idx_movimiento_fecha'),
      ('m.categoria_id = ?', 'idx_movimiento_categoria'),
      ("m.tipo = ? AND m.fecha >= ?", 'idx_movimiento_tipo_fecha'),
    ]) {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM movimiento m WHERE $where',
        where.contains('AND') ? ['egreso', '2026-01-01'] : ['x'],
      );
      expect(plan.toString(), contains(index));
    }
  });

  test('CA-086 / RNF-09: con 2,000 movimientos cada filtro tarda <= 1 s',
      () async {
    await insertAll([
      for (var i = 0; i < 2000; i++)
        row(
          i % 5 == 0 ? MovementType.ingreso : MovementType.egreso,
          100 + i,
          DateTime(2025 + i % 2, 1 + i % 12, 1 + i % 28),
          i % 5 == 0 ? sueldos : 1 + i % 6,
          description: i % 3 == 0 ? 'Café número $i' : 'Compra $i',
          note: i % 7 == 0 ? 'Nota con acentos ñandú' : null,
        ),
    ]);
    final criteria = [
      const MovementCriteria(text: 'cafe'),
      MovementCriteria(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 6, 30),
        categoryId: transporte,
        type: MovementType.egreso,
        text: 'compra',
      ),
      const MovementCriteria(type: MovementType.ingreso, text: 'nandu'),
      MovementCriteria(startDate: DateTime(2025, 3, 1)),
    ];
    for (final c in criteria) {
      final watch = Stopwatch()..start();
      final result = await run(c);
      watch.stop();
      // ignore: avoid_print
      print('RNF-09: ${result.countLabel} en ${watch.elapsedMilliseconds} ms');
      expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 1)));
    }
  });

  test('si la base falla, error no técnico y bitácora', () async {
    await db.close();
    final result = await filter.apply(const MovementCriteria(text: 'x'));
    expect(result.errorOrNull!.type, ErrorType.storageRead);
    expect(logFile.readAsStringSync(), contains('M-06'));
  });

  test('todas las categorías de egreso pueden filtrarse', () async {
    await seed();
    for (var id = 1; id <= Categories.expenseCategories.length; id++) {
      final result = await run(MovementCriteria(categoryId: id));
      expect(result.items.every((i) => i.categoryId == id), isTrue);
    }
  });
}
