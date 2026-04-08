import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import '../services/write_queue.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Device ID ─────────────────────────────────────────────────────────────

  Future<String> _getDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        return (await deviceInfo.iosInfo).identifierForVendor ?? 'unknown_device';
      }
      return 'unknown_device';
    } catch (_) {
      return 'unknown_device';
    }
  }

  // ── Write: flagged message ────────────────────────────────────────────────

  Future<void> writeFlaggedMessage({
    required String messageText,
    required String senderNumber,
    required double confidenceScore,
    required List<String> patternTags,
  }) async {
    final deviceId = await _getDeviceId();
    final data = {
      'message_text': messageText,
      'sender_number': senderNumber,
      'confidence_score': confidenceScore,
      'pattern_tags': patternTags,
      'timestamp': Timestamp.now(),
      'user_reported': false,
      'status': 'pending',
      'device_id': deviceId,
    };
    try {
      await _db.collection('flagged_messages').add(data);
    } catch (_) {
      // Queue for retry when connectivity is restored.
      await WriteQueue().enqueue(collection: 'flagged_messages', data: data);
    }
  }

  // ── Write: report suspicious number ──────────────────────────────────────

  Future<void> reportSuspiciousNumber(String phoneNumber) async {
    try {
      final query = await _db
          .collection('suspicious_numbers')
          .where('phone_number', isEqualTo: phoneNumber)
          .get();

      if (query.docs.isNotEmpty) {
        await _db
            .collection('suspicious_numbers')
            .doc(query.docs.first.id)
            .update({
          'report_count': FieldValue.increment(1),
          'last_reported': Timestamp.now(),
        });
      } else {
        await _db.collection('suspicious_numbers').add({
          'phone_number': phoneNumber,
          'report_count': 1,
          'last_reported': Timestamp.now(),
          'confirmed_smishing': false,
          'added_by': 'user',
        });
      }
    } catch (_) {
      // Silently ignore — conditional logic cannot be queued reliably.
    }
  }

  // ── Read: community number lookup ─────────────────────────────────────────

  /// Returns the Firestore document if [phoneNumber] is confirmed as a
  /// smishing number by the community, or null if safe / not found / offline.
  Future<Map<String, dynamic>?> checkCommunityNumber(String phoneNumber) async {
    if (phoneNumber.isEmpty) return null;
    try {
      final query = await _db
          .collection('suspicious_numbers')
          .where('phone_number', isEqualTo: phoneNumber)
          .where('confirmed_smishing', isEqualTo: true)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.data();
      }
      return null;
    } catch (_) {
      return null; // offline or error — skip silently
    }
  }

  // ── Read: educational alerts ──────────────────────────────────────────────

  Stream<QuerySnapshot> getPublishedAlerts() {
    return _db
        .collection('educational_alerts')
        .where('published', isEqualTo: true)
        .orderBy('published_at', descending: true)
        .snapshots();
  }

  // ── Write: app log ────────────────────────────────────────────────────────

  Future<void> logEvent(String eventType, String details) async {
    final deviceId = await _getDeviceId();
    final data = {
      'event_type': eventType,
      'timestamp': Timestamp.now(),
      'device_id': deviceId,
      'details': details,
    };
    try {
      await _db.collection('app_logs').add(data);
    } catch (_) {
      await WriteQueue().enqueue(collection: 'app_logs', data: data);
    }
  }
}
