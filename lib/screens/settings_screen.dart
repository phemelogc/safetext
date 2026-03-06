import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onReSync;

  const SettingsScreen({super.key, this.onReSync});

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
    widget.onReSync?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Re-syncing...')),
      );
    }
  }

  Future<void> _setupNotifications() async {
    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await notifications.initialize(
      settings: const InitializationSettings(android: initSettingsAndroid),
    );
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...(isBlock ? blockList : allowList).map((item) => Text(item)),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(isBlock ? 'Add number to block' : 'Add to allow list'),
                onPressed: () async {
                  Navigator.pop(context);
                  final controller = TextEditingController();
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isBlock ? 'Block number' : 'Allow number'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          hintText: 'Number or name',
                        ),
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  );
                  if (added == true && controller.text.trim().isNotEmpty) {
                    await _addToList(controller.text.trim(), isBlock);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ],
          ),
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
