// Pruebas de las pantallas del incremento 1 (M-01) con repositorios en
// memoria: formulario, lista, estado vacío, errores y texto al 200 %.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/config/categories.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/formatters.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/category_repository.dart';
import 'package:spendy/data/repositories/movement_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';

class MemoryCategoryRepository implements CategoryRepository {
  @override
  Future<List<CategoryRecord>> fetchAll() async {
    var id = 1;
    return [
      for (final type in [MovementType.egreso, MovementType.ingreso])
        for (final (i, name) in Categories.forType(type).indexed)
          CategoryRecord(id: id++, name: name, type: type, order: i + 1),
    ];
  }

  @override
  Future<List<CategoryRecord>> fetchByType(MovementType type) async =>
      (await fetchAll()).where((c) => c.type == type).toList();
}

class MemoryMovementRepository implements MovementRepository {
  final List<Movement> rows = [];
  Object? insertError;

  @override
  Future<int> insert(Movement movement) async {
    final error = insertError;
    if (error != null) throw error;
    final names = {
      for (final c in await MemoryCategoryRepository().fetchAll()) c.id: c.name,
    };
    rows.add(Movement.fromRow({
      ...movement.toRow(),
      'id': rows.length + 1,
      'categoria_nombre': names[movement.categoryId],
    }));
    return rows.length;
  }

  @override
  Future<List<Movement>> fetchAll() async => rows.reversed.toList();
}

void main() {
  late MemoryMovementRepository repo;
  late CategoryCatalog catalog;
  late MovementService service;

  setUp(() {
    // En pruebas de widgets el disco real no responde dentro del reloj
    // simulado; la bitácora falla en silencio, como en producción.
    final logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    repo = MemoryMovementRepository();
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    service = MovementService(
      repository: repo,
      catalog: catalog,
      logger: logger,
    );
  });

  Future<void> pumpApp(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(SpendyApp(service: service, catalog: catalog));
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.text('Registrar mi primer movimiento'));
    await tester.pumpAndSettle();
  }

  final categoryDropdown = find.byType(DropdownButton<int>);
  final methodDropdown = find.byType(DropdownButton<PaymentMethod>);

  Future<void> choose(WidgetTester tester, Finder field, String option) async {
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('CA-013: lista vacía con botón para registrar el primero',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('Aún no tienes movimientos'), findsOneWidget);
    expect(find.text('Registrar mi primer movimiento'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('CA-001 / CA-012: registrar un egreso y verlo en la lista',
      (tester) async {
    await pumpApp(tester);
    await openForm(tester);
    expect(find.text(formatDate(DateTime.now())), findsOneWidget,
        reason: 'RF-03: la fecha de hoy viene seleccionada');
    await tester.enterText(find.byType(TextField).first, '1234.5');
    await choose(tester, categoryDropdown, 'Alimentos');
    await choose(tester, methodDropdown, 'Efectivo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Movimientos'), findsOneWidget);
    expect(find.text(r'−$1,234.50'), findsOneWidget);
    expect(find.text('Alimentos'), findsOneWidget);
    expect(find.textContaining('Egreso · '), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(repo.rows.single.amountCents, 123450);
  });

  testWidgets('CA-004: resalta faltantes y conserva lo capturado',
      (tester) async {
    await pumpApp(tester);
    await openForm(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nota (opcional)'),
        'Comida del lunes');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text(ErrorMessages.missingFields), findsOneWidget);
    expect(find.text('Escribe el monto.'), findsOneWidget);
    expect(find.text('El campo "Categoría" es obligatorio.'), findsOneWidget);
    expect(
        find.text('El campo "Método de pago" es obligatorio.'), findsOneWidget);
    expect(find.text('Comida del lunes'), findsOneWidget);
    expect(repo.rows, isEmpty);
  });

  testWidgets('CA-006: contadores 0/60 y 0/200 que no dejan pasar el límite',
      (tester) async {
    await pumpApp(tester);
    await openForm(tester);
    expect(find.text('0/60'), findsOneWidget);
    expect(find.text('0/200'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Nota (opcional)'), 'n' * 205);
    await tester.pump();
    expect(find.text('200/200'), findsOneWidget);
  });

  testWidgets('CA-010 / CA-036: en ingreso solo hay categorías de ingreso '
      'y no hay método de pago', (tester) async {
    await pumpApp(tester);
    await openForm(tester);
    await tester.tap(find.text('Ingreso'));
    await tester.pumpAndSettle();
    expect(find.text('Método de pago *'), findsNothing);
    expect(find.text('0/60'), findsNothing);
    await tester.tap(categoryDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Sueldos y salarios'), findsWidgets);
    expect(find.text('Otros ingresos'), findsWidgets);
    expect(find.text('Alimentos'), findsNothing);
  });

  testWidgets('CA-029: falla de escritura, mensaje, datos intactos y '
      'Reintentar', (tester) async {
    repo.insertError = const FileSystemException('escritura');
    await pumpApp(tester);
    await openForm(tester);
    await tester.enterText(find.byType(TextField).first, '350');
    await choose(tester, categoryDropdown, 'Alimentos');
    await choose(tester, methodDropdown, 'Débito');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text(ErrorMessages.saveFailed), findsOneWidget);
    expect(find.text('350'), findsOneWidget);
    expect(repo.rows, isEmpty);

    repo.insertError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text(r'−$350.00'), findsOneWidget);
  });

  testWidgets('RNF-06: texto al 200 % sin recortes en lista y formulario',
      (tester) async {
    await service.save(MovementDraft(
      type: MovementType.ingreso,
      amountText: '9999999.99',
      date: DateTime.now(),
      categoryId: 7,
    ));
    await pumpApp(tester, textScale: 2);
    expect(find.text(r'+$9,999,999.99'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Guardar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('RNF-06: botones con área táctil de al menos 44 x 44',
      (tester) async {
    await pumpApp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await openForm(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('StartupErrorApp muestra el mensaje', (tester) async {
    await tester.pumpWidget(
      const StartupErrorApp(message: ErrorMessages.loadFailed),
    );
    expect(find.text(ErrorMessages.loadFailed), findsOneWidget);
  });
}
