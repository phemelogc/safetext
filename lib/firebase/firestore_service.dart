import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import '../services/write_queue.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> _getDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) return (await info.androidInfo).id;
      if (Platform.isIOS) return (await info.iosInfo).identifierForVendor ?? 'unknown';
      return 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> writeFlaggedMessage({
    required String messageText,
    required String senderNumber,
    required double confidenceScore,
    required List<String> patternTags,
  }) async {
    final data = {
      'message_text': messageText,
      'sender_number': senderNumber,
      'confidence_score': confidenceScore,
      'pattern_tags': patternTags,
      'timestamp': Timestamp.now(),
      'user_reported': false,
      'status': 'pending',
      'device_id': await _getDeviceId(),
    };
    try {
      await _db.collection('flagged_messages').add(data);
    } catch (_) {
      await WriteQueue().enqueue(collection: 'flagged_messages', data: data);
    }
  }

  Future<void> reportSuspiciousNumber(String phoneNumber) async {
    try {
      final query = await _db
          .collection('suspicious_numbers')
          .where('phone_number', isEqualTo: phoneNumber)
          .get();

      if (query.docs.isNotEmpty) {
        await _db.collection('suspicious_numbers').doc(query.docs.first.id).update({
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
    } catch (_) {}
  }

  // Returns the Firestore record if this number is community-confirmed as a
  // scammer, or null if clean / not found / offline.
  Future<Map<String, dynamic>?> checkCommunityNumber(String phoneNumber) async {
    if (phoneNumber.isEmpty) return null;
    try {
      final query = await _db
          .collection('suspicious_numbers')
          .where('phone_number', isEqualTo: phoneNumber)
          .where('confirmed_smishing', isEqualTo: true)
          .limit(1)
          .get();
      return query.docs.isNotEmpty ? query.docs.first.data() : null;
    } catch (_) {
      return null;
    }
  }

  Stream<QuerySnapshot> getPublishedAlerts() {
    return _db
        .collection('educational_alerts')
        .where('published', isEqualTo: true)
        .orderBy('published_at', descending: true)
        .snapshots();
  }

  Future<void> logEvent(String eventType, String details) async {
    final data = {
      'event_type': eventType,
      'timestamp': Timestamp.now(),
      'device_id': await _getDeviceId(),
      'details': details,
    };
    try {
      await _db.collection('app_logs').add(data);
    } catch (_) {
      await WriteQueue().enqueue(collection: 'app_logs', data: data);
    }
  }
}
