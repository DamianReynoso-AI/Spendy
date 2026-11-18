/// M-01 · Tema visual de SPENDY, tomado del prototipo de diseño (azul
/// marino, verde azulado para ingresos y coral para egresos) en modo claro
/// y oscuro. El modo sigue al del teléfono.
///
/// Los colores de texto cumplen contraste de 4.5:1 o más sobre su fondo
/// (RNF-06).
library;

import 'package:flutter/material.dart';

/// Colores propios de SPENDY que no están en [ColorScheme].
@immutable
class SpendyPalette extends ThemeExtension<SpendyPalette> {
  const SpendyPalette({
    required this.income,
    required this.incomeSoft,
    required this.expense,
    required this.expenseSoft,
    required this.muted,
    required this.cardShadow,
  });

  /// Ingresos: texto e íconos.
  final Color income;

  /// Fondo suave de los íconos de ingreso.
  final Color incomeSoft;

  /// Egresos: texto e íconos.
  final Color expense;

  /// Fondo suave de los íconos de egreso.
  final Color expenseSoft;

  /// Texto secundario.
  final Color muted;

  /// Sombra de las tarjetas.
  final Color cardShadow;

  /// Azul marino de la tarjeta de saldo (degradado), igual en ambos modos.
  static const List<Color> navyGradient = [
    Color(0xFF213F6E),
    Color(0xFF162B4E),
    Color(0xFF0F1F3B),
  ];

  /// Texto sobre el azul marino.
  static const Color onNavy = Color(0xFFF7F9FC);

  /// Ingreso y egreso sobre el azul marino (contraste ≥ 4.5:1).
  static const Color incomeOnNavy = Color(0xFF6ED8C6);
  static const Color expenseOnNavy = Color(0xFFFF9B8C);

  static const SpendyPalette light = SpendyPalette(
    income: Color(0xFF0A7368),
    incomeSoft: Color(0xFFDDF2EF),
    expense: Color(0xFFBF3A2B),
    expenseSoft: Color(0xFFFBE7E3),
    muted: Color(0xFF5B6680),
    cardShadow: Color(0x1F1B2B4A),
  );

  static const SpendyPalette dark = SpendyPalette(
    income: Color(0xFF5FCFBE),
    incomeSoft: Color(0xFF1C3B3B),
    expense: Color(0xFFF48D7F),
    expenseSoft: Color(0xFF45292A),
    muted: Color(0xFFA9B3C6),
    cardShadow: Color(0x66000000),
  );

  /// Paleta del tema actual (la clara si no hay ninguna).
  static SpendyPalette of(BuildContext context) =>
      Theme.of(context).extension<SpendyPalette>() ?? light;

  @override
  SpendyPalette copyWith() => this;

  @override
  SpendyPalette lerp(SpendyPalette? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Colores de las categorías en la gráfica de dona (se repiten si hay más).
const List<Color> categoryChartColors = [
  Color(0xFFE8833A),
  Color(0xFF3F7FD9),
  Color(0xFFE2B53A),
  Color(0xFFD9468A),
  Color(0xFFD6493C),
  Color(0xFF2E9DB8),
  Color(0xFF9156C9),
  Color(0xFF7B8599),
  Color(0xFF169C8C),
  Color(0xFF3FAE6A),
];

class _Base {
  const _Base({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.accent,
    required this.border,
    required this.error,
    required this.palette,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color accent;
  final Color border;
  final Color error;
  final SpendyPalette palette;
}

const _Base _lightBase = _Base(
  brightness: Brightness.light,
  primary: Color(0xFF15294D),
  onPrimary: Color(0xFFF7F9FC),
  background: Color(0xFFF4F6FA),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF172033),
  accent: Color(0xFFE4EAF4),
  border: Color(0xFFE1E6EE),
  error: Color(0xFFBF3A2B),
  palette: SpendyPalette.light,
);

const _Base _darkBase = _Base(
  brightness: Brightness.dark,
  primary: Color(0xFF8DB2EE),
  onPrimary: Color(0xFF0F1A2C),
  background: Color(0xFF111927),
  surface: Color(0xFF1A2434),
  onSurface: Color(0xFFEEF1F6),
  accent: Color(0xFF263349),
  border: Color(0xFF2C384D),
  error: Color(0xFFF48D7F),
  palette: SpendyPalette.dark,
);

/// Temas claro y oscuro de la app.
class SpendyTheme {
  SpendyTheme._();

  static ThemeData light() => _build(_lightBase);
  static ThemeData dark() => _build(_darkBase);

  static AppBarTheme _appBar(_Base b) => AppBarTheme(
        backgroundColor: b.background,
        foregroundColor: b.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: b.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      );

  static CardThemeData _card(_Base b) => CardThemeData(
        color: b.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: b.palette.cardShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      );

  static ThemeData _build(_Base b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF15294D),
      brightness: b.brightness,
    ).copyWith(
      primary: b.primary,
      onPrimary: b.onPrimary,
      secondary: b.palette.income,
      surface: b.surface,
      onSurface: b.onSurface,
      onSurfaceVariant: b.palette.muted,
      surfaceContainerHighest: b.accent,
      secondaryContainer: b.accent,
      onSecondaryContainer: b.onSurface,
      outlineVariant: b.border,
      error: b.error,
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: b.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerColor: b.border,
      extensions: [b.palette],
      appBarTheme: _appBar(b),
      cardTheme: _card(b),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: b.primary,
        foregroundColor: b.onPrimary,
        shape: const StadiumBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: shape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: shape),
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
