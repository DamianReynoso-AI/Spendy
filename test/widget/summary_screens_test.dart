// Pruebas de pantallas del incremento 5: aviso de privacidad en el primer
// inicio y resumen anual con exportación (M-01 con M-07, M-08 y M-10).
// CA-095 a CA-100, CA-104, CA-107, CA-111, CA-112, CA-141 a CA-143.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendy/app.dart';
import 'package:spendy/config/privacy_texts.dart';
import 'package:spendy/core/error_logger.dart';
import 'package:spendy/core/result.dart';
import 'package:spendy/data/repositories/settings_repository.dart';
import 'package:spendy/modules/categories/category_catalog.dart';
import 'package:spendy/modules/export/export_service.dart';
import 'package:spendy/modules/movements/movement_service.dart';
import 'package:spendy/modules/privacy/onboarding_service.dart';
import 'package:spendy/modules/summary/summary_service.dart';
import 'package:spendy/ui/screens/summary_screen.dart';

import 'movement_screens_test.dart'
    show MemoryCategoryRepository, MemoryMovementRepository;

class MemorySettings implements SettingsRepository {
  final Map<String, String> values = {};

  @override
  Future<String?> getSetting(String clave) async => values[clave];

  @override
  Future<void> setSetting(String clave, String valor) async =>
      values[clave] = valor;
}

class FakeExports implements ExportService {
  final List<ExportFormat> calls = [];
  bool fail = false;

  @override
  Future<Result<String>> export(
    AnnualSummary summary,
    ExportFormat format,
  ) async {
    calls.add(format);
    if (fail) {
      return const Failure(
        AppError(type: ErrorType.export, message: ExportMessages.failed),
      );
    }
    return Success(exportFileName(summary.year, format));
  }
}

void main() {
  late ErrorLogger logger;
  late MemoryMovementRepository repo;
  late MovementService service;
  late CategoryCatalog catalog;
  late MemorySettings settings;
  late FakeExports exports;
  final now = DateTime(2026, 11, 12, 12);

  setUp(() {
    logger = ErrorLogger(
      () async => throw const FileSystemException(errorLogFileName),
    );
    repo = MemoryMovementRepository();
    catalog = CategoryCatalog(MemoryCategoryRepository(), logger);
    service = MovementService(
      repository: repo,
      catalog: catalog,
      logger: logger,
      clock: () => now,
    );
    settings = MemorySettings();
    exports = FakeExports();
  });

  Future<void> pumpApp(WidgetTester tester, {bool onboarding = false}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SpendyApp(
        key: UniqueKey(),
        service: service,
        catalog: catalog,
        onboarding: onboarding ? OnboardingService(settings, logger) : null,
        summary: SummaryService(
          repository: repo,
          logger: logger,
          clock: () => now,
        ),
        exports: exports,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addMovement(MovementType type, String amount, DateTime date) =>
      service.save(
        MovementDraft(
          type: type,
          amountText: amount,
          date: date,
          categoryId: type == MovementType.egreso ? 1 : 7,
          paymentMethod:
              type == MovementType.egreso ? PaymentMethod.efectivo : null,
        ),
      );

  /// Desplaza la lista hasta que [text] exista y lo toca.
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.dragUntilVisible(
      find.text(text),
      find.byType(ListView).last,
      const Offset(0, -300),
    );
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> openSummary(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Resumen anual'));
    await tester.pumpAndSettle();
  }

  group('aviso de privacidad (RF-51)', () {
    testWidgets('CA-141 / CA-142: bloquea la app hasta tocar "Acepto"',
        (tester) async {
      await pumpApp(tester, onboarding: true);
      expect(find.text(PrivacyTexts.title), findsOneWidget);
      expect(find.text('Movimientos'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(PrivacyTexts.title), findsOneWidget);

      await tapText(tester, PrivacyTexts.acceptButton);
      expect(find.text('Movimientos'), findsOneWidget);
      expect(settings.values[OnboardingService.acceptedKey], 'true');
    });

    testWidgets('CA-143: aceptado, no vuelve a aparecer al abrir de nuevo',
        (tester) async {
      settings.values[OnboardingService.acceptedKey] = 'true';
      await pumpApp(tester, onboarding: true);
      expect(find.text(PrivacyTexts.title), findsNothing);
      expect(find.text('Movimientos'), findsOneWidget);
    });
  });

  group('resumen anual', () {
    testWidgets(
        'CA-095 / CA-099: año actual por defecto, totales y '
        'categorías con \$0.00', (tester) async {
      await addMovement(MovementType.ingreso, '15000', DateTime(2026, 1, 15));
      await addMovement(MovementType.egreso, '1234.56', DateTime(2026, 3, 2));
      await addMovement(MovementType.egreso, '10', DateTime(2025, 5, 5));
      await pumpApp(tester);
      await openSummary(tester);

      expect(find.text('2026'), findsOneWidget);
      expect(find.text(r'$15,000.00'), findsOneWidget);
      expect(find.text(r'$1,234.56'), findsNWidgets(2));
      expect(find.text(r'$13,765.44'), findsOneWidget);
      expect(find.text('Entretenimiento'), findsOneWidget);
      expect(find.text(r'$0.00'), findsNWidgets(5));

      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025').last);
      await tester.pumpAndSettle();
      expect(find.text(r'$10.00'), findsWidgets);
    });

    testWidgets('CA-096 / CA-098: año sin movimientos muestra aviso',
        (tester) async {
      await addMovement(MovementType.egreso, '10', DateTime(2025, 5, 5));
      await pumpApp(tester);
      await openSummary(tester);
      expect(
          find.text('No hay movimientos registrados en 2026.'), findsOneWidget);
      expect(find.text('Exportar CSV'), findsNothing);
    });

    testWidgets('CA-100 / CA-104: se recalcula al volver a la pantalla',
        (tester) async {
      await addMovement(MovementType.egreso, '100', DateTime(2026, 2, 2));
      await pumpApp(tester);
      await openSummary(tester);
      expect(find.text(r'$100.00'), findsWidgets);

      final navigator =
          Navigator.of(tester.element(find.byType(SummaryScreen)));
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await tester.pumpAndSettle();
      await addMovement(MovementType.egreso, '50', DateTime(2026, 2, 3));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text(r'$150.00'), findsWidgets);
    });

    testWidgets('CA-107 / CA-111 / CA-112: exportar y reintentar si falla',
        (tester) async {
      await addMovement(MovementType.egreso, '100', DateTime(2026, 2, 2));
      await pumpApp(tester);
      await openSummary(tester);

      await tapText(tester, 'Exportar CSV');
      expect(exports.calls, [ExportFormat.csv]);

      exports.fail = true;
      await tapText(tester, 'Exportar PDF');
      expect(find.text(ExportMessages.failed), findsOneWidget);

      exports.fail = false;
      await tapText(tester, 'Reintentar');
      expect(exports.calls, [
        ExportFormat.csv,
        ExportFormat.pdf,
        ExportFormat.pdf,
      ]);
      expect(find.text(ExportMessages.failed), findsNothing);
    });
  });
}
