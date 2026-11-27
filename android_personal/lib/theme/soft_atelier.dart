import 'package:flutter/material.dart';
import '../data/models.dart';

class AtelierPalette {
  const AtelierPalette({
    required this.kind,
    required this.name,
    required this.description,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
  });

  final AppThemeKind kind;
  final String name;
  final String description;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
}

const List<AtelierPalette> kAtelierPalettes = [
  AtelierPalette(
    kind: AppThemeKind.berryCream,
    name: 'Ягодный крем',
    description: 'Тёплый сливочный фон и ягодный акцент',
    brightness: Brightness.light,
    background: Color(0xFFFFFBF8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF9EFF3),
    primary: Color(0xFFA45C7A),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF7A4B5E),
    border: Color(0xFFECDCE3),
    textPrimary: Color(0xFF2B1E24),
    textMuted: Color(0xFF6F5B63),
    success: Color(0xFF2E7D5B),
    warning: Color(0xFFC57B1C),
    danger: Color(0xFFB83A4B),
  ),
  AtelierPalette(
    kind: AppThemeKind.vanillaPistachio,
    name: 'Ваниль и фисташка',
    description: 'Свежий натуральный тон и фисташковый лист',
    brightness: Brightness.light,
    background: Color(0xFFFBFDF9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF5EE),
    primary: Color(0xFF3E6F52),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF6E8B63),
    border: Color(0xFFD7E6D9),
    textPrimary: Color(0xFF1D2B22),
    textMuted: Color(0xFF566B5D),
    success: Color(0xFF2E7D5B),
    warning: Color(0xFFB97419),
    danger: Color(0xFFB83A4B),
  ),
  AtelierPalette(
    kind: AppThemeKind.porcelain,
    name: 'Фарфор',
    description: 'Светлая нейтральная палитра без акцентов цвета',
    brightness: Brightness.light,
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDF0F5),
    primary: Color(0xFF3A4B68),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF5A6D8C),
    border: Color(0xFFDCE1EA),
    textPrimary: Color(0xFF1C2230),
    textMuted: Color(0xFF5D6677),
    success: Color(0xFF277756),
    warning: Color(0xFFB87118),
    danger: Color(0xFFB43746),
  ),
  AtelierPalette(
    kind: AppThemeKind.darkChocolate,
    name: 'Тёмный шоколад',
    description: 'Вечерняя комфортная тема для работы на кухне',
    brightness: Brightness.dark,
    background: Color(0xFF171214),
    surface: Color(0xFF231B1F),
    surfaceAlt: Color(0xFF2F2329),
    primary: Color(0xFFE29DB8),
    onPrimary: Color(0xFF2B141D),
    secondary: Color(0xFFC5A88F),
    border: Color(0xFF3E3036),
    textPrimary: Color(0xFFF7EFF2),
    textMuted: Color(0xFFC2B0B7),
    success: Color(0xFF6AD0A2),
    warning: Color(0xFFF0B45A),
    danger: Color(0xFFF17D8B),
  ),
];

AtelierPalette paletteForIndex(int index) {
  if (index < 0 || index >= kAtelierPalettes.length) {
    return kAtelierPalettes.first;
  }
  return kAtelierPalettes[index];
}

ThemeData buildAtelierTheme(AtelierPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.secondary,
    onSecondary: p.onPrimary,
    error: p.danger,
    onError: Colors.white,
    surface: p.surface,
    onSurface: p.textPrimary,
    outline: p.border,
    surfaceContainerHighest: p.surfaceAlt,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    fontFamily: 'LiberationSans',
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'LiberationSans',
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: p.primary, width: 1.6),
      ),
      labelStyle: TextStyle(color: p.textMuted, fontSize: 13),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'LiberationSans',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: 'LiberationSans',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.surfaceAlt,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'LiberationSans',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: p.textPrimary,
        ),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.textPrimary,
      contentTextStyle: TextStyle(
        color: p.background,
        fontFamily: 'LiberationSans',
        fontSize: 13,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
