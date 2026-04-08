import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../services/notification_service.dart';
import '../services/offline_classifier.dart';
import '../services/connectivity_service.dart';
import 'message_detail_screen.dart';
import 'settings_screen.dart';
import 'education_hub_screen.dart';
import '../utils/translations.dart';
import '../main.dart';
import '../firebase/firestore_service.dart';

// Confidence threshold for triggering a push notification.
const double _kNotifyThreshold = 0.85;

// ── Background SMS handler (separate isolate) ──────────────────────────────

@pragma('vm:entry-point')
Future<void> onBackgroundMessage(SmsMessage msg) async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  final prefs = await SharedPreferences.getInstance();
  final blockList = prefs.getStringList('blockList') ?? [];
  final addr = msg.address ?? '';
  if (blockList.any((b) => addr.contains(b) || b.contains(addr))) return;

  double confidence = 0.0;
  List<String> tags = [];

  // Try online classifier, fall back to offline.
  try {
    final response = await http
        .post(
          Uri.parse(predictUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'message': msg.body ?? ''}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
      tags = List<String>.from(data['tags'] as List? ?? []);

      try {
        await FirestoreService().logEvent(
            'message_scanned', 'Background message scanned');
      } catch (_) {}
    } else {
      throw Exception('non-200');
    }
  } catch (_) {
    // Backend unreachable — use offline classifier.
    final result = OfflineClassifier.classify(msg.body ?? '');
    confidence = (result['confidence'] as num).toDouble();
    tags = List<String>.from(result['tags'] as List);
  }

  if (confidence >= _kNotifyThreshold) {
    try {
      await FirestoreService().writeFlaggedMessage(
        messageText: msg.body ?? '',
        senderNumber: addr,
        confidenceScore: confidence,
        patternTags: tags,
      );
    } catch (_) {}

    await NotificationService.showSuspiciousAlert(
      from: addr,
      bodySnippet: (msg.body ?? '').length > 60
          ? '${(msg.body ?? '').substring(0, 60)}...'
          : (msg.body ?? ''),
    );

    try {
      await FirestoreService().logEvent(
          'alert_shown', 'Suspicious alert shown (background)');
    } catch (_) {}
  }
}

