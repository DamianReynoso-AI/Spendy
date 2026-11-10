// Pruebas del incremento 1: M-02 (servicio de movimientos), M-03 (catálogo),
// M-11 (SQLite en memoria y en archivo) y M-13 (resultado y bitácora).
// Cubre CA-001 a CA-015, CA-029 a CA-039, CA-067 y CA-147 a CA-153.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/core/validators.dart';
import 'package:spendy/data/database.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ids fijos de la migración v1: egresos 1 a 6, ingresos 7 y 8.
const int alimentos = 1;
const int transporte = 2;
const int sueldos = 7;
const int otrosIngresos = 8;

/// "Hoy" fijo para las pruebas: 10/11/2026 a mediodía.
final DateTime today = DateTime(2026, 11, 10);

/// Reloj que avanza un segundo en cada llamada, para que `creado_en`
/// sea distinto en cada movimiento.
class TestClock {
  DateTime _now = DateTime(2026, 11, 10, 12);
  DateTime call() => _now = _now.add(const Duration(seconds: 1));
}

/// Repositorio que falla a voluntad (RF-11). Implementa la interfaz del
/// repositorio real, así el servicio no sabe que es simulado.
class FakeMovementRepository implements MovementRepository {
  Object? insertError;
  Object? fetchError;
  final List<Movement> saved = [];

  @override
  Future<int> insert(Movement movement) async {
    final error = insertError;
    if (error != null) throw error;
    saved.add(movement);
    return saved.length;
  }

  @override
  Future<List<Movement>> fetchAll() async {
    final error = fetchError;
    if (error != null) throw error;
    return const [];
  }
}

/// Repositorio de categorías que siempre falla al leer.
class FailingCategoryRepository implements CategoryRepository {
  @override
  Future<List<CategoryRecord>> fetchAll() async =>
      throw const FileSystemException('lectura');

  @override
  Future<List<CategoryRecord>> fetchByType(MovementType type) => fetchAll();
}

/// Excepción con datos del usuario en su mensaje, como la que daría un
/// INSERT fallido. La bitácora no debe copiar ese texto.
class LeakyStorageException implements Exception {
  @override
  String toString() =>
      'database or disk is full: INSERT args [35000, Tienda La Esquina, '
      'Comida del lunes]';
}

MovementDraft expense({
  String? amount = '350.00',
  DateTime? date,
  int? categoryId = alimentos,
  PaymentMethod? method = PaymentMethod.efectivo,
  String? description,
  String? note,
}) =>
    MovementDraft(
      type: MovementType.egreso,
      amountText: amount,
      date: date ?? today,
      categoryId: categoryId,
      paymentMethod: method,
      description: description,
      note: note,
    );

MovementDraft income({
  String? amount = '15000.00',
  DateTime? date,
  int? categoryId = sueldos,
  PaymentMethod? method,
  String? description,
  String? note,
  bool noDate = false,
}) =>
    MovementDraft(
      type: MovementType.ingreso,
      amountText: amount,
      date: noDate ? null : (date ?? today),
      categoryId: categoryId,
      paymentMethod: method,
      description: description,
      note: note,
    );

