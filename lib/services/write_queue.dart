import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Queues Firestore add-document writes locally and flushes them
/// when connectivity is restored. Only simple add() operations are
/// supported (not conditional updates with FieldValue).
class WriteQueue {
  static const _prefKey = 'firestore_write_queue';

  static final WriteQueue _instance = WriteQueue._internal();
  factory WriteQueue() => _instance;
  WriteQueue._internal();

  // ── Enqueue ──────────────────────────────────────────────────────────────

  Future<void> enqueue({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      raw.add(jsonEncode({
        'collection': collection,
        'data': _serialize(data),
      }));
      await prefs.setStringList(_prefKey, raw);
    } catch (_) {}
  }

  // ── Flush ────────────────────────────────────────────────────────────────

  /// Attempt to write all queued documents. Items that still fail
  /// are left in the queue for the next retry.
  Future<void> flush() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      if (raw.isEmpty) return;

      final db = FirebaseFirestore.instance;
      final remaining = <String>[];

      for (final item in raw) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final collection = map['collection'] as String;
          final data = _deserialize(Map<String, dynamic>.from(
            map['data'] as Map,
          ));
          await db.collection(collection).add(data);
        } catch (_) {
          remaining.add(item); // keep for next attempt
        }
      }

      await prefs.setStringList(_prefKey, remaining);
    } catch (_) {}
  }

  // ── Serialisation helpers ────────────────────────────────────────────────

  Map<String, dynamic> _serialize(Map<String, dynamic> data) {
    return data.map((k, v) {
      if (v is Timestamp) {
        return MapEntry(k, {
          '__type__': 'Timestamp',
          'ms': v.millisecondsSinceEpoch,
        });
      }
      if (v is List) {
        // Lists of primitives serialize fine with JSON.
        return MapEntry(k, v);
      }
      return MapEntry(k, v);
    });
  }

  Map<String, dynamic> _deserialize(Map<String, dynamic> data) {
    return data.map((k, v) {
      if (v is Map && v['__type__'] == 'Timestamp') {
        return MapEntry(
          k,
          Timestamp.fromMillisecondsSinceEpoch(v['ms'] as int),
        );
      }
      return MapEntry(k, v);
    });
  }
}
