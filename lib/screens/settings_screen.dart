import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/translations.dart';
import '../main.dart';

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
  bool _dailySummary = false;

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
      _dailySummary = prefs.getBool('dailySummary') ?? false;
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

  void _toggleDailySummary(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dailySummary', value);
    setState(() => _dailySummary = value);
    if (value) {
      await _setupNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily summary enabled')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = SafeTextApp.localeNotifier.value;
    final isDark = SafeTextApp.themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: Text(Translations.get('settings', lang))),
      body: ListView(
        children: [
          ListTile(
            title: Text(Translations.get('block_list', lang)),
            trailing: Text('${blockList.length}'),
            onTap: () => _showListDialog(true),
          ),
          ListTile(
            title: Text(Translations.get('allow_list', lang)),
            trailing: Text('${allowList.length}'),
            onTap: () => _showListDialog(false),
          ),
          ListTile(
            title: Text(Translations.get('resync_inbox', lang)),
            onTap: _reSync,
            trailing: const Icon(Icons.sync),
          ),
          const Divider(),
          SwitchListTile(
            title: Text(Translations.get('daily_summary', lang)),
            value: _dailySummary,
            onChanged: _toggleDailySummary,
            secondary: const Icon(Icons.notifications_active),
          ),
          SwitchListTile(
            title: Text(Translations.get('theme', lang)),
            subtitle: Text(isDark ? 'Dark Mode' : 'Light Mode'),
            value: isDark,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('isDark', val);
              SafeTextApp.themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
            },
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
          ),
          ListTile(
            title: Text(Translations.get('language', lang)),
            subtitle: Text(lang == 'en' ? 'English' : 'Setswana'),
            leading: const Icon(Icons.language),
            trailing: DropdownButton<String>(
              value: lang,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'tn', child: Text('Setswana')),
              ],
              onChanged: (newLang) async {
                if (newLang != null) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('lang', newLang);
                  SafeTextApp.localeNotifier.value = newLang;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showListDialog(bool isBlock) {
    final lang = SafeTextApp.localeNotifier.value;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isBlock ? Translations.get('block_list', lang) : Translations.get('allow_list', lang)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...(isBlock ? blockList : allowList).map((item) => Text(item)),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text('Add'),
                onPressed: () async {
                  Navigator.pop(context);
                  final controller = TextEditingController();
                  final added = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Add number'),
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