// ── Home screen ───────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Telephony _telephony = Telephony.instance;
  final TextEditingController _searchController = TextEditingController();

  List<SmsMessage> _messages = [];
  bool _permissionDenied = false;
  bool _loading = true;
  bool _isOnline = true;

  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();

    // Track connectivity changes.
    _isOnline = ConnectivityService().isOnline;
    _connectivitySub = ConnectivityService().onStatusChange.listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });

    _ensurePermissionAndLoadSms();

    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        await _handleNewSms(msg);
      },
      onBackgroundMessage: onBackgroundMessage,
      listenInBackground: true,
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── SMS loading ───────────────────────────────────────────────────────────

  Future<void> _ensurePermissionAndLoadSms() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    final smsGranted = await Permission.sms.isGranted;
    if (!smsGranted) {
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        setState(() {
          _loading = false;
          _permissionDenied = true;
        });
        return;
      }
    }
    final telephonyGranted = await _telephony.requestPhoneAndSmsPermissions;
    if (telephonyGranted != true) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }
    await _loadSms();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSms() async {
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      _messages = messages.where((m) {
        final addr = m.address ?? '';
        return !blockList.any((b) => addr.contains(b) || b.contains(addr));
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('Failed to load SMS: $e');
    }
  }

  // ── New SMS handling (foreground) ─────────────────────────────────────────

  Future<void> _handleNewSms(SmsMessage msg) async {
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    final addr = msg.address ?? '';
    if (blockList.any((b) => addr.contains(b) || b.contains(addr))) return;

    await _loadSms();
    if (mounted) setState(() {});

    double confidence = 0.0;
    List<String> tags = [];

    try {
      final response = await http
          .post(
            Uri.parse(predictUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'message': msg.body ?? ''}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;
        tags = List<String>.from(data['tags'] as List? ?? []);
        try {
          await FirestoreService().logEvent(
              'message_scanned', 'Foreground message scanned');
        } catch (_) {}
      } else {
        throw Exception('non-200');
      }
    } catch (_) {
      // Offline fallback
      final result = OfflineClassifier.classify(msg.body ?? '');
      confidence = (result['confidence'] as num).toDouble();
      tags = List<String>.from(result['tags'] as List);
    }

    if (confidence >= _kNotifyThreshold) {
      try {
        await FirestoreService().writeFlaggedMessage(
          messageText: msg.body ?? '',
          senderNumber: addr,
          confidenceScore: confidence,
          patternTags: tags,
        );
      } catch (_) {}

      await NotificationService.showSuspiciousAlert(
        from: addr,
        bodySnippet: (msg.body ?? '').length > 60
            ? '${(msg.body ?? '').substring(0, 60)}...'
            : (msg.body ?? ''),
      );

      try {
        await FirestoreService().logEvent(
            'alert_shown', 'Suspicious alert shown (foreground)');
      } catch (_) {}
    }
  }

  // ── Scan Inbox ────────────────────────────────────────────────────────────

  Future<void> _scanInbox() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ScanInboxSheet(telephony: _telephony),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<SmsMessage> _filterByQuery(List<SmsMessage> list, String q) {
    if (q.trim().isEmpty) return list;
    final lower = q.trim().toLowerCase();
    return list.where((m) {
      return (m.address ?? '').toLowerCase().contains(lower) ||
          (m.body ?? '').toLowerCase().contains(lower);
    }).toList();
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      return DateFormat.jm().format(date);
    }
    return DateFormat.MMMd().format(date);
  }

  Color _getAvatarColor(String address) {
    if (address.isEmpty) return Colors.grey;
    final colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.green,
      Colors.orange,
      Colors.deepPurpleAccent,
      Colors.teal,
    ];
    return colors[address.hashCode % colors.length];
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text;
    final messagesFiltered = _filterByQuery(_messages, searchQuery);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanInbox,
        icon: const Icon(Icons.search),
        label: const Text('Scan Inbox'),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: Column(
        children: [
          // Offline banner
          if (!_isOnline)
            Material(
              color: Colors.orange.shade800,
              child: const SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline mode — using local keyword filter',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  title: Text(
                    Translations.get(
                        'app_title', SafeTextApp.localeNotifier.value),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  floating: true,
                  snap: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.school_outlined),
                      tooltip: Translations.get(
                          'education_hub', SafeTextApp.localeNotifier.value),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EducationHubScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(
                              onReSync: () async {
                                setState(() => _loading = true);
                                await _loadSms();
                                if (mounted) setState(() => _loading = false);
                              },
                            ),
                          ),
                        );
                        if (!mounted) return;
                        await _loadSms();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(70),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Hero(
                        tag: 'searchBar',
                        child: Material(
                          color: Colors.transparent,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: Translations.get('search_messages',
                                  SafeTextApp.localeNotifier.value),
                              hintStyle:
                                  TextStyle(color: Colors.grey.shade400),
                              prefixIcon: const Icon(Icons.search,
                                  color: Colors.grey),
                              filled: true,
                              fillColor: Theme.of(context).cardColor,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 0, horizontal: 20),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(30),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _permissionDenied
                      ? _buildPermissionWarning()
                      : RefreshIndicator(
                          onRefresh: () async {
                            await _loadSms();
                            if (mounted) setState(() {});
                          },
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: messagesFiltered.isEmpty
                                ? ListView(children: [
                                    SizedBox(
                                        height: MediaQuery.of(context)
                                                .size
                                                .height *
                                            0.3),
                                    const Center(
                                      child: Text('No messages found.',
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 16)),
                                    ),
                                  ])
                                : ListView.builder(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 100),
                                    itemCount: messagesFiltered.length,
                                    itemBuilder: (context, index) =>
                                        _buildMessageTile(
                                            messagesFiltered[index]),
                                  ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(SmsMessage msg) {
    final address = msg.address ?? 'Unknown';
    final initial = address.isNotEmpty ? address[0].toUpperCase() : '?';

    return InkWell(
      onTap: () async {
        final blocked = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => MessageDetailScreen(message: msg)),
        );
        if (blocked == true && mounted) {
          await _loadSms();
          if (mounted) setState(() {});
        }
      },
      onLongPress: () => _blockContactFromList(msg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _getAvatarColor(address),
              child: Text(
                initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          address,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(msg.date),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.body ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: Colors.grey.shade300, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionWarning() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sms_failed, size: 60, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'SMS permission is needed to show your messages.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _ensurePermissionAndLoadSms,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open Settings',
                  style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _blockContactFromList(SmsMessage msg) async {
    final addr = msg.address ?? '';
    if (addr.isEmpty) return;
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Block contact?'),
        content: Text('Messages from $addr will be hidden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Block', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    if (!blockList.contains(addr)) {
      blockList.add(addr);
      await prefs.setStringList('blockList', blockList);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$addr blocked'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      await _loadSms();
      setState(() {});
    }
  }
}

// ── Scan Inbox sheet ──────────────────────────────────────────────────────

class _ScanResult {
  final SmsMessage message;
  final bool flagged;
  final double confidence;
  final List<String> tags;

  const _ScanResult({
    required this.message,
    required this.flagged,
    required this.confidence,
    required this.tags,
  });
}

class _ScanInboxSheet extends StatefulWidget {
  final Telephony telephony;
  const _ScanInboxSheet({required this.telephony});

  @override
  State<_ScanInboxSheet> createState() => _ScanInboxSheetState();
}

class _ScanInboxSheetState extends State<_ScanInboxSheet> {
  bool _scanning = false;
  int _progress = 0;
  int _total = 0;
  List<_ScanResult> _results = [];

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() => _scanning = true);
    List<SmsMessage> messages = [];
    try {
      messages = await widget.telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan('0'),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );
    } catch (_) {}

    final sample = messages.take(50).toList();
    setState(() => _total = sample.length);

    final results = <_ScanResult>[];
    final isOnline = ConnectivityService().isOnline;

    for (final msg in sample) {
      bool flagged = false;
      double confidence = 0.0;
      List<String> tags = [];

      if (isOnline) {
        try {
          final response = await http
              .post(
                Uri.parse(predictUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'message': msg.body ?? ''}),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200) {
            final data =
                jsonDecode(response.body) as Map<String, dynamic>;
            flagged = data['flagged'] as bool? ?? false;
            confidence =
                (data['confidence'] as num?)?.toDouble() ?? 0.0;
            tags = List<String>.from(data['tags'] as List? ?? []);
          } else {
            throw Exception('non-200');
          }
        } catch (_) {
          final r = OfflineClassifier.classify(msg.body ?? '');
          flagged = r['flagged'] as bool;
          confidence = (r['confidence'] as num).toDouble();
          tags = List<String>.from(r['tags'] as List);
        }
      } else {
        final r = OfflineClassifier.classify(msg.body ?? '');
        flagged = r['flagged'] as bool;
        confidence = (r['confidence'] as num).toDouble();
        tags = List<String>.from(r['tags'] as List);
      }

      results.add(_ScanResult(
        message: msg,
        flagged: flagged,
        confidence: confidence,
        tags: tags,
      ));

      if (mounted) setState(() => _progress++);
    }

    if (mounted) {
      setState(() {
        _results = results;
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final suspicious = _results.where((r) => r.flagged).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.search, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _scanning
                        ? 'Scanning inbox... ($_progress / $_total)'
                        : 'Scan complete — $suspicious suspicious',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          if (_scanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _progress / _total,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final addr = r.message.address ?? 'Unknown';
                final pct = (r.confidence * 100).round();
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: r.flagged
                        ? Colors.redAccent
                        : Colors.green,
                    child: Icon(
                      r.flagged
                          ? Icons.warning_amber_rounded
                          : Icons.check,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text(addr,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    (r.message.body ?? '').length > 60
                        ? '${(r.message.body ?? '').substring(0, 60)}...'
                        : r.message.body ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: r.confidence >= 0.85
                          ? Colors.red
                          : r.confidence >= 0.5
                              ? Colors.orange
                              : Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            MessageDetailScreen(message: r.message),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
