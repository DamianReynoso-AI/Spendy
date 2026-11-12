// Pruebas del incremento 5 para M-07: AnnualSummaryCalculator (lógica
// pura) y SummaryService con SQLite real, incluida la medición con 2,000
// movimientos. RF-36 a RF-40; RNF-10, RNF-33; CA-095 a CA-106.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/config/categories.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/summary/annual_summary_calculator.dart';
import 'package:spendy/modules/summary/summary_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ids fijos de la migración v1: egresos 1 a 6, ingresos 7 y 8.
const Map<String, int> categoryIds = {
  'Alimentos': 1,
  'Transporte': 2,
  'Vivienda': 3,
  'Servicios': 4,
  'Entretenimiento': 5,
  'Otros': 6,
  'Sueldos y salarios': 7,
  'Otros ingresos': 8,
};

Movement movement(
  MovementType type,
  int cents,
  DateTime date, [
  String category = 'Alimentos',
]) =>
    Movement(
      type: type,
      amountCents: cents,
      date: date,
      categoryId: categoryIds[category] ?? 6,
      categoryName: category,
      paymentMethod: type == MovementType.egreso ? 'efectivo' : null,
      createdAt: date,
      updatedAt: date,
    );

Movement expense(int cents, DateTime date, [String category = 'Alimentos']) =>
    movement(MovementType.egreso, cents, date, category);

Movement income(int cents, DateTime date) =>
    movement(MovementType.ingreso, cents, date, 'Sueldos y salarios');

/// 2,000 movimientos repartidos en 2025 y 2026, con montos variados.
List<Movement> sampleMovements(int count) => [
      for (var i = 0; i < count; i++)
        i % 4 == 0
            ? income(150000 + i, DateTime(2025 + i % 2, 1 + i % 12, 1 + i % 28))
            : expense(
                1000 + i * 37,
                DateTime(2025 + i % 2, 1 + i % 12, 1 + i % 28),
                Categories.expenseCategories[i % 6],
              ),
    ];

