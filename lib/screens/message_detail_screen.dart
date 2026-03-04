import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:custom_advanced_sms/custom_advanced_sms.dart';

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
    final url = Uri.parse('https://safetextbackend.onrender.com/predict');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': widget.message.body ?? ''}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        _prediction =
            'Confidence: ${data['confidence']}%\nExplanation: ${data['explanation']}';
      });
    } else {
      setState(() => _prediction = 'Error analyzing.');
    }
  }

  Future<void> _sendFeedback(bool isSmishing) async {
    final url = Uri.parse('https://safetextbackend.onrender.com/feedback');
    await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': widget.message.body,
        'label': isSmishing ? 'smishing' : 'safe',
      }),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Feedback sent')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.message.address ?? 'Unknown')),
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
                  onPressed: () => _sendFeedback(true),
                  child: const Text('Flag as Smishing'),
                ),
                ElevatedButton(
                  onPressed: () => _sendFeedback(false),
                  child: const Text('Mark as Safe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
