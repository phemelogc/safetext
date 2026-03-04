import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();
  List<String> blockList = [], allowList = [];

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      blockList = prefs.getStringList('blockList') ?? [];
      allowList = prefs.getStringList('allowList') ?? [];
    });
  }

  Future<void> _addToList(String sender, bool isBlock) async {
    final prefs = await SharedPreferences.getInstance();
    final list = isBlock ? blockList : allowList;
    list.add(sender);
    await prefs.setStringList(isBlock ? 'blockList' : 'allowList', list);
    setState(() {});
  }

  Future<void> _reSync() async {
    // Re-load and re-categorize SMS; call your home logic
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Re-syncing...')));
  }

  Future<void> _setupNotifications() async {
    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      const InitializationSettings(android: initSettingsAndroid),
    );
    // Schedule daily summary, e.g., via flutter_local_notifications
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Block List'),
            trailing: Text('${blockList.length}'),
            onTap: () => _showListDialog(true),
          ),
          ListTile(
            title: const Text('Allow List'),
            trailing: Text('${allowList.length}'),
            onTap: () => _showListDialog(false),
          ),
          ListTile(title: const Text('Re-Sync Inbox'), onTap: _reSync),
          ListTile(
            title: const Text('Daily Summary Notifications'),
            trailing: Switch(
              value: true,
              onChanged: (_) => _setupNotifications(),
            ),
          ),
          ListTile(
            title: const Text('Theme'),
            subtitle: const Text('System Default'),
          ),
        ],
      ),
    );
  }

  void _showListDialog(bool isBlock) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isBlock ? 'Block List' : 'Allow List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: (isBlock ? blockList : allowList)
              .map((item) => Text(item))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
