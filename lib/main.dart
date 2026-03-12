import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final prefs = await SharedPreferences.getInstance();
  final bool onboarded = prefs.getBool('onboarded') ?? false;
  
  final isDark = prefs.getBool('isDark') ?? true;
  final lang = prefs.getString('lang') ?? 'en';
  
  SafeTextApp.themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  SafeTextApp.localeNotifier.value = lang;

  runApp(
    SafeTextApp(initialRoute: onboarded ? HomeScreen() : OnboardingScreen()),
  );
}

class SafeTextApp extends StatelessWidget {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
  static final ValueNotifier<String> localeNotifier = ValueNotifier('en');

  final Widget initialRoute;
  const SafeTextApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: localeNotifier,
      builder: (_, String lang, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, __) {
            return MaterialApp(
              title: 'SafeText',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                brightness: Brightness.light,
                primaryColor: const Color(0xFF2196F3),
                scaffoldBackgroundColor: const Color(0xFFF5F5F5),
                cardColor: Colors.white,
                textTheme: const TextTheme(
                  bodyMedium: TextStyle(fontFamily: 'Roboto', fontSize: 16, color: Colors.black87),
                  titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black87),
                  bodySmall: TextStyle(fontFamily: 'Roboto', fontSize: 14, color: Colors.black54),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                primaryColor: const Color(0xFF2196F3),
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardColor: const Color(0xFF1E1E1E),
                textTheme: const TextTheme(
                  bodyMedium: TextStyle(fontFamily: 'Roboto', fontSize: 16, color: Colors.white),
                  titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold, fontSize: 24, color: Colors.white),
                  bodySmall: TextStyle(fontFamily: 'Roboto', fontSize: 14, color: Color(0xFFBDBDBD)),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              themeMode: currentMode,
              home: initialRoute,
            );
          },
        );
      },
    );
  }
}
