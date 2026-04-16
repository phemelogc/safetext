import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Wraps [child] and prepends a dismissible offline banner whenever the device
/// has no network connection.  The banner auto-hides when connectivity returns.
class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late bool _isOnline;
  bool _dismissed = false;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _isOnline = ConnectivityService().isOnline;
    _sub = ConnectivityService().onStatusChange.listen((online) {
      if (mounted) {
        setState(() {
          _isOnline = online;
          // Reset dismiss flag so the banner re-appears if connection drops again.
          if (!online) _dismissed = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showBanner = !_isOnline && !_dismissed;
    return Column(
      children: [
        if (showBanner)
          Material(
            color: Colors.orange.shade800,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Offline — using local keyword filter',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _dismissed = true),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
