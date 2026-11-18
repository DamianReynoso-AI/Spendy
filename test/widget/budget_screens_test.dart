// Pruebas de pantallas de las mejoras de v1.1: tarjetas de "Tu mes" y
// presupuestos en Inicio, edición de presupuestos y clave de Gemini en
// Ajustes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/data/models/movement.dart';
import 'package:spendy/data/repositories/budget_repository.dart';
import 'package:spendy/data/secure_store.dart';
import 'package:spendy/modules/budgets/budget_service.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/insights/insights_service.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/ocr/ocr_key_service.dart';
import 'package:spendy/modules/security/biometric_service.dart';
import 'package:spendy/modules/security/lock_controller.dart';
import 'package:spendy/modules/security/pin_service.dart';

import '../unit/pin_service_test.dart' show FakeBiometrics, fastHasher;
import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import 'security_screens_test.dart' show FakeReset;
import 'summary_screens_test.dart' show MemorySettings;

class MemoryBudgetRepository implements BudgetRepository {
  final Map<int, int> limits = {};

  @override
  Future<Map<int, int>> fetchAll() async => Map.of(limits);

  @override
  Future<void> setLimit(int categoryId, int? cents) async {
    if (cents == null) {
      limits.remove(categoryId);
    } else {
      limits[categoryId] = cents;
    }
  }
}

void main() {
  final today = DateTime.now();
  late ErrorLogger logger;
  late MemoryMovementRepository movements;
  late MemoryBudgetRepository budgetRows;
  late MemorySecureBackend backend;
  late CategoryCatalog catalog;

  setUp(() {
    logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    movements = MemoryMovementRepository();
    budgetRows = MemoryBudgetRepository();
    backend = MemorySecureBackend();
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
  });

  Movement expense(int cents) => Movement(
        type: MovementType.egreso,
        amountCents: cents,
        date: DateTime(today.year, today.month, 1),
        categoryId: 1,
        categoryName: 'Alimentos',
        paymentMethod: 'efectivo',
        createdAt: today,
        updatedAt: today,
      );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = SecureStore(backend);
    final lock = LockController(
      pin: PinService(store: store, logger: logger, hasher: fastHasher()),
      biometrics: BiometricService(
        store: store,
        logger: logger,
        authenticator: FakeBiometrics(),
      ),
      reset: FakeReset(backend, MemorySettings()),
      shield: const NoScreenShield(),
    );
    await lock.init();
    await tester.pumpWidget(SpendyApp(
      service: MovementService(
        repository: movements,
        catalog: catalog,
        logger: logger,
      ),
      catalog: catalog,
      lock: lock,
      budgets: BudgetService(
        budgets: budgetRows,
        movements: movements,
        catalog: catalog,
        logger: logger,
      ),
      insights: InsightsService(repository: movements, logger: logger),
      ocrKey: OcrKeyService(store, logger),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Inicio muestra "Tu mes" y el avance del presupuesto',
      (tester) async {
    movements.rows.add(expense(45000));
    budgetRows.limits[1] = 50000;
    await pumpApp(tester);
    expect(find.byKey(const Key('insights_card')), findsOneWidget);
    expect(find.textContaining('Donde más gastas: Alimentos'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('budgets_card')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(r'$450.00 de $500.00'), findsOneWidget);
    expect(find.text(r'Quedan $50.00'), findsOneWidget);
  });

  testWidgets('crear un presupuesto desde Inicio', (tester) async {
    await pumpApp(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('edit_budgets')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Crear'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit_budgets')));
    await tester.pumpAndSettle();
    expect(find.text('Presupuestos'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('budget_1')), '12,5');
    await tester.tap(find.byKey(const Key('save_budgets')));
    await tester.pumpAndSettle();
    expect(budgetRows.limits, isEmpty, reason: 'la coma se rechaza');

    await tester.enterText(find.byKey(const Key('budget_1')), '3000');
    await tester.tap(find.byKey(const Key('save_budgets')));
    await tester.pumpAndSettle();
    expect(budgetRows.limits, {1: 300000});
    await tester.scrollUntilVisible(find.text(r'$0.00 de $3,000.00'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(r'$0.00 de $3,000.00'), findsOneWidget);
  });

  testWidgets('guardar y quitar la clave de Gemini en Ajustes', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Configuración'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin clave'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gemini_key')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gemini_key_field')), 'mala');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text(OcrKeyMessages.invalid), findsOneWidget);

    await tester.enterText(find.byKey(const Key('gemini_key_field')),
        'AIzaSyA-1234567890abcdefghijklmnopqrWXYZ');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(backend.values[SecureStore.geminiApiKeyKey],
        'AIzaSyA-1234567890abcdefghijklmnopqrWXYZ');
    expect(find.textContaining('termina en WXYZ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('gemini_key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar clave'));
    await tester.pumpAndSettle();
    expect(backend.values.containsKey(SecureStore.geminiApiKeyKey), isFalse);
    expect(find.textContaining('Sin clave'), findsOneWidget);
  });
}
