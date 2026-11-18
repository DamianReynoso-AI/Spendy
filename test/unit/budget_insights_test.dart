// Pruebas de las migraciones (RNF-27), los presupuestos por categoría
// (M-14) y los indicadores del mes (M-15).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/migrations/v1_initial.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/budget_repository.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/budgets/budget_calculator.dart';
import 'package:spendy/modules/budgets/budget_service.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/insights/insights_calculator.dart';
import 'package:spendy/modules/insights/insights_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Categorías de la migración v1: 1 Alimentos, 2 Transporte, 7 Sueldos.
const int food = 1;
const int transport = 2;
const int salary = 7;

Movement mov(
  int cents,
  DateTime date, {
  int category = food,
  MovementType type = MovementType.egreso,
  String? name,
}) =>
    Movement(
      type: type,
      amountCents: cents,
      date: date,
      categoryId: category,
      categoryName: name,
      paymentMethod: type == MovementType.egreso ? 'efectivo' : null,
      createdAt: date,
      updatedAt: date,
    );

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late ErrorLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_budget_');
    logger =
        ErrorLogger(() async => File(p.join(tempDir.path, errorLogFileName)));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('Migraciones (RNF-27)', () {
    test('una base v1 con datos sube a v2 sin perder nada', () async {
      final path = p.join(tempDir.path, databaseFileName);
      final v1 = await databaseFactoryFfiNoIsolate.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 1, onCreate: V1Initial.apply),
      );
      await v1.insert('movimiento', mov(12345, DateTime(2026, 11, 3)).toRow());
      await v1.close();

      final db = await openSpendyDatabase(
          factory: databaseFactoryFfiNoIsolate, path: path);
      expect(await db.getVersion(), schemaVersion);
      expect(await MovementRepository(db).fetchAll(), hasLength(1));
      await BudgetRepository(db).setLimit(food, 50000);
      expect(await BudgetRepository(db).fetchAll(), {food: 50000});
      await db.close();
    });

    test('el restablecimiento también borra los presupuestos', () async {
      final db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
      await BudgetRepository(db).setLimit(food, 100);
      await wipeUserData(db);
      expect(await BudgetRepository(db).fetchAll(), isEmpty);
      await db.close();
    });
  });

  group('BudgetCalculator', () {
    const calc = BudgetCalculator();
    final names = {food: 'Alimentos', transport: 'Transporte'};

    test('solo cuenta egresos de cada categoría con límite', () {
      final lines = calc.calculate(
        limits: {food: 100000},
        names: names,
        movements: [
          mov(30000, DateTime(2026, 11, 2)),
          mov(20000, DateTime(2026, 11, 5)),
          mov(99999, DateTime(2026, 11, 5), category: transport),
          mov(500000, DateTime(2026, 11, 1),
              category: salary, type: MovementType.ingreso),
        ],
      );
      expect(lines, hasLength(1));
      expect(lines.single.categoryName, 'Alimentos');
      expect(lines.single.spentCents, 50000);
      expect(lines.single.remainingCents, 50000);
      expect(lines.single.status, BudgetStatus.ok);
    });

    test('avisa desde el 80 % y marca excedido al pasar el límite', () {
      BudgetStatus statusFor(int spent) => calc
          .calculate(
            limits: {food: 10000},
            names: names,
            movements: [mov(spent, DateTime(2026, 11, 1))],
          )
          .single
          .status;
      expect(statusFor(7999), BudgetStatus.ok);
      expect(statusFor(8000), BudgetStatus.warning);
      expect(statusFor(10000), BudgetStatus.warning);
      expect(statusFor(10001), BudgetStatus.exceeded);
    });
  });

  group('BudgetService con SQLite real', () {
    late Database db;
    late BudgetService service;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: p.join(tempDir.path, databaseFileName),
      );
      service = BudgetService(
        budgets: BudgetRepository(db),
        movements: MovementRepository(db),
        catalog: CategoryCatalog(CategoryRepository(db), logger),
        logger: logger,
        clock: () => DateTime(2026, 11, 18),
      );
    });

    tearDown(() => db.close());

    test('guarda, actualiza y quita límites', () async {
      expect((await service.setLimit(food, 150000)).isSuccess, isTrue);
      expect((await service.setLimit(food, 200000)).isSuccess, isTrue);
      expect((await service.limits()).valueOrNull, {food: 200000});
      expect((await service.setLimit(food, 0)).isSuccess, isTrue);
      expect((await service.limits()).valueOrNull, isEmpty);
    });

    test('rechaza montos mayores al máximo', () async {
      final r = await service.setLimit(food, 1000000000);
      expect(r, isA<Failure<void>>());
      expect(r.errorOrNull!.message, BudgetMessages.tooBig);
    });

    test('el avance solo usa movimientos del mes en curso', () async {
      final repo = MovementRepository(db);
      await repo.insert(mov(40000, DateTime(2026, 11, 10)));
      await repo.insert(mov(90000, DateTime(2026, 10, 31)));
      await service.setLimit(food, 50000);
      final overview = (await service.currentMonth()).valueOrNull!;
      expect(overview.month.month, 11);
      expect(overview.lines.single.spentCents, 40000);
      expect(overview.lines.single.status, BudgetStatus.warning);
      expect(overview.limitCents, 50000);
    });
  });

  group('InsightsCalculator', () {
    const calc = InsightsCalculator();

    test('compara contra el mismo avance del mes pasado', () {
      final r = calc.calculate(
        today: DateTime(2026, 11, 10),
        current: [
          mov(30000, DateTime(2026, 11, 2), name: 'Alimentos'),
          mov(50000, DateTime(2026, 11, 9),
              category: transport, name: 'Transporte'),
          mov(800000, DateTime(2026, 11, 1),
              category: salary, type: MovementType.ingreso, name: 'Sueldo'),
        ],
        previous: [
          mov(40000, DateTime(2026, 10, 5)),
          mov(999999, DateTime(2026, 10, 25)), // después del día 10: no
        ],
      );
      expect(r.expenseCents, 80000);
      expect(r.previousExpenseCents, 40000);
      expect(r.changePercent, 100);
      expect(r.topCategoryName, 'Transporte');
      expect(r.topCategoryCents, 50000);
      expect(r.dailyAverageCents, 8000);
      expect(r.projectedCents, 8000 * 30);
    });

    test('sin gasto el mes pasado no hay porcentaje', () {
      final r = calc.calculate(
        today: DateTime(2026, 11, 3),
        current: [mov(1000, DateTime(2026, 11, 1))],
        previous: const [],
      );
      expect(r.changePercent, isNull);
      expect(r.hasExpenses, isTrue);
    });

    test('días del mes, incluido febrero bisiesto', () {
      expect(InsightsCalculator.daysIn(2028, 2), 29);
      expect(InsightsCalculator.daysIn(2026, 2), 28);
      expect(InsightsCalculator.daysIn(2026, 12), 31);
    });
  });

  test('InsightsService lee enero contra diciembre del año anterior', () async {
    final db = await openSpendyDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: p.join(tempDir.path, databaseFileName),
    );
    final repo = MovementRepository(db);
    await repo.insert(mov(10000, DateTime(2026, 12, 3)));
    await repo.insert(mov(15000, DateTime(2027, 1, 2)));
    final service = InsightsService(
      repository: repo,
      logger: logger,
      clock: () => DateTime(2027, 1, 5),
    );
    final r = (await service.currentMonth()).valueOrNull!;
    expect(r.expenseCents, 15000);
    expect(r.previousExpenseCents, 10000);
    expect(r.changePercent, 50);
    await db.close();
  });
}
