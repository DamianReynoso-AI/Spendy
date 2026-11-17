/// M-01 · Raíz de la interfaz: tema, idioma fijo es-MX y pantalla inicial
/// (RF-54, RNF-37), con la guardia del aviso de privacidad en el primer
/// inicio (RF-51; CA-141 a CA-143) y el bloqueo con PIN al abrir, al volver
/// del segundo plano y en el selector de recientes (RF-46, RF-50; RNF-19;
/// CA-119 a CA-123, CA-140).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'modules/categories/category_catalog.dart';
import 'modules/export/export_service.dart';
import 'modules/movements/movement_service.dart';
import 'modules/privacy/onboarding_service.dart';
import 'modules/receipts/camera_service.dart';
import 'modules/receipts/receipt_service.dart';
import 'modules/search/movement_filter.dart';
import 'modules/security/lock_controller.dart';
import 'modules/summary/summary_service.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/pin_screen.dart';
import 'ui/screens/shell_screen.dart';
import 'ui/screens/summary_screen.dart';
import 'ui/theme/spendy_theme.dart';

/// Idioma y región fijos: la app no cambia aunque el teléfono esté en
/// inglés (CA-152).
const Locale spendyLocale = Locale('es', 'MX');

MaterialApp _materialApp(
  Widget home, {
  Key? key,
  TransitionBuilder? builder,
}) =>
    MaterialApp(
      key: key,
      builder: builder,
      title: 'SPENDY',
      theme: SpendyTheme.light(),
      darkTheme: SpendyTheme.dark(),
      themeMode: ThemeMode.system,
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
    this.filter,
    this.lock,
  });

  final MovementService service;
  final CategoryCatalog catalog;
  final ReceiptService? receipts;
  final CameraService? camera;

  /// Sin él no se muestra el aviso de primer inicio (pruebas de pantallas).
  final OnboardingService? onboarding;
  final SummaryService? summary;
  final ExportService? exports;
  final MovementFilter? filter;

  /// Protección con PIN (incremento 7). Sin ella no hay bloqueo.
  final LockController? lock;

  Widget _home() => SpendyShell(
        service: service,
        catalog: catalog,
        receipts: receipts,
        camera: camera,
        summary: summary,
        exports: exports,
        filter: filter,
        lock: lock,
      );

  @override
  Widget build(BuildContext context) {
    final gate = onboarding;
    final start =
        gate == null ? _home() : StartGate(onboarding: gate, home: _home);
    final lock = this.lock;
    if (lock == null) return _materialApp(start);
    // Tras un restablecimiento cambia la generación y se reconstruye toda
    // la app, que vuelve a pedir el aviso de privacidad (CA-140).
    return LockScope(
      controller: lock,
      builder: (generation) => _materialApp(
        start,
        key: ValueKey(generation),
        builder: (context, child) =>
            LockGate(controller: lock, child: child ?? const SizedBox()),
      ),
    );
  }
}

/// Escucha el ciclo de vida de la app para el bloqueo (CA-121 a CA-123) y
/// bloquea el botón "atrás" mientras se pide el PIN, para no cerrar
/// pantallas ocultas debajo. Va por encima de [MaterialApp] para recibir
/// "atrás" antes que su navegador.
class LockScope extends StatefulWidget {
  const LockScope({super.key, required this.controller, required this.builder});

  final LockController controller;
  final Widget Function(int generation) builder;

  @override
  State<LockScope> createState() => _LockScopeState();
}

class _LockScopeState extends State<LockScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.controller.handleLifecycle(state);

  @override
  Future<bool> didPopRoute() async => widget.controller.locked;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (_, __) => widget.builder(widget.controller.generation),
      );
}

/// Muestra la pantalla del PIN en lugar de la app mientras está bloqueada
/// (CA-119, CA-120) y una cubierta lisa cuando la app no está en primer
/// plano (RNF-19, CA-123). En el arranque en frío la app no se construye
/// hasta desbloquear, así que no se lee ningún dato antes.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.controller, required this.child});

  final LockController controller;
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> {
  bool _appBuilt = false;

  @override
  Widget build(BuildContext context) {
    final lock = widget.controller;
    if (!lock.ready) return const _PlainCover();
    if (!lock.locked) _appBuilt = true;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_appBuilt)
          Offstage(
            offstage: lock.locked,
            child: TickerMode(enabled: !lock.locked, child: widget.child),
          ),
        if (lock.locked) _LockNavigator(controller: lock),
        if (lock.obscured) const _PlainCover(),
      ],
    );
  }
}

/// Navegador propio de la pantalla de PIN, para sus diálogos de
/// confirmación del restablecimiento.
class _LockNavigator extends StatelessWidget {
  const _LockNavigator({required this.controller});

  final LockController controller;

  @override
  Widget build(BuildContext context) => HeroControllerScope.none(
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => PinUnlockScreen(controller: controller),
          ),
        ),
      );
}

/// Fondo liso sin datos (cubierta de recientes y espera inicial).
class _PlainCover extends StatelessWidget {
  const _PlainCover();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        key: Key('privacy_cover'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: SpendyPalette.navyGradient,
          ),
        ),
        child: Center(
          child: Icon(Icons.lock_outline, size: 56, color: SpendyPalette.onNavy),
        ),
      );
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
