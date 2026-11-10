/// M-01 · Raíz de la interfaz: tema, idioma fijo es-MX y pantalla inicial
/// (RF-54, RNF-37).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'modules/categories/category_catalog.dart';
import 'modules/movements/movement_service.dart';
import 'ui/screens/movement_list_screen.dart';

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
      home: home,
    );

/// App con sus servicios ya creados (los crea `main.dart`).
class SpendyApp extends StatelessWidget {
  const SpendyApp({super.key, required this.service, required this.catalog});

  final MovementService service;
  final CategoryCatalog catalog;

  @override
  Widget build(BuildContext context) =>
      _materialApp(MovementListScreen(service: service, catalog: catalog));
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
