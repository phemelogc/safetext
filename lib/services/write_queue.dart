import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Persists failed Firestore add() calls locally and retries them when the
// app comes back online. Only simple document adds are supported.
class WriteQueue {
  static const _prefKey = 'firestore_write_queue';

  static final WriteQueue _instance = WriteQueue._internal();
  factory WriteQueue() => _instance;
  WriteQueue._internal();

  Future<void> enqueue({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefKey) ?? [];
      raw.add(jsonEncode({'collection': collection, 'data': _serialize(data)}));
      await prefs.setStringList(_prefKey, raw);
    } catch (_) {}
  }

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
          await db
              .collection(map['collection'] as String)
              .add(_deserialize(Map<String, dynamic>.from(map['data'] as Map)));
        } catch (_) {
          remaining.add(item);
        }
      }

      await prefs.setStringList(_prefKey, remaining);
    } catch (_) {}
  }

  Map<String, dynamic> _serialize(Map<String, dynamic> data) {
    return data.map((k, v) {
      if (v is Timestamp) {
        return MapEntry(k, {'__type__': 'Timestamp', 'ms': v.millisecondsSinceEpoch});
      }
      return MapEntry(k, v);
    });
  }

  Map<String, dynamic> _deserialize(Map<String, dynamic> data) {
    return data.map((k, v) {
      if (v is Map && v['__type__'] == 'Timestamp') {
        return MapEntry(k, Timestamp.fromMillisecondsSinceEpoch(v['ms'] as int));
      }
      return MapEntry(k, v);
    });
  }
}
