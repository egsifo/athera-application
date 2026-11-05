import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// ATHERA colour tokens. Dark navy base, cyan primary, amber = warning,
/// red = critical. Violet is used ONLY for predicted (non-measured) data.
class AC {
  AC._();
  static const bg = Color(0xFF070B14);
  static const surface = Color(0xFF0E1522);
  static const surface2 = Color(0xFF141D2E);
  static const border = Color(0xFF223049);
  static const text = Color(0xFFE8EEF7);
  static const textDim = Color(0xFF9AA8BF);
  static const cyan = Color(0xFF22D3EE);
  static const blue = Color(0xFF7C9CCB);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
  static const sosRed = Color(0xFFDC2626);
  static const green = Color(0xFF34D399);
  static const predicted = Color(0xFFB79CFF);
}

/// Opacity helper that avoids the withOpacity/withValues API split.
Color tint(Color c, double opacity) => c.withAlpha((opacity * 255).round().clamp(0, 255));

class Sp {
  Sp._();
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32;
}

/// Large numeric readouts use tabular figures so values do not jitter.
const kTabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AC.cyan,
    onPrimary: Color(0xFF00252B),
    secondary: AC.blue,
    onSecondary: Colors.black,
    surface: AC.surface,
    onSurface: AC.text,
    error: AC.red,
    onError: Colors.black,
  );
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AC.bg,
    textTheme: base.textTheme.apply(bodyColor: AC.text, displayColor: AC.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: AC.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AC.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AC.surface,
      indicatorColor: tint(AC.cyan, 0.16),
      height: 66,
    ),
    dividerTheme: const DividerThemeData(color: AC.border, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AC.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AC.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AC.border),
      ),
    ),
  );
}
