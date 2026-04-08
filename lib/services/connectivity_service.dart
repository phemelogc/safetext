import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Singleton that tracks network connectivity and broadcasts changes.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  /// Stream of true (online) / false (offline) events.
  Stream<bool> get onStatusChange => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _hasConnection(results);
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        final online = _hasConnection(results);
        if (online != _isOnline) {
          _isOnline = online;
          _controller.add(_isOnline);
        }
      });
    } catch (_) {
      // If connectivity_plus fails, assume online to not block the user.
      _isOnline = true;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none);
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
