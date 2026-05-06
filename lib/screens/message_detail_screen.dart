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
  
  bool _flagged = false;
  List<String> _tags = [];
  String _loadingMessage = '';
  bool _isOffline = false;
  Map<String, dynamic>? _communityHit;

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
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted && _isLoading) {
        setState(() {
          _loadingMessage = Translations.get(
            'waking_server',
            SafeTextApp.localeNotifier.value,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns "Today · 10:42 AM", "Yesterday · 3:15 PM", or "12 Apr · 9:00 AM"
  String _formatMessageTime() {
    final raw = widget.message.date;
    if (raw == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(raw);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);

    String dayLabel;
    if (msgDay == today) {
      dayLabel = 'Today';
    } else if (msgDay == today.subtract(const Duration(days: 1))) {
      dayLabel = 'Yesterday';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      dayLabel = '${dt.day} ${months[dt.month - 1]}';
    }

    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$dayLabel · $hour:$minute $period';
  }

  /// Two-character avatar label from a phone number or sender name.
  String _avatarLabel(String sender) {
    if (sender.isEmpty) return '??';
    final digits = sender.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 2) return digits.substring(digits.length - 2);
    return sender.substring(0, sender.length.clamp(0, 2)).toUpperCase();
  }

  // ── Network / prediction ───────────────────────────────────────────────────

  Future<void> _getPrediction() async {
    final lang = SafeTextApp.localeNotifier.value;
    final body = widget.message.body ?? '';

    if (body.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _prediction = Translations.get('error', lang);
          _isLoading = false;
        });
        _animController.forward();
      }
      return;
    }

    final sender = widget.message.address ?? '';
    final communityFuture = FirestoreService().checkCommunityNumber(sender);

    bool flagged = false;
    double confidence = 0.0;
    List<String> tags = [];
    String explanation = '';
    bool usedOffline = false;

    if (ConnectivityService().isOnline) {
      try {
        final response = await http
            .post(
              Uri.parse(predictUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'message': body}),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
          flagged = data['flagged'] as bool? ?? false;
          tags = List<String>.from(data['tags'] as List? ?? []);
          explanation = data['explanation'] as String? ?? '';

          try {
            await FirestoreService().logEvent(
              'message_scanned',
              'Detail screen scan',
            );
          } catch (_) {}

          if (confidence >= 0.85) {
            try {
              await FirestoreService().writeFlaggedMessage(
                messageText: body,
                senderNumber: sender,
                confidenceScore: confidence,
                patternTags: tags,
              );
            } catch (_) {}
          }
        } else {
          throw Exception('non-200 (${response.statusCode})');
        }
      } catch (_) {
        usedOffline = true;
        final result = OfflineClassifier.classify(body);
        flagged = result['flagged'] as bool;
        confidence = (result['confidence'] as num).toDouble();
        tags = List<String>.from(result['tags'] as List);
        explanation = result['explanation'] as String;
      }
    } else {
      usedOffline = true;
      final result = OfflineClassifier.classify(body);
      flagged = result['flagged'] as bool;
      confidence = (result['confidence'] as num).toDouble();
      tags = List<String>.from(result['tags'] as List);
      explanation = result['explanation'] as String;
    }

    // Local URL tag injection
    final lower = body.toLowerCase();
    final urlRegex = RegExp(r'https?://\S+', caseSensitive: false);
    if ((urlRegex.hasMatch(body) ||
            lower.contains('bit.ly') ||
            lower.contains('tinyurl')) &&
        !tags.contains('phishing_link')) {
      tags.add('phishing_link');
    }

    Map<String, dynamic>? communityHit;
    try {
      communityHit = await communityFuture;
    } catch (_) {}

    if (communityHit != null) {
      flagged = true;
      if (confidence < 0.95) confidence = 0.95;
    }

    if (mounted) {
      setState(() {
        _flagged = flagged;
        
        _tags = tags;
        _prediction = explanation;
        _isOffline = usedOffline;
        _communityHit = communityHit;
        _isLoading = false;
      });
      _animController.forward();
    }
  }

  // ── Feedback / block 

  Future<void> _sendFeedback(bool isReport) async {
    final lang = SafeTextApp.localeNotifier.value;
    try {
      if (isReport) {
        try {
          await FirestoreService().logEvent(
            'user_report',
            'User reported message',
          );
        } catch (_) {}
        try {
          await FirestoreService().reportSuspiciousNumber(
            widget.message.address ?? '',
          );
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
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.get('feedback_sent', lang)),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        if (isReport) {
          await _blockContact();
        } else {
          Navigator.pop(context, false);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.get('error', lang))),
        );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$addr blocked')));
      Navigator.pop(context, true);
    }
  }

  // Report & block confirmation dialog 

  void _confirmReport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Report & block sender?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'This will report the message to SafeText and block '
                '${widget.message.address ?? "this number"} from contacting you.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _sendFeedback(true);
                      },
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Report & block'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  //  Build 

  @override
  Widget build(BuildContext context) {
    final lang = SafeTextApp.localeNotifier.value;
    final theme = Theme.of(context);
    final sender = widget.message.address ?? 'Unknown';
    final timeLabel = _formatMessageTime();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        // ── Improved appbar: avatar + sender name + timestamp subtitle ──
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            // Avatar circle
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Text(
                  _avatarLabel(sender),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sender,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (timeLabel.isNotEmpty)
                  Text(
                    timeLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Community scammer banner ───────────────────────────
                    if (_communityHit != null) ...[
                      _CommunityBanner(
                        reportCount:
                            (_communityHit!['reportCount'] as int?) ?? 0,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Offline mode badge ─────────────────────────────────
                    if (_isOffline && !_isLoading) ...[
                      _OfflineBadge(),
                      const SizedBox(height: 12),
                    ],

                    // ── Section label: MESSAGE ─────────────────────────────
                    _SectionLabel('Message'),
                    const SizedBox(height: 8),

                    // ── SMS chat bubble ────────────────────────────────────
                    _SmsBubble(
                      body: widget.message.body ?? '',
                      timeLabel: timeLabel,
                      theme: theme,
                    ),

                    const SizedBox(height: 24),

                    // ── Loading / result ───────────────────────────────────
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionLabel('Analysis'),
                            const SizedBox(height: 8),
                            _buildResultCard(theme, lang),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Bottom action bar ────────────────────────────────────────
            if (!_isLoading)
              FadeTransition(
                opacity: _fadeAnimation,
                child: _ActionBar(
                  onSafe: () => _sendFeedback(false),
                  onReport: _confirmReport,
                  lang: lang,
                ),
              ),
          ],
        ),
      ),
    );
  }

  //  Results card 

  Widget _buildResultCard(ThemeData theme, String lang) {
    final isFlagged = _flagged;
    final statusLabel = isFlagged ? 'Suspicious message' : 'Message looks safe';
    final statusColor = isFlagged ? Colors.redAccent : Colors.green;
    final statusIcon = isFlagged
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    final bgColor = isFlagged
        ? Colors.red.withValues(alpha: 0.08)
        : Colors.green.withValues(alpha: 0.08);
    final borderColor = isFlagged
        ? Colors.redAccent.withValues(alpha: 0.4)
        : Colors.green.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor.withValues(alpha: 0.15),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Explanation text
          Text(
            _prediction,
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),

          // Tags
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _tags.map(_buildTagChip).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tag chip ───────────────────────────────────────────────────────────────

  Widget _buildTagChip(String tag) {
    final info = _tagInfo(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.color.withValues(alpha: 0.5)),
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
              fontWeight: FontWeight.w600,
            ),
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
          'Credential Request',
          Colors.deepOrange,
          Icons.lock_open,
        );
      case 'impersonation':
        return _TagInfo('Impersonation', Colors.purple, Icons.person_off);
      case 'setswana_bait':
        return _TagInfo('Setswana Bait', Colors.teal, Icons.translate);
      case 'offline_filter':
        return _TagInfo('Offline Filter', Colors.blueGrey, Icons.wifi_off);
      case 'fake_job':
        return _TagInfo('Fake Job', Colors.indigo, Icons.work_off);
      case 'fake_investment':
        return _TagInfo('Fake Investment', Colors.brown, Icons.trending_down);
      default:
        return _TagInfo(tag, Colors.grey, Icons.label_outline);
    }
  }
}


