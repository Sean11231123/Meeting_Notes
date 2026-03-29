import 'package:flutter/material.dart';

class AppTheme {
  // 暖灰調色盤
  static const _warmWhite = Color(0xFFF5F5F0);
  static const _warmLightGrey = Color(0xFFEAEAE5);
  static const _warmMidGrey = Color(0xFF9E9E9A);
  static const _warmDarkGrey = Color(0xFF2C2C2A);
  static const _warmDeepGrey = Color(0xFF1A1A18);
  static const _warmBlack = Color(0xFF111110);
  static const _accentLight = Color(0xFF3D3D3A);
  static const _accentDark = Color(0xFFD4D4CF);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _warmWhite,
    colorScheme: const ColorScheme.light(
      primary: _accentLight,
      onPrimary: _warmWhite,
      secondary: _warmMidGrey,
      surface: _warmWhite,
      onSurface: _warmDarkGrey,
      outline: _warmMidGrey,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _warmWhite,
      foregroundColor: _warmDarkGrey,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: _warmDarkGrey,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: _warmDarkGrey),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _accentLight,
        foregroundColor: _warmWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _warmLightGrey),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _warmLightGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _warmLightGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentLight, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: _warmLightGrey, thickness: 1),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: _warmDarkGrey),
      bodyMedium: TextStyle(color: _warmDarkGrey),
      bodySmall: TextStyle(color: _warmMidGrey),
      titleLarge: TextStyle(color: _warmDarkGrey, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: _warmDarkGrey, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _warmDarkGrey,
      contentTextStyle: TextStyle(color: _warmWhite),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _warmBlack,
    colorScheme: const ColorScheme.dark(
      primary: _accentDark,
      onPrimary: _warmBlack,
      secondary: _warmMidGrey,
      surface: _warmDeepGrey,
      onSurface: _accentDark,
      outline: Color(0xFF3A3A38),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _warmBlack,
      foregroundColor: _accentDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: _accentDark,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: _accentDark),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _accentDark,
        foregroundColor: _warmBlack,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    cardTheme: CardThemeData(
      color: _warmDeepGrey,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF3A3A38)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _warmDeepGrey,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A38)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3A3A38)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accentDark, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF3A3A38),
      thickness: 1,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: _accentDark),
      bodyMedium: TextStyle(color: _accentDark),
      bodySmall: TextStyle(color: _warmMidGrey),
      titleLarge: TextStyle(color: _accentDark, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: _accentDark, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: _accentDark,
      contentTextStyle: TextStyle(color: _warmBlack),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
  );
}