void main() {
  const calculator = AnnualSummaryCalculator();
  final now = DateTime(2026, 11, 12);

  group('selector de años (RF-36)', () {
    test('CA-095: años con movimientos y el actual por defecto', () {
      final options = calculator.yearOptions([2025, 2026], now);
      expect(options.years, [2026, 2025]);
      expect(options.selected, 2026);
    });

    test('CA-097: solo el año en curso aparece una vez', () {
      expect(calculator.yearOptions([2026], now).years, [2026]);
    });

    test('sin movimientos aparece el año actual', () {
      expect(calculator.yearOptions(const [], now).years, [2026]);
    });

    test('años antiguos se ordenan de mayor a menor', () {
      expect(
        calculator.yearOptions([2021, 2024, 2023], now).years,
        [2026, 2024, 2023, 2021],
      );
    });
  });

  group('cálculo (RF-37 a RF-40)', () {
    test('CA-096 / CA-098: año sin movimientos da aviso, no resumen vacío', () {
      final summary = calculator.calculate(2024, [
        expense(100, DateTime(2025, 1, 1)),
      ]);
      expect(summary.hasMovements, isFalse);
      expect(summary.movementCount, 0);
    });

    test('CA-099: totales y diferencia en centavos', () {
      final summary = calculator.calculate(2026, [
        income(1500000, DateTime(2026, 1, 15)),
        expense(35050, DateTime(2026, 3, 1)),
        expense(10, DateTime(2026, 12, 31), 'Transporte'),
        expense(99999, DateTime(2025, 12, 31)),
        income(1, DateTime(2027, 1, 1)),
      ]);
      expect(summary.incomeCents, 1500000);
      expect(summary.expenseCents, 35060);
      expect(summary.differenceCents, 1464940);
      expect(summary.formattedIncome, r'$15,000.00');
      expect(summary.formattedExpense, r'$350.60');
      expect(summary.formattedDifference, r'$14,649.40');
      expect(summary.movementCount, 3);
    });

    test('diferencia negativa', () {
      final summary = calculator.calculate(2026, [
        expense(50000, DateTime(2026, 5, 5)),
      ]);
      expect(summary.formattedDifference, r'-$500.00');
    });

    test('CA-106: las 6 categorías siempre aparecen, en orden y con \$0.00',
        () {
      final summary = calculator.calculate(2026, [
        expense(12345, DateTime(2026, 2, 2), 'Servicios'),
      ]);
      expect(
        summary.byCategory.map((c) => c.name),
        Categories.expenseCategories,
      );
      expect(summary.byCategory[0].formatted, r'$0.00');
      expect(summary.byCategory[3].formatted, r'$123.45');
    });

    test('CA-100 / CA-104 / CA-105: la suma por categoría es igual al total',
        () {
      final movements = sampleMovements(2000);
      final summary = calculator.calculate(2026, movements);
      final sumByCategory =
          summary.byCategory.fold<int>(0, (sum, c) => sum + c.cents);
      expect(sumByCategory, summary.expenseCents);
      final expected = movements
          .where((m) => m.date.year == 2026 && m.type == MovementType.egreso)
          .fold<int>(0, (sum, m) => sum + m.amountCents);
      expect(summary.expenseCents, expected);
    });

    test('un egreso con categoría desconocida cuenta en "Otros"', () {
      final summary = calculator.calculate(2026, [
        expense(700, DateTime(2026, 1, 1), 'Inexistente'),
      ]);
      expect(summary.byCategory.last.cents, 700);
      expect(summary.byCategory.last.name, 'Otros');
    });

    test('RNF-33: la calculadora no importa Flutter', () {
      final source = File(
        'lib/modules/summary/annual_summary_calculator.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('package:flutter')));
    });
  });

  group('SummaryService con SQLite real', () {
    sqfliteFfiInit();
    late Directory tempDir;
    late Database db;
    late MovementRepository repository;
    late SummaryService service;
    late File logFile;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('spendy_summary_');
      logFile = File(p.join(tempDir.path, errorLogFileName));
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
      repository = MovementRepository(db);
      service = SummaryService(
        repository: repository,
        logger: ErrorLogger(() async => logFile),
        clock: () => now,
      );
    });

    tearDown(() async {
      await db.close();
      tempDir.deleteSync(recursive: true);
    });

    Future<void> insertAll(List<Movement> movements) async {
      final batch = db.batch();
      for (final m in movements) {
        batch.insert('movimiento', m.toRow());
      }
      await batch.commit(noResult: true);
    }

    test('CA-095 / CA-101: años distintos y movimientos del año', () async {
      await insertAll([
        expense(100, DateTime(2024, 12, 31)),
        expense(200, DateTime(2025, 1, 1)),
        income(300, DateTime(2025, 12, 31)),
        expense(400, DateTime(2026, 1, 1)),
      ]);
      expect(await repository.getYearsWithMovements(), [2026, 2025, 2024]);
      final year2025 = await repository.getMovementsByYear(2025);
      expect(year2025.map((m) => m.amountCents), unorderedEquals([200, 300]));
      final options = (await service.yearOptions()).valueOrNull!;
      expect(options.years, [2026, 2025, 2024]);
      final summary = (await service.summaryFor(2025)).valueOrNull!;
      expect(summary.incomeCents, 300);
      expect(summary.expenseCents, 200);
    });

    test('CA-101: la consulta anual usa el índice de fecha', () async {
      final plan = await db.rawQuery(
        'EXPLAIN QUERY PLAN ${MovementRepository.monthSql}',
        ['2026-01-01', '2026-12-31'],
      );
      expect(plan.toString(), contains('idx_movimiento_fecha'));
    });

    test('CA-102 / RNF-10: con 2,000 movimientos el resumen tarda <= 3 s',
        () async {
      await insertAll(sampleMovements(2000));
      final watch = Stopwatch()..start();
      final options = (await service.yearOptions()).valueOrNull!;
      final summary = (await service.summaryFor(options.selected)).valueOrNull!;
      watch.stop();
      // ignore: avoid_print
      print('RNF-10: resumen de ${summary.movementCount} movimientos del año '
          '(2,000 en la base) en ${watch.elapsedMilliseconds} ms');
      expect(summary.movementCount, 1000);
      expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 3)));
    });

    test('si la base falla, mensaje no técnico y bitácora', () async {
      await db.close();
      final years = await service.yearOptions();
      expect(years.isSuccess, isFalse);
      expect((await service.summaryFor(2026)).isSuccess, isFalse);
      expect(logFile.readAsStringSync(), contains('M-07'));
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
    });
  });
}