AppError errorOf(Result<Object?> result) {
  expect(result, isA<Failure<Object?>>());
  return result.errorOrNull!;
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late File logFile;
  late ErrorLogger logger;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('spendy_test_');
    logFile = File('${tempDir.path}/$errorLogFileName');
    logger = ErrorLogger(
      () async => logFile,
      clock: () => DateTime.utc(2026, 11, 10, 18, 30),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('con SQLite real (M-11 + M-03 + M-02)', () {
    late Database db;
    late MovementService service;
    late CategoryCatalog catalog;
    late MovementRepository repository;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: factory,
        path: '${tempDir.path}/$databaseFileName',
      );
      repository = MovementRepository(db);
      catalog = CategoryCatalog(CategoryRepository(db), logger);
      service = MovementService(
        repository: repository,
        catalog: catalog,
        logger: logger,
        clock: TestClock().call,
      );
    });

    tearDown(() => db.close());

    Future<int> count() async => Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM movimiento'),
        )!;

    Future<List<MovementItem>> listed() async =>
        (await service.list()).valueOrNull!;

    group('HU-01 egreso (RF-01)', () {
      test('CA-001 éxito: \$350.00, hoy, Alimentos, efectivo', () async {
        final result = await service.save(expense());
        expect(result.isSuccess, isTrue);
        final rows = await db.query('movimiento');
        expect(rows.single['monto_centavos'], 35000);
        expect(rows.single['fecha'], '2026-11-10');
        expect(rows.single['metodo_pago'], 'efectivo');
        final item = (await listed()).single;
        expect(item.formattedAmount, r'$350.00');
        expect(item.categoryName, 'Alimentos');
        expect(item.paymentMethod, PaymentMethod.efectivo);
        expect(item.isIncome, isFalse);
      });

      test('CA-002 / CA-008 error: 0, negativo, letras, 3 decimales',
          () async {
        for (final amount in ['0', '0.00', '-5', 'abc', '10.999']) {
          final error = errorOf(await service.save(expense(amount: amount)));
          expect(error.type, ErrorType.validation);
          expect(
            error.fieldErrors[MovementFields.amount],
            ValidationMessages.amountInvalid,
            reason: 'monto: $amount',
          );
        }
        expect(await count(), 0);
      });

      test('CA-003 error: fecha futura no se guarda', () async {
        final tomorrow = today.add(const Duration(days: 1));
        final error = errorOf(await service.save(expense(date: tomorrow)));
        expect(error.fieldErrors[MovementFields.date],
            ValidationMessages.dateFuture);
        expect(await count(), 0);
      });

      test('CA-004 error: indica monto, categoría y método faltantes',
          () async {
        final draft = expense(
          amount: '  ',
          categoryId: null,
          method: null,
          note: 'Comida del lunes',
        );
        final error = errorOf(await service.save(draft));
        expect(error.message, ErrorMessages.missingFields);
        expect(error.missingFields, [
          MovementFields.amount,
          MovementFields.category,
          MovementFields.paymentMethod,
        ]);
        expect(error.fieldErrors[MovementFields.paymentMethod],
            ValidationMessages.requiredField('Método de pago'));
        // Lo capturado no se pierde: el borrador sigue igual.
        expect(draft.note, 'Comida del lunes');
        expect(await count(), 0);
      });

      test('CA-005 límite: 9999999.99 sí; 10000000.00 no', () async {
        expect((await service.save(expense(amount: '9999999.99'))).isSuccess,
            isTrue);
        final error = errorOf(await service.save(expense(amount: '10000000.00')));
        expect(error.fieldErrors[MovementFields.amount],
            ValidationMessages.amountTooHigh);
        final rows = await db.query('movimiento');
        expect(rows.single['monto_centavos'], 999999999);
      });

      test('CA-006 límite: descripción 60 y nota 200 sí; 61 y 201 no',
          () async {
        final ok = expense(description: 'd' * 60, note: 'n' * 200);
        expect((await service.save(ok)).isSuccess, isTrue);
        final tooLong = expense(description: 'd' * 61, note: 'n' * 201);
        final error = errorOf(await service.save(tooLong));
        expect(error.message, ErrorMessages.invalidFields);
        expect(error.missingFields, isEmpty);
        expect(error.fieldErrors[MovementFields.description],
            ValidationMessages.textTooLong(60));
        expect(error.fieldErrors[MovementFields.note],
            ValidationMessages.textTooLong(200));
        expect(await count(), 1);
      });

      test('descripción y nota se guardan sin espacios; vacías como null',
          () async {
        await service.save(expense(description: '  Tienda  ', note: '   '));
        final row = (await db.query('movimiento')).single;
        expect(row['descripcion'], 'Tienda');
        expect(row['nota'], isNull);
      });
    });

    group('HU-02 ingreso (RF-02)', () {
      test('CA-007 éxito: \$15,000.00, hoy, Sueldos y salarios', () async {
        final result = await service.save(income(note: 'Quincena'));
        expect(result.isSuccess, isTrue);
        final row = (await db.query('movimiento')).single;
        expect(row['tipo'], 'ingreso');
        expect(row['monto_centavos'], 1500000);
        expect(row['metodo_pago'], isNull);
        expect(row['descripcion'], isNull);
        expect(row['nota'], 'Quincena');
        final item = (await listed()).single;
        expect(item.formattedAmount, r'$15,000.00');
        expect(item.isIncome, isTrue);
        expect(item.paymentMethod, isNull);
      });

      test('CA-008 error: monto 0 en ingreso', () async {
        final error = errorOf(await service.save(income(amount: '0')));
        expect(error.fieldErrors.keys, [MovementFields.amount]);
        expect(await count(), 0);
      });

      test('CA-009 error: falta monto, fecha y categoría', () async {
        final draft = income(amount: null, categoryId: null, noDate: true);
        final error = errorOf(await service.save(draft));
        expect(error.missingFields, [
          MovementFields.amount,
          MovementFields.date,
          MovementFields.category,
        ]);
        expect(error.fieldErrors[MovementFields.date],
            ValidationMessages.dateRequired);
        expect(await count(), 0);
      });

      test('CA-010 error: en ingreso solo hay categorías de ingreso',
          () async {
        final options = (await catalog.forType(MovementType.ingreso))
            .valueOrNull!
            .map((c) => c.name);
        expect(options, ['Sueldos y salarios', 'Otros ingresos']);
      });

      test('RF-02: ingreso con método de pago o descripción se rechaza',
          () async {
        final draft = income(
          method: PaymentMethod.debito,
          description: 'Empresa',
        );
        final error = errorOf(await service.save(draft));
        expect(error.fieldErrors[MovementFields.paymentMethod],
            MovementMessages.incomeNoPaymentMethod);
        expect(error.fieldErrors[MovementFields.description],
            MovementMessages.incomeNoDescription);
        expect(await count(), 0);
      });

      test('RF-02: nota de ingreso máximo 200', () async {
        final error = errorOf(await service.save(income(note: 'n' * 201)));
        expect(error.fieldErrors.keys, [MovementFields.note]);
      });

      test('CA-011 límite: 31/12 del año pasado sí; mañana no', () async {
        final lastYear = DateTime(2025, 12, 31);
        expect((await service.save(income(date: lastYear))).isSuccess, isTrue);
        final tomorrow = DateTime(2026, 11, 11);
        final error = errorOf(await service.save(income(date: tomorrow)));
        expect(error.fieldErrors[MovementFields.date],
            ValidationMessages.dateFuture);
        expect(await count(), 1);
      });

      test('la fecha se guarda sin hora (TEC-09)', () async {
        await service.save(income(date: DateTime(2026, 3, 5, 23, 59)));
        final row = (await db.query('movimiento')).single;
        expect(row['fecha'], '2026-03-05');
      });
    });

    group('HU-03 lista (RF-07)', () {
      test('CA-012 éxito: del más reciente al más antiguo, con tipo, monto, '
          'fecha y categoría', () async {
        await service.save(expense(date: DateTime(2026, 11, 1)));
        await service.save(income(date: DateTime(2026, 11, 9)));
        await service.save(
          expense(date: DateTime(2026, 10, 15), categoryId: transporte),
        );
        final items = await listed();
        expect(items.map((i) => i.formattedDate),
            ['09/11/2026', '01/11/2026', '15/10/2026']);
        expect(items.map((i) => i.isIncome), [true, false, false]);
        expect(items.map((i) => i.categoryName),
            ['Sueldos y salarios', 'Alimentos', 'Transporte']);
        expect(items.first.id, isPositive);
      });

      test('CA-013: sin movimientos la lista está vacía (no es error)',
          () async {
        final result = await service.list();
        expect(result.isSuccess, isTrue);
        expect(result.valueOrNull, isEmpty);
      });

      test('CA-014 límite: misma fecha, primero el creado más tarde y el '
          'orden no cambia', () async {
        await service.save(expense(amount: '1'));
        await service.save(expense(amount: '2'));
        await service.save(expense(amount: '3'));
        final first = (await listed()).map((i) => i.amountCents).toList();
        final second = (await listed()).map((i) => i.amountCents).toList();
        expect(first, [300, 200, 100]);
        expect(second, first);
      });

      test('CA-015 límite: 2,000 movimientos cargan en 2 s o menos', () async {
        final batch = db.batch();
        for (var i = 0; i < 2000; i++) {
          final created = DateTime(2026, 1, 1).add(Duration(minutes: i));
          batch.insert(
            'movimiento',
            Movement(
              type: i.isEven ? MovementType.egreso : MovementType.ingreso,
              amountCents: 100 + i,
              date: DateTime(2026, 1, 1).add(Duration(days: i % 300)),
              categoryId: i.isEven ? alimentos : sueldos,
              paymentMethod: i.isEven ? 'efectivo' : null,
              createdAt: created,
              updatedAt: created,
            ).toRow(),
          );
        }
        await batch.commit(noResult: true);
        final watch = Stopwatch()..start();
        final items = await listed();
        watch.stop();
        expect(items, hasLength(2000));
        expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 2)));
      });
    });

    group('HU-08 y HU-09 categorías (RF-12 a RF-14)', () {
      test('CA-032 éxito: las 6 categorías de egreso en orden', () async {
        final names = (await catalog.forType(MovementType.egreso))
            .valueOrNull!
            .map((c) => c.name);
        expect(names, [
          'Alimentos',
          'Transporte',
          'Vivienda',
          'Servicios',
          'Entretenimiento',
          'Otros',
        ]);
      });

      test('CA-033 error: egreso sin categoría no se guarda', () async {
        final error = errorOf(await service.save(expense(categoryId: null)));
        expect(error.missingFields, [MovementFields.category]);
        expect(error.fieldErrors[MovementFields.category],
            ValidationMessages.requiredField('Categoría'));
        expect(await count(), 0);
      });

      test('CA-034 error: el catálogo es fijo y de solo lectura', () async {
        final options =
            (await catalog.forType(MovementType.egreso)).valueOrNull!;
        expect(
          () => options.add(
            const CategoryOption(id: 99, name: 'Nueva', type: MovementType.egreso),
          ),
          throwsUnsupportedError,
        );
        final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM categoria'),
        );
        expect(total, 8);
      });

      test('CA-035: la categoría elegida es la que se guarda y se lista',
          () async {
        await service.save(expense(categoryId: transporte));
        expect((await listed()).single.categoryName, 'Transporte');
      });

      test('CA-036 éxito: ingreso solo ve sus 2 categorías', () async {
        final options =
            (await catalog.forType(MovementType.ingreso)).valueOrNull!;
        expect(options.map((c) => c.id), [sueldos, otrosIngresos]);
        expect(options.every((c) => c.type == MovementType.ingreso), isTrue);
      });

      test('CA-037 error: ingreso sin categoría no se guarda', () async {
        final error = errorOf(await service.save(income(categoryId: null)));
        expect(error.missingFields, [MovementFields.category]);
        expect(await count(), 0);
      });

      test('CA-038 error: ingreso con "Alimentos" se rechaza (RF-14)',
          () async {
        final names = (await catalog.forType(MovementType.ingreso))
            .valueOrNull!
            .map((c) => c.name);
        expect(names, isNot(contains('Alimentos')));
        final error = errorOf(await service.save(income(categoryId: alimentos)));
        expect(error.fieldErrors[MovementFields.category],
            MovementMessages.categoryWrongType);
        expect(await count(), 0);
      });

      test('RF-14: egreso con categoría de ingreso o inexistente se rechaza',
          () async {
        for (final id in [sueldos, 999]) {
          final error = errorOf(await service.save(expense(categoryId: id)));
          expect(error.fieldErrors[MovementFields.category],
              MovementMessages.categoryWrongType);
        }
        expect(await count(), 0);
      });

      test('CA-039: "Otros ingresos" se guarda con su propia categoría',
          () async {
        await service.save(income(categoryId: sueldos));
        await service.save(income(categoryId: otrosIngresos));
        expect((await listed()).map((i) => i.categoryName),
            ['Otros ingresos', 'Sueldos y salarios']);
      });

      test('el repositorio filtra por tipo en su orden', () async {
        final records =
            await CategoryRepository(db).fetchByType(MovementType.ingreso);
        expect(records.map((r) => r.order), [1, 2]);
      });
    });

    group('HU-39 persistencia (RF-53)', () {
      test('CA-147 éxito: los datos siguen al cerrar y reabrir la app',
          () async {
        await service.save(expense(note: 'Comida del lunes'));
        await db.close();
        db = await openSpendyDatabase(
          factory: factory,
          path: '${tempDir.path}/$databaseFileName',
        );
        final items = await MovementRepository(db).fetchAll();
        expect(items.single.note, 'Comida del lunes');
        expect(items.single.amountCents, 35000);
      });

      test('CA-148 / CA-031: un guardado que falla no deja nada a medias',
          () async {
        await service.save(expense());
        final broken = Movement(
          type: MovementType.egreso,
          amountCents: 100,
          date: today,
          categoryId: 999, // llave foránea inexistente
          paymentMethod: 'efectivo',
          createdAt: today,
          updatedAt: today,
        );
        await expectLater(repository.insert(broken), throwsA(anything));
        expect(await count(), 1);
        expect((await listed()).single.amountCents, 35000);
      });

      test('CA-149 límite: reabrir con la misma versión conserva los datos',
          () async {
        await service.save(income());
        await db.close();
        db = await openSpendyDatabase(
          factory: factory,
          path: '${tempDir.path}/$databaseFileName',
        );
        expect(await db.getVersion(), schemaVersion);
        expect(await MovementRepository(db).fetchAll(), hasLength(1));
        final categories = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM categoria'),
        );
        expect(categories, 8, reason: 'la migración no se repite');
      });

      test('RNF-14 / RNF-27: llaves foráneas, versión 1, tablas e índices',
          () async {
        final fk = Sqflite.firstIntValue(
          await db.rawQuery('PRAGMA foreign_keys'),
        );
        expect(fk, 1);
        expect(await db.getVersion(), 1);
        final objects = await db.rawQuery(
          "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
          "AND name != 'android_metadata' ORDER BY type, name",
        );
        expect(objects.map((r) => '${r['type']}:${r['name']}'), [
          'index:idx_movimiento_categoria',
          'index:idx_movimiento_fecha',
          'index:idx_movimiento_tipo_fecha',
          'table:ajuste',
          'table:categoria',
          'table:movimiento',
          'table:recibo',
        ]);
      });
    });

    group('HU-40 formato (RF-54)', () {
      test('CA-150 éxito: 1234.5 se ve como \$1,234.50 y DD/MM/AAAA',
          () async {
        await service.save(expense(amount: '1234.5', date: DateTime(2026, 1, 5)));
        final item = (await listed()).single;
        expect(item.amountCents, 123450);
        expect(item.formattedAmount, r'$1,234.50');
        expect(item.formattedDate, '05/01/2026');
      });

      test('CA-151 error: "12,5" se rechaza y no se guarda 125', () async {
        final error = errorOf(await service.save(expense(amount: '12,5')));
        expect(error.fieldErrors[MovementFields.amount],
            ValidationMessages.amountComma);
        expect(await count(), 0);
      });

      test('CA-153 límite: \$0.01 y \$9,999,999.99', () async {
        await service.save(expense(amount: '0.01'));
        await service.save(expense(amount: '9999999.99'));
        expect((await listed()).map((i) => i.formattedAmount),
            [r'$9,999,999.99', r'$0.01']);
      });
    });

    test('CA-067 error: total borrado o no válido no se guarda', () async {
      for (final amount in [null, '', 'abc', '1.2.3', '-1']) {
        final error = errorOf(await service.save(expense(amount: amount)));
        expect(error.fieldErrors, contains(MovementFields.amount));
      }
      expect(await count(), 0);
    });
  });

  group('HU-07 fallo de almacenamiento (RF-11, repositorio simulado)', () {
    late FakeMovementRepository fakeRepo;
    late MovementService service;
    late Database db;

    setUp(() async {
      db = await openSpendyDatabase(
        factory: factory,
        path: '${tempDir.path}/categorias.db',
      );
      fakeRepo = FakeMovementRepository();
      service = MovementService(
        repository: fakeRepo,
        catalog: CategoryCatalog(CategoryRepository(db), logger),
        logger: logger,
        clock: TestClock().call,
      );
    });

    tearDown(() => db.close());

    test('CA-029 éxito: falla, avisa, conserva y permite reintentar',
        () async {
      fakeRepo.insertError = const FileSystemException('escritura');
      final draft = expense(note: 'Comida del lunes');
      final error = errorOf(await service.save(draft));
      expect(error.type, ErrorType.storageWrite);
      expect(error.message, ErrorMessages.saveFailed);
      expect(error.message, contains('Reintentar'));
      expect(fakeRepo.saved, isEmpty);

      fakeRepo.insertError = null;
      final retry = await service.save(draft);
      expect(retry.valueOrNull, 1);
      expect(fakeRepo.saved.single.note, 'Comida del lunes');
    });

    test('CA-030 error: sin espacio, mensaje no técnico y nada a medias',
        () async {
      fakeRepo.insertError = LeakyStorageException();
      final error = errorOf(
        await service.save(
          expense(description: 'Tienda La Esquina', note: 'Comida del lunes'),
        ),
      );
      expect(error.type, ErrorType.storageFull);
      expect(error.message, ErrorMessages.storageFull);
      expect(error.message, isNot(contains('SQLITE')));
      expect(error.message, isNot(contains('INSERT')));
      expect(fakeRepo.saved, isEmpty);

      final log = logFile.readAsStringSync();
      expect(log, contains('almacenamiento_lleno | M-02 | '
          'LeakyStorageException'));
      for (final secret in ['35000', '350', 'Tienda', 'Comida', 'INSERT']) {
        expect(log, isNot(contains(secret)), reason: 'RNF-20: $secret');
      }
    });

    test('CA-031: si el guardado falla no queda ningún movimiento', () async {
      fakeRepo.insertError = StateError('cierre');
      final error = errorOf(await service.save(expense()));
      expect(error.type, ErrorType.storageWrite);
      expect(fakeRepo.saved, isEmpty);
    });

    test('error de lectura de la lista: mensaje con acción siguiente',
        () async {
      fakeRepo.fetchError = const FileSystemException('lectura');
      final error = errorOf(await service.list());
      expect(error.type, ErrorType.storageRead);
      expect(error.message, ErrorMessages.loadFailed);
      expect(logFile.readAsStringSync(), contains('almacenamiento_lectura'));
    });

    test('una validación fallida no toca el repositorio', () async {
      fakeRepo.insertError = StateError('no debe llamarse');
      final error = errorOf(await service.save(expense(amount: '0')));
      expect(error.type, ErrorType.validation);
    });
  });

  group('M-03 sin base disponible', () {
    test('el catálogo devuelve error y el servicio no guarda', () async {
      final catalog = CategoryCatalog(FailingCategoryRepository(), logger);
      final forType = await catalog.forType(MovementType.egreso);
      expect(forType.errorOrNull?.message, ErrorMessages.loadFailed);
      final belongs = await catalog.belongsToType(alimentos, MovementType.egreso);
      expect(belongs.errorOrNull?.type, ErrorType.storageRead);

      final fakeRepo = FakeMovementRepository();
      final service = MovementService(
        repository: fakeRepo,
        catalog: catalog,
        logger: logger,
      );
      final error = errorOf(await service.save(expense()));
      expect(error.type, ErrorType.storageRead);
      expect(fakeRepo.saved, isEmpty);
    });
  });

  group('M-13 resultado, bitácora y mensajes', () {
    test('Result: éxito y fallo', () {
      const ok = Success(5);
      const AppError err =
          AppError(type: ErrorType.unexpected, message: 'x', fieldErrors: {
        'monto': 'a',
        'fecha': 'b',
      });
      const fail = Failure<int>(err);
      expect(ok.isSuccess, isTrue);
      expect(ok.valueOrNull, 5);
      expect(ok.errorOrNull, isNull);
      expect(fail.isSuccess, isFalse);
      expect(fail.valueOrNull, isNull);
      expect(fail.errorOrNull, same(err));
      expect(err.fields, ['monto', 'fecha']);
    });

    test('RNF-20: la línea tiene fecha, tipo, módulo y causa, sin datos',
        () {
      final fixed = ErrorLogger(
        () async => logFile,
        clock: () => DateTime.utc(2026, 11, 10, 18, 30),
      );
      final line = fixed.formatEntry(
        type: ErrorType.storageWrite,
        module: 'M-02 \n inyectado',
        cause: LeakyStorageException(),
      );
      expect(line,
          '2026-11-10T18:30:00.000Z | almacenamiento_escritura | M-02inyectado'
          ' | LeakyStorageException');
    });

    test('la bitácora agrega líneas y nunca rompe la app', () async {
      await logger.log(
        type: ErrorType.unexpected,
        module: 'M-02',
        cause: StateError('Tienda La Esquina'),
      );
      await logger.log(
        type: ErrorType.storageRead,
        module: 'M-03',
        cause: const FileSystemException('x'),
      );
      final lines = logFile.readAsLinesSync();
      expect(lines, hasLength(2));
      expect(lines.join(), isNot(contains('Tienda')));

      final broken = ErrorLogger(
        () async => File('${tempDir.path}/no/existe/$errorLogFileName'),
      );
      await expectLater(
        broken.log(type: ErrorType.unexpected, module: 'M-02', cause: 1),
        completes,
      );
    });

    test('RNF-05: traduce fallos técnicos a mensajes con acción', () {
      const enospc =
          FileSystemException('w', 'p', OSError('No space left', 28));
      expect(translateStorageError(enospc, writing: true).type,
          ErrorType.storageFull);
      expect(isDiskFullError(Exception('SQLITE_FULL')), isTrue);
      expect(isDiskFullError(Exception('otro')), isFalse);
      final write = translateStorageError(StateError('x'), writing: true);
      expect(write.type, ErrorType.storageWrite);
      final read = translateStorageError(StateError('x'), writing: false);
      expect(read.message, ErrorMessages.loadFailed);
      for (final message in [
        ErrorMessages.saveFailed,
        ErrorMessages.storageFull,
        ErrorMessages.loadFailed,
        ErrorMessages.unexpected,
      ]) {
        expect(message, isNot(matches(RegExp(r'Exception|SQL|errno|\d{2,}'))));
      }
    });
  });

  group('utilidades', () {
    test('amountTextToCents convierte sin redondeos', () {
      expect(amountTextToCents('1234.5'), 123450);
      expect(amountTextToCents('0.01'), 1);
      expect(amountTextToCents(' 7 '), 700);
      expect(amountTextToCents('9999999.99'), 999999999);
    });

    test('PaymentMethod.fromValue', () {
      expect(PaymentMethod.fromValue('credito'), PaymentMethod.credito);
      expect(PaymentMethod.fromValue('cheque'), isNull);
      expect(PaymentMethod.fromValue(null), isNull);
      expect(PaymentMethod.values.map((m) => m.value),
          ['efectivo', 'debito', 'credito', 'transferencia']);
    });

    test('toIsoDate y fromIsoDate (TEC-09)', () {
      expect(toIsoDate(DateTime(2026, 2, 3, 22, 10)), '2026-02-03');
      expect(fromIsoDate('2026-02-03'), DateTime(2026, 2, 3));
    });

    test('CA-152: idioma y región fijos en es-MX', () {
      expect(spendyLocale.languageCode, 'es');
      expect(spendyLocale.countryCode, 'MX');
    });
  });
}
