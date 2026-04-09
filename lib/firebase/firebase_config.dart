import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseConfig {
  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: dotenv.env['FIREBASE_API_KEY'] ?? '',
          authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '',
          projectId: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
          storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '',
          messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
          appId: dotenv.env['FIREBASE_APP_ID'] ?? '',
        ),
      ).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Firebase init: $e');
    }
  }
}
