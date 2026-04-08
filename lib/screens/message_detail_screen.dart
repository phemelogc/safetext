import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../utils/translations.dart';
import '../main.dart';
import '../firebase/firestore_service.dart';
import '../services/offline_classifier.dart';
import '../services/connectivity_service.dart';

class MessageDetailScreen extends StatefulWidget {
  final SmsMessage message;
  const MessageDetailScreen({super.key, required this.message});

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen>
    with SingleTickerProviderStateMixin {
  String _prediction = '';
  bool _isLoading = true;
  double? _confidence;
  bool _flagged = false;
  List<String> _tags = [];
  String _loadingMessage = '';
  bool _isOffline = false;
  Map<String, dynamic>? _communityHit; // non-null if confirmed scammer

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    _getPrediction();

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        setState(() {
          _loadingMessage = Translations.get(
              'waking_server', SafeTextApp.localeNotifier.value);
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Classification ────────────────────────────────────────────────────────

  Future<void> _getPrediction() async {
    final lang = SafeTextApp.localeNotifier.value;
    final messageBody = widget.message.body ?? '';

    if (messageBody.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _prediction = Translations.get('error', lang);
          _isLoading = false;
        });
        _animController.forward();
      }
      return;
    }

    // Community number lookup (silent, parallel to classification).
    final senderAddr = widget.message.address ?? '';
    final communityFuture =
        FirestoreService().checkCommunityNumber(senderAddr);

    // Classify — try online first, fall back to offline.
    bool flagged = false;
    double confidence = 0.0;
    List<String> tags = [];
    String explanation = '';
    bool usedOffline = false;

    final isOnline = ConnectivityService().isOnline;

    if (isOnline) {
      try {
        final response = await http
            .post(
              Uri.parse(predictUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'message': messageBody}),
            )
            .timeout(
              const Duration(seconds: 60),
              onTimeout: () =>
                  http.Response(jsonEncode({'error': 'timeout'}), 408),
            );

        if (response.statusCode == 200) {
          final data =
              jsonDecode(response.body) as Map<String, dynamic>;
          confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
          flagged = data['flagged'] as bool? ?? false;
          tags = List<String>.from(data['tags'] as List? ?? []);
          explanation = data['explanation'] as String? ?? '';

          try {
            await FirestoreService().logEvent(
                'message_scanned', 'Manual scan from detail screen');
          } catch (_) {}

          if (confidence >= 0.85) {
            try {
              await FirestoreService().writeFlaggedMessage(
                messageText: messageBody,
                senderNumber: senderAddr,
                confidenceScore: confidence,
                patternTags: tags,
              );
            } catch (_) {}
          }
        } else if (response.statusCode == 408) {
          // Timeout — fall back to offline.
          throw Exception('timeout');
        } else {
          throw Exception('non-200');
        }
      } catch (_) {
        usedOffline = true;
        final result = OfflineClassifier.classify(messageBody);
        flagged = result['flagged'] as bool;
        confidence = (result['confidence'] as num).toDouble();
        tags = List<String>.from(result['tags'] as List);
        explanation = result['explanation'] as String;
      }
    } else {
      usedOffline = true;
      final result = OfflineClassifier.classify(messageBody);
      flagged = result['flagged'] as bool;
      confidence = (result['confidence'] as num).toDouble();
      tags = List<String>.from(result['tags'] as List);
      explanation = result['explanation'] as String;
    }

    // Merge any locally-detected tags not already present.
    _mergeLocalTags(messageBody, tags);

    // Await community lookup result.
    Map<String, dynamic>? communityHit;
    try {
      communityHit = await communityFuture;
    } catch (_) {}

    // Community confirmed scammer overrides ML score.
    if (communityHit != null) {
      flagged = true;
      if (confidence < 0.95) confidence = 0.95;
    }

