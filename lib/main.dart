import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase/firebase_config.dart';
import 'firebase/firestore_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/write_queue.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
    await FirebaseConfig.init();
    await FirestoreService().logEvent('app_opened', 'App launched');
  } catch (e) {
    debugPrint('Startup error: $e');
  }

  await NotificationService.init();

  final connectivity = ConnectivityService();
  await connectivity.init();
  connectivity.onStatusChange.listen((online) {
    if (online) WriteQueue().flush();
  });
  if (connectivity.isOnline) WriteQueue().flush();

  final prefs = await SharedPreferences.getInstance();
  final onboarded = prefs.getBool('onboarded') ?? false;
  final isDark = prefs.getBool('isDark') ?? true;
  final lang = prefs.getString('lang') ?? 'en';

  SafeTextApp.themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  SafeTextApp.localeNotifier.value = lang;

  runApp(SafeTextApp(
    initialRoute: onboarded ? const HomeScreen() : const OnboardingScreen(),
  ));
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
      builder: (_, lang, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, mode, _) {
            return MaterialApp(
              title: 'SafeText',
              debugShowCheckedModeBanner: false,
              theme: _lightTheme(),
              darkTheme: _darkTheme(),
              themeMode: mode,
              home: initialRoute,
            );
          },
        );
      },
    );
  }

  ThemeData _lightTheme() => ThemeData(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );

  ThemeData _darkTheme() => ThemeData(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}
