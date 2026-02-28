import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

import '../models/sms_category.dart';
import 'message_detail_screen.dart';
import 'settings_screen.dart';

const String _backendBaseUrl = 'https://safetextbackend.onrender.com';

final Telephony _telephony = Telephony.instance;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final Map<SmsCategory, List<SmsMessage>> _categorized = {
    SmsCategory.people: [],
    SmsCategory.business: [],
    SmsCategory.suspicious: [],
  };

  int _selectedTab = 0;
  bool _loadingInbox = false;
  int _suspiciousCount = 0;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissionAndLoad();
    _listenIncomingSms();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _requestPermissionAndLoad() async {
    final status = await Permission.sms.status;
    if (!status.isGranted) {
      final result = await Permission.sms.request();
      if (!result.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SafeText needs SMS permission to filter messages.'),
          ),
        );
        return;
      }
    }
    await _loadInbox();
  }

  Future<void> _loadInbox() async {
    setState(() {
      _loadingInbox = true;
    });

    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final Map<SmsCategory, List<SmsMessage>> temp = {
        SmsCategory.people: [],
        SmsCategory.business: [],
        SmsCategory.suspicious: [],
      };

      for (final msg in messages) {
        final body = msg.body ?? '';
        final category = _categorizeByKeywords(body);
        temp[category]!.add(msg);
      }

      setState(() {
        _categorized
          ..[SmsCategory.people] = temp[SmsCategory.people]!
          ..[SmsCategory.business] = temp[SmsCategory.business]!
          ..[SmsCategory.suspicious] = temp[SmsCategory.suspicious]!;
        _suspiciousCount = _categorized[SmsCategory.suspicious]!.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load SMS inbox.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingInbox = false;
        });
      }
    }
  }

  void _listenIncomingSms() {
    _telephony.listenIncomingSms(
      onNewMessage: _handleNewSms,
      listenInBackground: false,
    );
  }

  Future<void> _handleNewSms(SmsMessage message) async {
    final body = message.body ?? '';
    if (body.trim().isEmpty) return;

    SmsCategory category = _categorizeByKeywords(body);

    try {
      final uri = Uri.parse('$_backendBaseUrl/predict');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': body}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final confidence = (json['confidence'] as num).toDouble();

        if (confidence > 50) {
          category = SmsCategory.suspicious;
          await _showSuspiciousNotification(message, confidence);
        }
      }
    } catch (_) {
      // Silent network failure; app should keep working offline.
    }

    if (!mounted) return;

    setState(() {
      _categorized[category]!.insert(0, message);
      if (category == SmsCategory.suspicious) {
        _suspiciousCount++;
      }
    });
  }

  Future<void> _showSuspiciousNotification(
      SmsMessage message, double confidence) async {
    final body = message.body ?? '';
    final truncatedBody =
        body.length > 60 ? '${body.substring(0, 57)}...' : body;

    const androidDetails = AndroidNotificationDetails(
      'suspicious_sms_channel',
      'Suspicious SMS',
      channelDescription: 'Alerts when a suspicious SMS is detected.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);

    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _notificationsPlugin.show(
      id,
      'Suspicious message detected (${confidence.toStringAsFixed(0)}%)',
      '$truncatedBody\n\nTip: Never share your OTP or click unknown links.',
      details,
    );
  }

  SmsCategory _categorizeByKeywords(String body) {
    final lower = body.toLowerCase();
    final businessKeywords = [
      'bank',
      'otp',
      'offer',
      'loan',
      'payment',
      'transaction',
      'account',
      'invoice',
      'card',
      'discount',
    ];

    for (final k in businessKeywords) {
      if (lower.contains(k)) return SmsCategory.business;
    }
    return SmsCategory.people;
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedTab = index;
    });
  }

  SmsCategory get _currentCategory {
    switch (_selectedTab) {
      case 0:
        return SmsCategory.people;
      case 1:
        return SmsCategory.business;
      case 2:
        return SmsCategory.suspicious;
      default:
        return SmsCategory.people;
    }
  }

  Future<void> _openSettings() async {
    final resync = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (resync == true) {
      await _loadInbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = _categorized[_currentCategory] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // Reserved for future search; kept minimal now.
            },
          ),
          IconButton(
            icon: const Icon(Icons.mail_outline),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildTabs(theme),
          const Divider(height: 1, color: Color(0xFF2C2C2C)),
          Expanded(
            child: _loadingInbox
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2196F3)),
                  )
                : messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages in ${_currentCategory.label} yet.',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.builder(
                        itemCount: messages.length,
                        itemBuilder: (_, index) {
                          final msg = messages[index];
                          return _buildMessageTile(context, msg);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: null, // Disabled for now as requested.
        backgroundColor: const Color(0xFF2196F3).withOpacity(0.3),
        label: const Text('COMPOSE'),
        icon: const Icon(Icons.edit),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme) {
    const primary = Color(0xFF2196F3);
    const inactive = Color(0xFFBDBDBD);

    Widget buildTab(String label, int index, {Widget? badge}) {
      final isActive = _selectedTab == index;
      final color = isActive ? primary : inactive;

      return Expanded(
        child: InkWell(
          onTap: () => _onTabSelected(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      badge,
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 2,
                  width: 36,
                  decoration: BoxDecoration(
                    color: isActive ? primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget? suspiciousBadge;
    if (_suspiciousCount > 0) {
      suspiciousBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$_suspiciousCount',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white,
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      child: Row(
        children: [
          buildTab('People', 0),
          buildTab('Business', 1),
          buildTab('Suspicious', 2, badge: suspiciousBadge),
        ],
      ),
    );
  }

  Widget _buildMessageTile(BuildContext context, SmsMessage msg) {
    final theme = Theme.of(context);
    final address = msg.address ?? 'Unknown';
    final body = msg.body ?? '';
    final dateMillis = msg.date ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(dateMillis);
    final dateText = _formatDate(dt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: const Color(0xFF1E1E1E),
        child: Text(
          address.isNotEmpty ? address[0].toUpperCase() : '?',
          style: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.bold,
            color: Color(0xFF2196F3),
          ),
        ),
      ),
      title: Text(
        address,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        body,
        style: theme.textTheme.bodySmall,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        dateText,
        style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessageDetailScreen(message: msg),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    if (sameDay) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}';
  }
}
