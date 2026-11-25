import 'package:flutter/material.dart';

const millBlue = Color(0xFF3568A8);
const softCream = Color(0xFFFFF8E7);
const charcoal = Color(0xFF202731);
const runningGreen = Color(0xFF28734F);
const stoppedRed = Color(0xFFA6383D);
const pendingAmber = Color(0xFF98620B);
const unconfirmedGrey = Color(0xFF636B75);

ThemeData millTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final color =
      ColorScheme.fromSeed(
        seedColor: millBlue,
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF9FC4F7) : millBlue,
        onPrimary: dark ? const Color(0xFF111C2B) : Colors.white,
        surface: dark ? const Color(0xFF202733) : const Color(0xFFFFFDF7),
        onSurface: dark ? const Color(0xFFF5EDDA) : charcoal,
        surfaceContainerHighest: dark
            ? const Color(0xFF303B4A)
            : const Color(0xFFF3EDDE),
        outlineVariant: dark
            ? const Color(0xFF424E5F)
            : const Color(0xFFE4DAC7),
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: color,
    fontFamily: 'Mill Roboto',
  );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color.outlineVariant),
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF181E28) : softCream,
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.25,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.25,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: base.scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: color.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.outlineVariant),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: color.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: color.surface,
      border: outline,
      enabledBorder: outline,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerColor: color.outlineVariant,
  );
}
