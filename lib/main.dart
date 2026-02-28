import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;

  runApp(SafeTextApp(onboarded: onboarded));
}

class SafeTextApp extends StatelessWidget {
  final bool onboarded;

  const SafeTextApp({super.key, required this.onboarded});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeText',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _buildDarkTheme(),
      home: onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    const scaffoldBg = Color(0xFF121212);
    const surface = Color(0xFF1E1E1E);
    const primary = Color(0xFF2196F3);
    const subtitleColor = Color(0xFFBDBDBD);

    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
    );

    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
        primary: primary,
        surface: surface,
        background: scaffoldBg,
      ),
      scaffoldBackgroundColor: scaffoldBg,
      cardColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.bold,
          fontSize: 24,
          color: Colors.white,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          color: Colors.white,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 14,
          color: subtitleColor,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(
          color: Colors.white,
          fontFamily: 'Roboto',
          fontSize: 14,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: scaffoldBg,
        selectedItemColor: primary,
        unselectedItemColor: subtitleColor,
      ),
    );
  }
}
