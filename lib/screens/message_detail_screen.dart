import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';

const String _backendBaseUrl = 'https://safetextbackend.onrender.com';

class MessageDetailScreen extends StatefulWidget {
  final SmsMessage message;

  const MessageDetailScreen({super.key, required this.message});

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  bool _loadingPredict = true;
  double? _confidence; // 0–100
  String? _explanation;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPrediction();
  }

  Future<void> _fetchPrediction() async {
    final body = widget.message.body ?? '';
    if (body.trim().isEmpty) {
      setState(() {
        _loadingPredict = false;
        _error = 'Message has no content.';
      });
      return;
    }

    try {
      final uri = Uri.parse('$_backendBaseUrl/predict');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': body}),
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final confidence = (json['confidence'] as num).toDouble();
        final explanation = json['explanation'] as String? ?? '';

        setState(() {
          _confidence = confidence;
          _explanation = explanation;
          _error = null;
          _loadingPredict = false;
        });

        if (confidence > 50) {
          await _incrementCounter('flagged_count');
        }
      } else {
        setState(() {
          _error = 'Failed to analyze message (${res.statusCode}).';
          _loadingPredict = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Unable to reach SafeText server.';
        _loadingPredict = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error while predicting.'),
          ),
        );
      }
    }
  }

  Future<void> _sendFeedback(String label) async {
    final body = widget.message.body ?? '';
    if (body.trim().isEmpty) return;

    try {
      final uri = Uri.parse('$_backendBaseUrl/feedback');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': body,
          'label': label, // "smishing" or "safe"
        }),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (label == 'smishing') {
          await _incrementCounter('blocked_count');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                label == 'smishing'
                    ? 'Marked as smishing. Thanks for the feedback.'
                    : 'Marked as safe.',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Feedback failed. Please try again later.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error while sending feedback.'),
          ),
        );
      }
    }
  }

  Future<void> _incrementCounter(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = widget.message;
    final address = msg.address ?? 'Unknown';
    final body = msg.body ?? '';
    final date = DateTime.fromMillisecondsSinceEpoch(msg.date ?? 0);
    final dateText =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    Color statusColor;
    String statusLabel;
    if (_confidence == null) {
      statusColor = const Color(0xFF2196F3);
      statusLabel = 'Analyzing...';
    } else if (_confidence! > 50) {
      statusColor = Colors.redAccent;
      statusLabel = 'Suspicious';
    } else {
      statusColor = const Color(0xFF4CAF50);
      statusLabel = 'Likely Safe';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              address,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('Received', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              dateText,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  body,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _loadingPredict
                    ? const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2196F3),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Analyzing message...'),
                        ],
                      )
                    : _error != null
                        ? Text(
                            _error!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.redAccent),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: statusColor),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (_confidence != null)
                                    Text(
                                      '${_confidence!.toStringAsFixed(0)}%',
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_explanation != null &&
                                  _explanation!.trim().isNotEmpty)
                                Text(
                                  _explanation!,
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _sendFeedback('smishing'),
                    child: const Text('Flag as Smishing'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _sendFeedback('safe'),
                    child: const Text('Mark as Safe'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
