// Pruebas de las pantallas de los incrementos 1 y 2 (M-01) con
// repositorios en memoria: formulario, lista, estado vacío, errores, texto
// al 200 %, balance del mes, detalle, edición y eliminación.
import 'dart:async';
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
  Object? updateError;
  int deleteCalls = 0;

  /// Si no es `null`, cada baja espera a que se complete (CA-024).
  Completer<void>? deleteGate;

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

  @override
  Future<Movement?> findById(int id) async =>
      rows.where((m) => m.id == id).firstOrNull;

  @override
  Future<int> updateMovement(Movement movement) async {
    final error = updateError;
    if (error != null) throw error;
    final index = rows.indexWhere((m) => m.id == movement.id);
    if (index < 0) return 0;
    final names = {
      for (final c in await MemoryCategoryRepository().fetchAll()) c.id: c.name,
    };
    rows[index] = Movement.fromRow({
      ...movement.toRow(),
      'id': movement.id,
      'categoria_nombre': names[movement.categoryId],
    });
    return 1;
  }

  @override
  Future<int> deleteMovement(int id) async {
    deleteCalls++;
    await deleteGate?.future;
    final before = rows.length;
    rows.removeWhere((m) => m.id == id);
    return before - rows.length;
  }

  @override
  Future<List<Movement>> getMovementsByMonth(int year, int month) async =>
      rows.where((m) => m.date.year == year && m.date.month == month).toList();
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
    await tester.enterText(
        find.widgetWithText(TextField, 'Nota (opcional)'), 'Comida del lunes');
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

  testWidgets(
      'CA-010 / CA-036: en ingreso solo hay categorías de ingreso '
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

  testWidgets(
      'CA-029: falla de escritura, mensaje, datos intactos y '
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

  // ---------------- Incremento 2 ----------------

  Future<void> seed(String amount, {MovementType type = MovementType.egreso}) =>
      service.save(MovementDraft(
        type: type,
        amountText: amount,
        date: DateTime.now(),
        categoryId: type == MovementType.egreso ? 1 : 7,
        paymentMethod:
            type == MovementType.egreso ? PaymentMethod.efectivo : null,
      ));

  Future<void> openDetail(WidgetTester tester, String amountText) async {
    // Se toca la parte de arriba del renglón: con texto al 200 % su centro
    // puede quedar fuera de la pantalla.
    final tile = find.ancestor(
      of: find.text(amountText),
      matching: find.byType(InkWell),
    );
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(24, 12));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del movimiento'), findsOneWidget);
  }

  /// Botón "atrás" del sistema.
  Future<void> goBack(WidgetTester tester) async {
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
  }

  Future<void> openEdit(WidgetTester tester) async {
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
  }

  Future<void> tapDelete(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Eliminar'));
    await tester.pumpAndSettle();
  }

  final confirmDelete = find.widgetWithText(FilledButton, 'Eliminar');

  testWidgets('CA-026: sin movimientos el balance muestra \$0.00',
      (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Balance de '), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
  });

  testWidgets('CA-001 / CA-007: el balance se actualiza al registrar',
      (tester) async {
    await seed('15000', type: MovementType.ingreso);
    await pumpApp(tester);
    expect(find.text(r'$15,000.00'), findsOneWidget);
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '4000');
    await choose(tester, categoryDropdown, 'Alimentos');
    await choose(tester, methodDropdown, 'Efectivo');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text(r'$11,000.00'), findsOneWidget, reason: 'CA-025');
  });

  testWidgets('CA-027: balance negativo con -\$500.00', (tester) async {
    await seed('500');
    await pumpApp(tester);
    expect(find.text(r'-$500.00'), findsOneWidget);
  });

  testWidgets('CA-016: edito el monto y lista, detalle y balance cambian',
      (tester) async {
    await seed('350');
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await openEdit(tester);
    expect(find.text('Editar egreso'), findsOneWidget);
    expect(find.text('350.00'), findsOneWidget, reason: 'datos prellenados');
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Cambios guardados.'), findsOneWidget);
    expect(find.text(r'$500.00'), findsOneWidget, reason: 'detalle');
    await goBack(tester);
    await tester.pumpAndSettle();
    expect(find.text(r'−$500.00'), findsOneWidget);
    expect(find.text(r'-$500.00'), findsOneWidget);
    expect(repo.rows.single.amountCents, 50000);
  });

  testWidgets('CA-019 / CA-035: cambio la categoría y el método de pago',
      (tester) async {
    await seed('350');
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await openEdit(tester);
    await choose(tester, categoryDropdown, 'Transporte');
    await choose(tester, methodDropdown, 'Crédito');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Transporte'), findsOneWidget);
    expect(find.text('Crédito'), findsOneWidget);
    await goBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Transporte'), findsOneWidget);
    expect(repo.rows.single.paymentMethod, 'credito');
  });

  testWidgets('CA-017: en edición se aplican las validaciones de alta',
      (tester) async {
    await seed('350');
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await openEdit(tester);
    await tester.enterText(find.byType(TextField).first, '0');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar egreso'), findsOneWidget);
    expect(find.text(ErrorMessages.invalidFields), findsOneWidget);
    expect(repo.rows.single.amountCents, 35000);
  });

  testWidgets('CA-018: si falla el guardado, mensaje claro y valor anterior',
      (tester) async {
    await seed('350');
    repo.updateError = const FileSystemException('escritura');
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await openEdit(tester);
    await tester.enterText(find.byType(TextField).first, '999');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text(ErrorMessages.saveFailed), findsOneWidget);
    expect(find.text('999'), findsOneWidget, reason: 'lo capturado sigue');
    expect(repo.rows.single.amountCents, 35000);
  });

  testWidgets('CA-020: salir o guardar sin cambios no modifica nada',
      (tester) async {
    await seed('350');
    final before = repo.rows.single.toRow();
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await openEdit(tester);
    await goBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Detalle del movimiento'), findsOneWidget);
    await openEdit(tester);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Cambios guardados.'), findsNothing);
    expect(find.text('Detalle del movimiento'), findsOneWidget);
    expect(repo.rows.single.toRow(), before);
  });

  testWidgets('CA-022: "Cancelar" cierra el diálogo y no borra',
      (tester) async {
    await seed('350');
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await tapDelete(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('¿Eliminar este movimiento?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(repo.rows, hasLength(1));
    expect(repo.deleteCalls, 0);
  });

  testWidgets('CA-021: confirmar borra y actualiza lista y balance',
      (tester) async {
    await seed('15000', type: MovementType.ingreso);
    await seed('4000');
    await pumpApp(tester);
    expect(find.text(r'$11,000.00'), findsOneWidget);
    await openDetail(tester, r'−$4,000.00');
    await tapDelete(tester);
    await tester.tap(confirmDelete);
    await tester.pumpAndSettle();
    expect(find.text('Movimiento eliminado.'), findsOneWidget);
    expect(find.text(r'−$4,000.00'), findsNothing);
    expect(find.text(r'$15,000.00'), findsOneWidget);
    expect(repo.rows, hasLength(1));
  });

  testWidgets('CA-024: "Eliminar" se deshabilita al primer toque',
      (tester) async {
    await seed('350');
    repo.deleteGate = Completer<void>();
    await pumpApp(tester);
    await openDetail(tester, r'−$350.00');
    await tapDelete(tester);
    await tester.tap(confirmDelete);
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Eliminando…'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Eliminando…'), warnIfMissed: false);
    await tester.pump();
    repo.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(repo.deleteCalls, 1);
    expect(repo.rows, isEmpty);
    expect(find.text('Aún no tienes movimientos'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
  });

  testWidgets('RNF-06: detalle y diálogo al 200 % y áreas táctiles',
      (tester) async {
    await seed('9999999.99', type: MovementType.ingreso);
    await pumpApp(tester, textScale: 2);
    await openDetail(tester, r'+$9,999,999.99');
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Eliminar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapDelete(tester);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });
}
