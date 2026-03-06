import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';

class MessageDetailScreen extends StatefulWidget {
  final SmsMessage message;
  const MessageDetailScreen({super.key, required this.message});

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  String _prediction = 'Analyzing...';

  @override
  void initState() {
    super.initState();
    _getPrediction();
  }

  Future<void> _getPrediction() async {
    try {
      final url = Uri.parse(predictUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': widget.message.body ?? ''}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final confidence = (data['confidence'] as num?)?.toDouble();
        final percent = confidence != null ? (confidence * 100).round() : null;
        if (mounted) {
          setState(() {
            _prediction = percent != null
                ? 'Suspicion: $percent%\n${data['explanation'] ?? ''}'
                : 'Suspicion: -\n${data['explanation'] ?? ''}';
          });
        }
      } else {
        if (mounted) setState(() => _prediction = 'Error analyzing.');
      }
    } catch (_) {
      if (mounted) setState(() => _prediction = 'Error analyzing.');
    }
  }

  Future<void> _sendFeedback(bool isReport) async {
    try {
      final url = Uri.parse(feedbackUrl);
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': widget.message.body,
          'label': isReport ? 'report' : 'legit',
          'address': widget.message.address,
        }),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback sent')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send feedback')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$addr blocked')),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.message.address ?? 'Unknown'),
        actions: [
          IconButton(
            icon: const Icon(Icons.block),
            tooltip: 'Block contact',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Block contact?'),
                  content: Text(
                    'Messages from ${widget.message.address ?? "this number"} will be hidden.',
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
              if (confirm == true) await _blockContact();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.message.body ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _prediction,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () => _sendFeedback(false),
                  child: const Text('Legit'),
                ),
                ElevatedButton(
                  onPressed: () => _sendFeedback(true),
                  child: const Text('Report'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