/// Small uppercase section label e.g. "MESSAGE", "ANALYSIS"
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: Colors.grey.shade500,
      ),
    );
  }
}

/// Chat-bubble styled SMS display
class _SmsBubble extends StatelessWidget {
  final String body;
  final String timeLabel;
  final ThemeData theme;

  const _SmsBubble({
    required this.body,
    required this.timeLabel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4), // Flat corner = incoming bubble
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ),
        if (timeLabel.isNotEmpty) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              timeLabel,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
        ],
      ],
    );
  }
}

/// Community scammer banner — softer red, shows report count
class _CommunityBanner extends StatelessWidget {
  final int reportCount;
  const _CommunityBanner({required this.reportCount});

  @override
  Widget build(BuildContext context) {
    final label = reportCount > 0
        ? 'Reported by $reportCount SafeText ${reportCount == 1 ? 'user' : 'users'} as a scammer'
        : 'Flagged by the SafeText community as a scammer';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.group_rounded, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.red.shade800,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline mode badge
class _OfflineBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 15),
          SizedBox(width: 7),
          Text(
            'Offline mode — keyword filter used',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Bottom action bar with "It's safe" and "Report & block"
class _ActionBar extends StatelessWidget {
  final VoidCallback onSafe;
  final VoidCallback onReport;
  final String lang;

  const _ActionBar({
    required this.onSafe,
    required this.onReport,
    required this.lang,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── It's safe ─────────────────────────────────────────────────
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSafe,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text("It's safe"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.green.shade600,
                side: BorderSide(color: Colors.green.shade400),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // ── Report & block ─────────────────────────────────────────────
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text('Report & block'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tag info model
// ═══════════════════════════════════════════════════════════════════════════

class _TagInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _TagInfo(this.label, this.color, this.icon);
}
