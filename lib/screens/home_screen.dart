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
import 'message_detail_screen.dart';
import 'settings_screen.dart';
import 'education_hub_screen.dart';
import '../utils/translations.dart';
import '../main.dart';
import '../firebase/firestore_service.dart';
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(SmsMessage msg) async {
  debugPrint('Received background message: ${msg.body}');
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final prefs = await SharedPreferences.getInstance();
  final blockList = prefs.getStringList('blockList') ?? [];
  final addr = msg.address ?? '';
  if (blockList.any((b) => addr.contains(b) || b.contains(addr))) return;

  try {
    final url = Uri.parse(predictUrl);
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': msg.body ?? ''}),
    );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final confidence = (data['confidence'] as num?)?.toDouble();
        
        try { await FirestoreService().logEvent('message_scanned', 'Background message scanned'); } catch (_) {}

        if (confidence != null && confidence >= 0.8) {
          try {
            await FirestoreService().writeFlaggedMessage(
              messageText: msg.body ?? '',
              senderNumber: addr,
              confidenceScore: confidence,
              patternTags: ['background_scan'],
            );
          } catch (_) {}

          await NotificationService.showSuspiciousAlert(
            from: addr,
            bodySnippet: (msg.body ?? '').length > 60
                ? '${(msg.body ?? '').substring(0, 60)}...'
                : (msg.body ?? ''),
          );

          try { await FirestoreService().logEvent('alert_shown', 'Suspicious alert shown (background)'); } catch (_) {}
        }
      }
    } catch (e) {
    debugPrint('Background Predict failed: $e');
  }
}

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

  @override
  void initState() {
    super.initState();
    _ensurePermissionAndLoadSms();
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        await _handleNewSms(msg);
      },
      onBackgroundMessage: onBackgroundMessage,
      listenInBackground: true,
    );
  }

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
      final filtered = messages.where((m) {
        final addr = m.address ?? '';
        return !blockList.any((b) => addr.contains(b) || b.contains(addr));
      }).toList();
      _messages = filtered;
    } on PlatformException catch (e) {
      debugPrint('Failed to load SMS: $e');
    }
  }

  Future<void> _handleNewSms(SmsMessage msg) async {
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    final addr = msg.address ?? '';
    if (blockList.any((b) => addr.contains(b) || b.contains(addr))) return;
    
    // Refresh list locally
    await _loadSms();
    if (mounted) setState(() {});

    // Still send to backend for potential notification
    try {
      final url = Uri.parse(predictUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': msg.body ?? ''}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final confidence = (data['confidence'] as num?)?.toDouble();

        try { await FirestoreService().logEvent('message_scanned', 'Foreground message scanned'); } catch (_) {}

        if (confidence != null && confidence >= 0.8) {
          try {
            await FirestoreService().writeFlaggedMessage(
              messageText: msg.body ?? '',
              senderNumber: addr,
              confidenceScore: confidence,
              patternTags: ['foreground_scan'],
            );
          } catch (_) {}

          await NotificationService.showSuspiciousAlert(
            from: addr,
            bodySnippet: (msg.body ?? '').length > 60
                ? '${(msg.body ?? '').substring(0, 60)}...'
                : (msg.body ?? ''),
          );

          try { await FirestoreService().logEvent('alert_shown', 'Suspicious alert shown (foreground)'); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Predict failed on new sms: $e');
    }
  }

  List<SmsMessage> _filterByQuery(List<SmsMessage> list, String q) {
    if (q.trim().isEmpty) return list;
    final lower = q.trim().toLowerCase();
    return list.where((m) {
      final addr = (m.address ?? '').toLowerCase();
      final body = (m.body ?? '').toLowerCase();
      return addr.contains(lower) || body.contains(lower);
    }).toList();
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (now.year == date.year && now.month == date.month && now.day == date.day) {
      return DateFormat.jm().format(date);
    }
    return DateFormat.MMMd().format(date);
  }

  Color _getAvatarColor(String address) {
    if (address.isEmpty) return Colors.grey;
    final colors = [
      Colors.redAccent, Colors.blueAccent, Colors.green, 
      Colors.orange, Colors.deepPurpleAccent, Colors.teal
    ];
    return colors[address.hashCode % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text;
    final messagesFiltered = _filterByQuery(_messages, searchQuery);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(Translations.get('app_title', SafeTextApp.localeNotifier.value), style: const TextStyle(fontWeight: FontWeight.bold)),
            floating: true,
            snap: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.school_outlined),
                tooltip: Translations.get('education_hub', SafeTextApp.localeNotifier.value),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EducationHubScreen()),
                  );
                },
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
                        hintText: Translations.get('search_messages', SafeTextApp.localeNotifier.value),
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
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
                          ? ListView(
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                                const Center(
                                  child: Text('No messages found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                                )
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(top: 8, bottom: 80),
                              itemCount: messagesFiltered.length,
                              itemBuilder: (context, index) {
                                final msg = messagesFiltered[index];
                                return _buildMessageTile(msg);
                              },
                            ),
                    ),
                  ),
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
            builder: (_) => MessageDetailScreen(message: msg),
          ),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(msg.date),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.body ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
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
                 padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
              ),
              onPressed: _ensurePermissionAndLoadSms,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open Settings', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            child: const Text('Block', style: TextStyle(color: Colors.redAccent)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
           content: Text('$addr blocked'),
           behavior: SnackBarBehavior.floating,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        )
      );
      await _loadSms();
      setState(() {});
    }
  }
}
