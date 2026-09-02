import 'package:flutter/material.dart';

/// Available application theme modes.
enum AppThemeMode {
  system,
  light,
  dark,
  oled;

  String get displayName {
    switch (this) {
      case AppThemeMode.system:
        return 'System Default';
      case AppThemeMode.light:
        return 'Light Mode';
      case AppThemeMode.dark:
        return 'Dark Mode';
      case AppThemeMode.oled:
        return 'OLED High-Contrast (Pitch Black)';
    }
  }
}

/// Curated cyber-security seed color palettes.
class AppPalettes {
  static const Color cyberEmerald = Color(0xFF00D26A); // Default primary
  static const Color electricIndigo = Color(0xFF3D5AFE);
  static const Color cyberCyan = Color(0xFF00E5FF);
  static const Color sunsetAmber = Color(0xFFFF9100);
  static const Color neonRose = Color(0xFFFF1744);

  static const List<NamedPalette> allPalettes = [
    NamedPalette('Cyber Emerald', cyberEmerald),
    NamedPalette('Electric Indigo', electricIndigo),
    NamedPalette('Cyber Cyan', cyberCyan),
    NamedPalette('Sunset Amber', sunsetAmber),
    NamedPalette('Neon Rose', neonRose),
  ];

  static const List<Color> allSeeds = [
    cyberEmerald,
    electricIndigo,
    cyberCyan,
    sunsetAmber,
    neonRose,
  ];
}

/// Container for named palette seeds.
class NamedPalette {
  final String name;
  final Color color;

  const NamedPalette(this.name, this.color);
}

/// Comprehensive Material 3 Theme Factory for SLFT.
class AppTheme {
  /// Monospace text style for cryptographic hashes, fingerprints, and SAS codes.
  static TextStyle monospace({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double letterSpacing = 1.0,
  }) {
    return TextStyle(
      fontFamily: 'Courier',
      fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  /// Light Material 3 Theme
  static ThemeData lightTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: Colors.white,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        indicatorColor: colorScheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: colorScheme.primaryContainer,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  /// Dark Material 3 Theme
  static ThemeData darkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121417),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        color: const Color(0xFF1B1F24),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Color(0xFF16191E),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF16191E),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1F242C),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF181C21),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }

  /// OLED True Black High-Contrast Theme (#000000)
  static ThemeData oledTheme(Color seedColor) {
    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );

    final oledColorScheme = baseColorScheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF181818),
      surfaceContainerHighest: const Color(0xFF222222),
      outline: const Color(0xFF444444),
      outlineVariant: const Color(0xFF2E2E2E),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: oledColorScheme,
      scaffoldBackgroundColor: Colors.black,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2A2A2A), width: 1.2),
        ),
        color: const Color(0xFF0E0E0E),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.black,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.black,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFF333333), width: 1.2),
        ),
        backgroundColor: const Color(0xFF0A0A0A),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF444444)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: oledColorScheme.primary, width: 2),
        ),
      ),
    );
  }

  /// Resolves effective ThemeData based on AppThemeMode and seed color.
  static ThemeData getThemeData(
    AppThemeMode mode,
    Color seedColor, {
    Brightness systemBrightness = Brightness.dark,
  }) {
    switch (mode) {
      case AppThemeMode.system:
        return systemBrightness == Brightness.dark
            ? darkTheme(seedColor)
            : lightTheme(seedColor);
      case AppThemeMode.light:
        return lightTheme(seedColor);
      case AppThemeMode.dark:
        return darkTheme(seedColor);
      case AppThemeMode.oled:
        return oledTheme(seedColor);
    }
  }
}
