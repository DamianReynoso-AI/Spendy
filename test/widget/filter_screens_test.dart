// Pruebas de pantallas del incremento 6: barra de filtros en la lista,
// conteo y suma, rango inválido y "Sin resultados" con "Limpiar filtros".
// CA-083 a CA-085, CA-087, CA-089, CA-092 a CA-094.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/search/movement_filter.dart';

import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;

void main() {
  late MemoryMovementRepository repo;
  late MovementService service;
  late CategoryCatalog catalog;
  late MovementFilter filter;
  final today = DateTime.now();

  setUp(() async {
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
    filter = MovementFilter(repository: repo, logger: logger);
    final date = DateTime(today.year, today.month, 1);
    for (final (type, amount, description, category) in [
      (MovementType.egreso, '45.50', 'Café Tal', 1),
      (MovementType.egreso, '350', 'Farmacia del Ahorro', 4),
      (MovementType.ingreso, '15000', null, 7),
    ]) {
      await service.save(
        MovementDraft(
          type: type,
          amountText: amount,
          date: date,
          categoryId: category,
          paymentMethod:
              type == MovementType.egreso ? PaymentMethod.efectivo : null,
          description: description,
          note: type == MovementType.ingreso ? 'Quincena' : null,
        ),
      );
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SpendyApp(service: service, catalog: catalog, filter: filter),
    );
    await tester.pumpAndSettle();
  }

  Finder searchField() =>
      find.widgetWithText(TextField, 'Buscar en descripción o nota');

  testWidgets('CA-087 / CA-092: buscar sin acentos muestra conteo y suma',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('Limpiar filtros'), findsNothing);
    await tester.enterText(searchField(), 'cafe');
    await tester.pumpAndSettle();
    expect(find.text(r'1 resultado · Suma: $45.50'), findsOneWidget);
    expect(find.text('Café Tal'), findsOneWidget);
    expect(find.text('Farmacia del Ahorro'), findsNothing);
  });

  testWidgets('CA-094: con ingresos y egresos, sumas separadas',
      (tester) async {
    await pumpApp(tester);
    await tester.enterText(searchField(), 'a');
    await tester.pumpAndSettle();
    expect(
      find.text(r'3 resultados · Ingresos: $15,000.00 · Egresos: $395.50'),
      findsOneWidget,
    );
  });

  testWidgets('CA-083: tipo y categoría se combinan', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Egreso').last);
    await tester.pumpAndSettle();
    expect(find.text(r'2 resultados · Suma: $395.50'), findsOneWidget);
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicios').last);
    await tester.pumpAndSettle();
    expect(find.text(r'1 resultado · Suma: $350.00'), findsOneWidget);
  });

  testWidgets('CA-085 / CA-089 / CA-093: sin resultados y "Limpiar filtros"',
      (tester) async {
    await pumpApp(tester);
    await tester.enterText(searchField(), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsOneWidget);
    expect(find.text(r'0 resultados · Suma: $0.00'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Limpiar filtros').last);
    await tester.pumpAndSettle();
    expect(find.text('Sin resultados'), findsNothing);
    expect(find.text('Café Tal'), findsOneWidget);
    expect(find.text('Farmacia del Ahorro'), findsOneWidget);
    expect(find.textContaining('resultado'), findsNothing);
  });

  testWidgets('CA-084: rango inválido avisa y no cambia la lista',
      (tester) async {
    await pumpApp(tester);
    Future<void> pick(String button, String day) async {
      await tester.tap(find.textContaining(button));
      await tester.pumpAndSettle();
      await tester.tap(find.text(day).last);
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
    }

    // Primero "Hasta" (día 10): los movimientos del día 1 siguen visibles.
    await pick('Hasta', '10');
    await pick('Desde', '20');
    expect(find.text(FilterMessages.invalidRange), findsOneWidget);
    expect(find.text('Café Tal'), findsOneWidget);
    expect(find.text('Farmacia del Ahorro'), findsOneWidget);
  });
}
