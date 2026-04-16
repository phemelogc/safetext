import 'dart:async';
import 'package:flutter/material.dart';
import '../firebase/firebase_config.dart';
import '../firebase/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/connectivity_service.dart';
import '../services/write_queue.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool onboarded;
  const SplashScreen({super.key, required this.onboarded});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Run independent initializations in parallel to minimise startup latency.
      // Firebase, connectivity, and notifications do not depend on each other.
      await Future.wait([
        FirebaseConfig.init(),          // SDK local init + optional 6 s timeout
        ConnectivityService().init(),   // connectivity_plus with 4 s timeout
        NotificationService.init(),     // local notification channel setup
      ]);

      // Wire up the reconnect → flush listener on the already-initialised singleton.
      ConnectivityService().onStatusChange.listen((online) {
        if (online) WriteQueue().flush();
      });
      if (ConnectivityService().isOnline) WriteQueue().flush();

      // Log app open without blocking — a failed/slow write never delays startup.
      unawaited(FirestoreService().logEvent('app_opened', 'App launched'));
    } catch (e) {
      // Any init error is non-fatal: the app still loads.
      debugPrint('SplashScreen init error: $e');
    }

    _navigate();
  }

  void _navigate() {
    if (!mounted) return;
    final target = widget.onboarded
        ? const HomeScreen()
        : const OnboardingScreen();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.security, size: 72, color: Color(0xFF2196F3)),
            const SizedBox(height: 24),
            Text(
              'SafeText',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Color(0xFF2196F3)),
          ],
        ),
      ),
    );
  }
}