    if (mounted) {
      setState(() {
        _flagged = flagged;
        _confidence = confidence;
        _tags = tags;
        _prediction = explanation;
        _isOffline = usedOffline;
        _communityHit = communityHit;
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  /// Detect URL / link patterns from raw message text and add tags if missing.
  void _mergeLocalTags(String body, List<String> tags) {
    final lower = body.toLowerCase();
    final urlRegex = RegExp(r'https?://\S+', caseSensitive: false);
    if ((urlRegex.hasMatch(body) ||
            lower.contains('bit.ly') ||
            lower.contains('tinyurl')) &&
        !tags.contains('phishing_link')) {
      tags.add('phishing_link');
    }
  }

  // ── Feedback ──────────────────────────────────────────────────────────────

  Future<void> _sendFeedback(bool isReport) async {
    final lang = SafeTextApp.localeNotifier.value;
    try {
      if (isReport) {
        try {
          await FirestoreService().logEvent(
              'user_report', 'User reported suspicious message');
        } catch (_) {}
        try {
          await FirestoreService()
              .reportSuspiciousNumber(widget.message.address ?? '');
        } catch (_) {}
      }

      try {
        await http.post(
          Uri.parse(feedbackUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': widget.message.body,
            'label': isReport ? 'report' : 'legit',
            'address': widget.message.address,
          }),
        );
      } catch (_) {} // Offline — feedback will be lost, not critical.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(Translations.get('feedback_sent', lang)),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        if (isReport) {
          await _blockContact();
        } else {
          Navigator.pop(context, false);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(Translations.get('error', lang))));
      }
    }
  }

  Future<void> _blockContact() async {
    final addr = widget.message.address;
    if (addr == null || addr.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    if (!blockList.contains(addr)) {
      blockList.add(addr);
      await prefs.setStringList('blockList', blockList);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$addr blocked')));
      Navigator.pop(context, true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lang = SafeTextApp.localeNotifier.value;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.message.address ?? 'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Community confirmed scammer banner
                    if (_communityHit != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.group, color: Colors.white),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '⚠️ This number has been confirmed as a scammer by the SafeText community',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Offline mode indicator
                    if (_isOffline && !_isLoading) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Offline mode — keyword filter used',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Message body card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.message.body ?? '',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 18, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Loading or result
                    if (_isLoading)
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _loadingMessage.isEmpty
                                  ? Translations.get('analyzing', lang)
                                  : _loadingMessage,
                              style: const TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildResultCard(theme, lang),
                      ),
                  ],
                ),
              ),
            ),

            // Action buttons
            if (!_isLoading)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _sendFeedback(false),
                          icon: const Icon(Icons.verified_user),
                          label: Text(Translations.get('ignore', lang)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _sendFeedback(true),
                          icon: const Icon(Icons.report_problem),
                          label: Text(Translations.get('report', lang)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(ThemeData theme, String lang) {
    final pct = _confidence != null
        ? (_confidence! * 100).round()
        : 0;
    final barColor = pct >= 85
        ? Colors.redAccent
        : pct >= 50
            ? Colors.orange
            : Colors.green;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _flagged
            ? Colors.red.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _flagged
              ? Colors.redAccent.withOpacity(0.5)
              : Colors.green.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon + label
          Row(
            children: [
              Icon(
                _flagged
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: _flagged ? Colors.redAccent : Colors.green,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${Translations.get('suspicion', lang)}: $pct%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _flagged ? Colors.redAccent : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Confidence progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _confidence ?? 0.0,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 16),

          // Explanation
          Text(
            _prediction,
            style: TextStyle(
              fontSize: 15,
              color: theme.textTheme.bodyMedium?.color,
              height: 1.4,
            ),
          ),

          // Pattern tag chips
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _tags
                  .map((tag) => _buildTagChip(tag))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    final info = _tagInfo(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 13, color: info.color),
          const SizedBox(width: 5),
          Text(
            info.label,
            style: TextStyle(
                fontSize: 12,
                color: info.color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  _TagInfo _tagInfo(String tag) {
    switch (tag) {
      case 'urgency':
        return _TagInfo('Urgent Language', Colors.orange, Icons.alarm);
      case 'phishing_link':
        return _TagInfo('Suspicious Link', Colors.red, Icons.link_off);
      case 'prize_bait':
        return _TagInfo('Prize Bait', Colors.amber, Icons.card_giftcard);
      case 'credential_harvest':
        return _TagInfo(
            'Credential Request', Colors.deepOrange, Icons.lock_open);
      case 'impersonation':
        return _TagInfo('Impersonation', Colors.purple, Icons.person_off);
      case 'setswana_bait':
        return _TagInfo('Setswana Bait', Colors.teal, Icons.translate);
      case 'offline_filter':
        return _TagInfo('Offline Filter', Colors.blueGrey, Icons.wifi_off);
      case 'fake_job':
        return _TagInfo('Fake Job', Colors.indigo, Icons.work_off);
      case 'fake_investment':
        return _TagInfo(
            'Fake Investment', Colors.brown, Icons.trending_down);
      default:
        return _TagInfo(tag, Colors.grey, Icons.label_outline);
    }
  }
}

class _TagInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _TagInfo(this.label, this.color, this.icon);
}
