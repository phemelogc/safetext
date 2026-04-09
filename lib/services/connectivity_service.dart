import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> init() async {
    try {
      final results = await _connectivity
          .checkConnectivity()
          .timeout(const Duration(seconds: 4));
      _isOnline = _hasConnection(results);
      _subscription = _connectivity.onConnectivityChanged.listen((results) {
        final online = _hasConnection(results);
        if (online != _isOnline) {
          _isOnline = online;
          _controller.add(_isOnline);
        }
      });
    } catch (_) {
      _isOnline = true;
    }
  }

  bool _hasConnection(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
