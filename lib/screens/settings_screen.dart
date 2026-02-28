import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final TextEditingController _blockController = TextEditingController();
  final TextEditingController _allowController = TextEditingController();

  List<String> _blockList = [];
  List<String> _allowList = [];
  bool _smsDeliveryReports = false;
  int _flaggedCount = 0;
  int _blockedCount = 0;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadPrefs();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _blockList = prefs.getStringList('block_list') ?? [];
      _allowList = prefs.getStringList('allow_list') ?? [];
      _smsDeliveryReports = prefs.getBool('sms_delivery_reports') ?? false;
      _flaggedCount = prefs.getInt('flagged_count') ?? 0;
      _blockedCount = prefs.getInt('blocked_count') ?? 0;
    });
  }

  Future<void> _saveList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value);
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _scheduleDailySummary() async {
    final androidDetails = AndroidNotificationDetails(
      'daily_summary_channel',
      'Daily Summary',
      channelDescription: 'Shows daily summary of blocked and flagged SMS.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    final details = NotificationDetails(android: androidDetails);

    final body =
        'Flagged: $_flaggedCount, Blocked: $_blockedCount messages today.';

    await _notificationsPlugin.periodicallyShow(
      100,
      'SafeText daily summary',
      body,
      RepeatInterval.daily,
      details,
      androidAllowWhileIdle: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daily summary scheduled (every 24h).')),
    );
  }

  void _addToBlockList() {
    final value = _blockController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _blockList.add(value);
      _blockController.clear();
    });
    _saveList('block_list', _blockList);
  }

  void _addToAllowList() {
    final value = _allowController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _allowList.add(value);
      _allowController.clear();
    });
    _saveList('allow_list', _allowList);
  }

  @override
  void dispose() {
    _blockController.dispose();
    _allowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ExpansionTile(
            backgroundColor: theme.cardColor,
            collapsedBackgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Block List'),
            subtitle: Text(
              'Numbers or keywords to always treat as spam.',
              style: theme.textTheme.bodySmall,
            ),
            childrenPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (_blockList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'No blocked items yet.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                ..._blockList.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _blockList.remove(item);
                        });
                        _saveList('block_list', _blockList);
                      },
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _blockController,
                      style: theme.textTheme.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Number or word',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addToBlockList,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            backgroundColor: theme.cardColor,
            collapsedBackgroundColor: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text('Allow List'),
            subtitle: Text(
              'Trusted numbers or keywords that bypass filters.',
              style: theme.textTheme.bodySmall,
            ),
            childrenPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (_allowList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'No allowed items yet.',
                    style: theme.textTheme.bodySmall,
                  ),
                )
              else
                ..._allowList.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(() {
                          _allowList.remove(item);
                        });
                        _saveList('allow_list', _allowList);
                      },
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _allowController,
                      style: theme.textTheme.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Number or word',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addToAllowList,
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 20),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Re-Sync Inbox'),
            subtitle: Text(
              'Reload and re-categorize all SMS messages.',
              style: theme.textTheme.bodySmall,
            ),
            trailing: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Re-Sync'),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Day\'s summary'),
            subtitle: Text(
              'Flagged: $_flaggedCount, Blocked: $_blockedCount messages.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _scheduleDailySummary,
              child: const Text('Schedule Daily Summary at 9 PM'),
            ),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('SMS delivery reports'),
            subtitle: Text(
              'Show delivery status in notification shade (placeholder).',
              style: theme.textTheme.bodySmall,
            ),
            value: _smsDeliveryReports,
            onChanged: (val) {
              setState(() {
                _smsDeliveryReports = val;
              });
              _saveBool('sms_delivery_reports', val);
            },
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Theme'),
            subtitle: Text(
              'System Default',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}