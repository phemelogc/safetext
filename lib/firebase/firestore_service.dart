import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> _getDeviceId() async {
    try {
      final defaultId = 'unknown_device';
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? defaultId;
      }
      return defaultId;
    } catch (e) {
      print('Error getting device ID: $e');
      return 'unknown_device';
    }
  }

  Future<void> writeFlaggedMessage({
    required String messageText,
    required String senderNumber,
    required double confidenceScore,
    required List<String> patternTags,
  }) async {
    try {
      final deviceId = await _getDeviceId();
      await _db.collection('flagged_messages').add({
        'message_text': messageText,
        'sender_number': senderNumber,
        'confidence_score': confidenceScore,
        'pattern_tags': patternTags,
        'timestamp': Timestamp.now(),
        'user_reported': false,
        'status': 'pending',
        'device_id': deviceId,
      });
    } catch (e) {
      print('Error writing flagged message: $e');
    }
  }

  Future<void> reportSuspiciousNumber(String phoneNumber) async {
    try {
      final querySnapshot = await _db
          .collection('suspicious_numbers')
          .where('phone_number', isEqualTo: phoneNumber)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final docId = querySnapshot.docs.first.id;
        await _db.collection('suspicious_numbers').doc(docId).update({
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
    } catch (e) {
      print('Error reporting suspicious number: $e');
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
    try {
      final deviceId = await _getDeviceId();
      await _db.collection('app_logs').add({
        'event_type': eventType,
        'timestamp': Timestamp.now(),
        'device_id': deviceId,
        'details': details,
      });
    } catch (e) {
      print('Error logging event: $e');
    }
  }
}
