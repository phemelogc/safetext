import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _requestPermissionIfNeeded();
    _initialized = true;
  }

  static Future<void> _requestPermissionIfNeeded() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  static Future<void> showSuspiciousAlert({
    required String from,
    required String bodySnippet,
  }) async {
    if (!_initialized) await init();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safetext_suspicious',
      'Suspicious message alerts',
      channelDescription: 'Alerts when a message is flagged as highly suspicious',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id: 0,
      title: 'Suspicious message',
      body: 'From: ${from.isEmpty ? "Unknown" : from}',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: bodySnippet,
    );
  }
}
