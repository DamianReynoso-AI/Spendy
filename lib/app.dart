/// M-01 · Raíz de la interfaz: tema, idioma fijo es-MX y pantalla inicial
/// (RF-54, RNF-37), con la guardia del aviso de privacidad en el primer
/// inicio (RF-51; CA-141 a CA-143).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'modules/categories/category_catalog.dart';
import 'modules/export/export_service.dart';
import 'modules/movements/movement_service.dart';
import 'modules/privacy/onboarding_service.dart';
import 'modules/receipts/camera_service.dart';
import 'modules/receipts/receipt_service.dart';
import 'modules/summary/summary_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/summary_screen.dart';

/// Idioma y región fijos: la app no cambia aunque el teléfono esté en
/// inglés (CA-152).
const Locale spendyLocale = Locale('es', 'MX');

ThemeData _theme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
      scaffoldBackgroundColor: Colors.white,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );

MaterialApp _materialApp(Widget home) => MaterialApp(
      title: 'SPENDY',
      theme: _theme(),
      locale: spendyLocale,
      supportedLocales: const [spendyLocale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorObservers: [spendyRouteObserver],
      home: home,
    );

/// App con sus servicios ya creados (los crea `main.dart`).
class SpendyApp extends StatelessWidget {
  const SpendyApp({
    super.key,
    required this.service,
    required this.catalog,
    this.receipts,
    this.camera,
    this.onboarding,
    this.summary,
    this.exports,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final ReceiptService? receipts;
  final CameraService? camera;

  /// Sin él no se muestra el aviso de primer inicio (pruebas de pantallas).
  final OnboardingService? onboarding;
  final SummaryService? summary;
  final ExportService? exports;

  Widget _home() => HomeScreen(
        service: service,
        catalog: catalog,
        receipts: receipts,
        camera: camera,
        summary: summary,
        exports: exports,
      );

  @override
  Widget build(BuildContext context) {
    final gate = onboarding;
    return _materialApp(
      gate == null ? _home() : StartGate(onboarding: gate, home: _home),
    );
  }
}

/// Guardia de la ruta inicial: mientras el aviso de privacidad no esté
/// aceptado solo se muestra [OnboardingScreen] (CA-141, CA-142); después,
/// la pantalla principal, también en las siguientes aperturas (CA-143).
class StartGate extends StatefulWidget {
  const StartGate({super.key, required this.onboarding, required this.home});

  final OnboardingService onboarding;
  final Widget Function() home;

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  bool? _accepted;

  @override
  void initState() {
    super.initState();
    widget.onboarding.isAccepted().then((accepted) {
      if (mounted) setState(() => _accepted = accepted);
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_accepted) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      true => widget.home(),
      false => OnboardingScreen(
          service: widget.onboarding,
          onAccepted: () => setState(() => _accepted = true),
        ),
    };
  }
}

/// Se muestra si la base no se pudo abrir al iniciar.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => _materialApp(
        Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Text(message, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      );
}
