import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  List<SmsMessage> personal = [], business = [], suspicious = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSms();
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) async {
        await _handleNewSms(msg);
      },
      listenInBackground: false,
    );
  }

  Future<void> _loadSms() async {
    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      );
      for (var msg in messages) {
        await _categorizeSms(msg);
      }
      setState(() {});
    } on PlatformException catch (e) {
      debugPrint('Failed to load SMS: $e');
    }
  }

  Future<void> _handleNewSms(SmsMessage msg) async {
    await _categorizeSms(msg);
    setState(() {});
  }

  Future<void> _categorizeSms(SmsMessage msg) async {
    final url = Uri.parse('https://safetextbackend.onrender.com/predict');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': msg.body ?? ''}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['confidence'] > 50) {
        suspicious.add(msg);
      } else if (_isBusiness(msg)) {
        business.add(msg);
      } else {
        personal.add(msg);
      }
    }
  }

  bool _isBusiness(SmsMessage msg) {
    return msg.address?.contains('BANK') ??
        false || (msg.body?.toLowerCase().contains('offer') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'People'),
            Tab(text: 'Business'),
            Tab(text: 'Suspicious'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSmsList(personal),
          _buildSmsList(business),
          _buildSmsList(suspicious),
        ],
      ),
    );
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MessageDetailScreen(message: msg),
            ),
          ),
        );
      },
    );
  }
}
