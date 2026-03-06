import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../services/notification_service.dart';
import 'message_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Telephony _telephony = Telephony.instance;
  final TextEditingController _searchController = TextEditingController();
  List<SmsMessage> personal = [], business = [], suspicious = [];
  bool _permissionDenied = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _ensurePermissionAndLoadSms();
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        await _handleNewSms(msg);
      },
      listenInBackground: false,
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
    personal.clear();
    business.clear();
    suspicious.clear();
    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      final filtered = messages.where((m) {
        final addr = m.address ?? '';
        return !blockList.any((b) => addr.contains(b) || b.contains(addr));
      }).toList();
      for (var msg in filtered) {
        await _categorizeSms(msg);
      }
      if (mounted) setState(() {});
    } on PlatformException catch (e) {
      debugPrint('Failed to load SMS: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleNewSms(SmsMessage msg) async {
    final prefs = await SharedPreferences.getInstance();
    final blockList = prefs.getStringList('blockList') ?? [];
    final addr = msg.address ?? '';
    if (blockList.any((b) => addr.contains(b) || b.contains(addr))) return;
    final confidence = await _categorizeSms(msg);
    if (confidence != null && confidence >= 0.8) {
      await NotificationService.showSuspiciousAlert(
        from: addr,
        bodySnippet: (msg.body ?? '').length > 60
            ? '${(msg.body ?? '').substring(0, 60)}...'
            : (msg.body ?? ''),
      );
    }
    if (mounted) setState(() {});
  }

  /// Returns suspicion confidence (0.0–1.0) if API succeeded, else null.
  Future<double?> _categorizeSms(SmsMessage msg) async {
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
        if (confidence != null) {
          if (confidence >= 0.6) {
            suspicious.add(msg);
          } else if (_isBusiness(msg)) {
            business.add(msg);
          } else {
            personal.add(msg);
          }
          return confidence;
        }
      }
    } catch (e) {
      debugPrint('Predict failed: $e');
      personal.add(msg);
    }
    return null;
  }

  bool _isBusiness(SmsMessage msg) {
    return msg.address?.contains('BANK') ??
        false || (msg.body?.toLowerCase().contains('offer') ?? false);
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

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text;
    final personalFiltered = _filterByQuery(personal, searchQuery);
    final businessFiltered = _filterByQuery(business, searchQuery);
    final suspiciousFiltered = _filterByQuery(suspicious, searchQuery);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    onReSync: () async {
                      await _loadSms();
                      if (mounted) setState(() {});
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
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'People'),
                  Tab(text: 'Business'),
                  Tab(text: 'Suspicious'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'SMS permission is needed to show your messages.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _ensurePermissionAndLoadSms,
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () => openAppSettings(),
                          child: const Text('Open Settings'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSmsList(personalFiltered),
                    _buildSmsList(businessFiltered),
                    _buildSmsList(suspiciousFiltered),
                  ],
                ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _blockContactFromList(SmsMessage msg) async {
    final addr = msg.address ?? '';
    if (addr.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block contact?'),
        content: Text(
          'Messages from $addr will be hidden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$addr blocked')));
      await _loadSms();
      setState(() {});
    }
  }

  Widget _buildSmsList(List<SmsMessage> messages) {
    return ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        return ListTile(
          leading: CircleAvatar(child: Text(msg.address?[0] ?? 'U')),
          title: Text(msg.address ?? 'Unknown'),
          subtitle: Text(
            msg.body ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(msg.date?.toString() ?? ''),
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
        );
      },
    );
  }
}
