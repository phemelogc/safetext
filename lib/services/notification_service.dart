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

  /// Shows a smishing alert notification.
  /// Only call this when confidence >= 0.85.
  static Future<void> showSuspiciousAlert({
    required String from,
    required String bodySnippet,
  }) async {
    if (!_initialized) await init();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'safetext_suspicious',
      'Smishing Alert',
      channelDescription:
          'Alerts when an incoming message is flagged as a likely scam',
      importance: Importance.max,
      priority: Priority.high,
    );
    await _plugin.show(
      id: 0,
      title: '⚠️ Smishing Alert Detected',
      body:
          'A message from ${from.isEmpty ? "Unknown" : from} has been flagged as a likely scam. Tap to review.',
      notificationDetails: const NotificationDetails(android: androidDetails),
      payload: bodySnippet,
    );
  }
}
