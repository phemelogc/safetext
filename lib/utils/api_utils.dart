import 'dart:async';
import 'package:flutter/foundation.dart';

/// Wraps any async API call with a 10-second timeout and swallows all
/// exceptions, returning null on failure.  Use this for every startup or
/// background API call so a slow/absent network never blocks the UI.
///
/// Example:
///   final result = await safeApiCall(() => http.post(...));
///   if (result == null) { /* handle offline gracefully */ }
Future<T?> safeApiCall<T>(
  Future<T> Function() call, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await call().timeout(
      timeout,
      onTimeout: () => throw TimeoutException('API call timed out'),
    );
  } catch (e) {
    debugPrint('safeApiCall failed: $e');
    return null;
  }
}
