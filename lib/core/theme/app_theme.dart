import 'package:flutter/material.dart';

enum AppThemeMode {
  light,
  dark,
  amoled,
}

class AppAccentColor {
  final String name;
  final Color color;
  final String hex;

  const AppAccentColor({
    required this.name,
    required this.color,
    required this.hex,
  });
}

class AppTheme {
  static const String fontFamily = 'Segoe UI';

  static const List<AppAccentColor> accentPresets = [
    AppAccentColor(name: 'JoyPlay Purple', color: Color(0xFF7C4DFF), hex: '#7C4DFF'),
    AppAccentColor(name: 'Electric Blue', color: Color(0xFF00B0FF), hex: '#00B0FF'),
    AppAccentColor(name: 'Emerald Green', color: Color(0xFF00C853), hex: '#00C853'),
    AppAccentColor(name: 'Sunset Orange', color: Color(0xFFFF6D00), hex: '#FF6D00'),
    AppAccentColor(name: 'Crimson Red', color: Color(0xFFE53935), hex: '#E53935'),
    AppAccentColor(name: 'Rose Pink', color: Color(0xFFEC4899), hex: '#EC4899'),
  ];

  static ThemeData getTheme({
    required AppThemeMode mode,
    required Color accentColor,
  }) {
    switch (mode) {
      case AppThemeMode.light:
        return _buildTheme(
          brightness: Brightness.light,
          primaryColor: accentColor,
          background: const Color(0xFFF7F8FA),
          surface: Colors.white,
          cardColor: const Color(0xFFFFFFFF),
          dividerColor: const Color(0xFFE2E8F0),
          textColor: const Color(0xFF1E293B),
          secondaryTextColor: const Color(0xFF64748B),
        );
      case AppThemeMode.dark:
        return _buildTheme(
          brightness: Brightness.dark,
          primaryColor: accentColor,
          background: const Color(0xFF12141A),
          surface: const Color(0xFF1B1E26),
          cardColor: const Color(0xFF1E222D),
          dividerColor: const Color(0xFF2C3240),
          textColor: const Color(0xFFF1F5F9),
          secondaryTextColor: const Color(0xFF94A3B8),
        );
      case AppThemeMode.amoled:
        return _buildTheme(
          brightness: Brightness.dark,
          primaryColor: accentColor,
          background: Colors.black,
          surface: const Color(0xFF0C0C0C),
          cardColor: const Color(0xFF121212),
          dividerColor: const Color(0xFF202020),
          textColor: Colors.white,
          secondaryTextColor: const Color(0xFFA0A0A0),
        );
    }
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primaryColor,
    required Color background,
    required Color surface,
    required Color cardColor,
    required Color dividerColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primaryColor,
      onPrimary: Colors.white,
      secondary: primaryColor,
      onSecondary: Colors.white,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      surface: surface,
      onSurface: textColor,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: cardColor,
      dividerColor: dividerColor,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryColor,
        unselectedItemColor: secondaryTextColor,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: dividerColor.withOpacity(0.5)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          color: textColor,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          color: secondaryTextColor,
        ),
      ),
    );
  }
}
