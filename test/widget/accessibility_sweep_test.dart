// Cierre v1.0.0 · Barrido de accesibilidad y tamaños de pantalla
// (RNF-06, RNF-35, RNF-37): recorre las pantallas principales en un
// teléfono de 5", uno de 6.1" y uno de 6.7" en vertical, con el texto del
// sistema al 200 %, y revisa que no haya desbordamientos. Con texto normal
// revisa áreas táctiles (44 x 44 pt de iOS y 48 x 48 dp de Android) y
// contraste de texto (4.5:1).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/privacy/onboarding_service.dart';
import 'package:spendy/modules/search/movement_filter.dart';
import 'package:spendy/modules/summary/summary_service.dart';

import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;
import 'summary_screens_test.dart' show FakeExports, MemorySettings;

/// Tamaños lógicos (dp) de referencia en vertical.
const Map<String, Size> phones = {
  '5.0" (360 x 640)': Size(360, 640),
  '6.1" (393 x 852)': Size(393, 852),
  '6.7" (430 x 932)': Size(430, 932),
};

void main() {
  late MemoryMovementRepository repo;
  late MovementService service;
  late CategoryCatalog catalog;
  late ErrorLogger logger;
  late MemorySettings settings;
  final now = DateTime.now();

  setUp(() async {
    logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    repo = MemoryMovementRepository();
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    service = MovementService(
      repository: repo,
      catalog: catalog,
      logger: logger,
    );
    settings = MemorySettings();
    await service.save(MovementDraft(
      type: MovementType.egreso,
      amountText: '9999999.99',
      date: now,
      categoryId: 1,
      paymentMethod: PaymentMethod.credito,
      description: 'Supermercado de la colonia Jardines del Moral',
      note: 'Despensa de la quincena con artículos de limpieza',
    ));
    await service.save(MovementDraft(
      type: MovementType.ingreso,
      amountText: '15000',
      date: now,
      categoryId: 7,
    ));
  });

  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(SpendyApp(
      key: UniqueKey(),
      service: service,
      catalog: catalog,
      onboarding: OnboardingService(settings, logger),
      summary: SummaryService(repository: repo, logger: logger),
      exports: FakeExports(),
      filter: MovementFilter(repository: repo, logger: logger),
    ));
    await tester.pumpAndSettle();
  }

  void expectNoOverflow(WidgetTester tester, String where) {
    expect(tester.takeException(), isNull, reason: where);
  }

  Future<void> acceptPrivacy(WidgetTester tester) async {
    final accept = find.text(PrivacyTexts.acceptButton);
    // El aviso completo (AUD-07) mide varias pantallas al 200 %.
    await tester.scrollUntilVisible(accept, 500,
        maxScrolls: 100, scrollable: find.byType(Scrollable).first);
    // Que quede completo en pantalla, no solo asomado en el borde.
    await tester.ensureVisible(accept);
    await tester.pumpAndSettle();
    await tester.tap(accept);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
  }

  Future<void> sweep(WidgetTester tester, String label) async {
    expectNoOverflow(tester, '$label · aviso de privacidad');
    await acceptPrivacy(tester);
    expectNoOverflow(tester, '$label · pantalla principal');

    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester, '$label · formulario');
    await back(tester);

    final amount = find.text(r'−$9,999,999.99');
    await tester.scrollUntilVisible(amount, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    // Se toca el monto, que ya quedó a la vista: con texto al 200 % el
    // renglón completo puede medir más que la lista visible.
    await tester.tap(amount);
    await tester.pumpAndSettle();
    expect(find.text('Detalle del movimiento'), findsOneWidget);
    expectNoOverflow(tester, '$label · detalle');
    await back(tester);

    await tester.tap(find.byTooltip('Resumen anual'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester, '$label · resumen anual');
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expectNoOverflow(tester, '$label · regreso a la lista');
  }

  for (final MapEntry(key: label, value: size) in phones.entries) {
    testWidgets('RNF-06 / RNF-35: texto al 200 % en $label sin desbordes',
        (tester) async {
      await pumpApp(tester, size, textScale: 2);
      await sweep(tester, label);
    });
  }

  testWidgets(
      'RNF-06: áreas táctiles y contraste en aviso, lista, formulario y resumen',
      (tester) async {
    await pumpApp(tester, phones.values.first);
    Future<void> check() async {
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    await check();
    await acceptPrivacy(tester);
    await check();
    await tester.tap(find.text('Registrar'));
    await tester.pumpAndSettle();
    await check();
    await back(tester);
    await tester.tap(find.byTooltip('Resumen anual'));
    await tester.pumpAndSettle();
    await check();
  });
}
