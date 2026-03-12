import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api.dart';
import '../utils/translations.dart';
import '../main.dart';

class MessageDetailScreen extends StatefulWidget {
  final SmsMessage message;
  const MessageDetailScreen({super.key, required this.message});

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> with SingleTickerProviderStateMixin {
  String _prediction = '';
  bool _isLoading = true;
  double? _confidence;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    
    _getPrediction();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _getPrediction() async {
    final lang = SafeTextApp.localeNotifier.value;
    try {
      final url = Uri.parse(predictUrl);
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': widget.message.body ?? ''}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _confidence = (data['confidence'] as num?)?.toDouble();
        
        if (mounted) {
          setState(() {
            _prediction = data['explanation'] ?? '';
            _isLoading = false;
          });
          _animController.forward();
        }
      } else {
        if (mounted) {
          setState(() {
            _prediction = Translations.get('error', lang);
            _isLoading = false;
          });
          _animController.forward();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _prediction = Translations.get('error', lang);
          _isLoading = false;
        });
        _animController.forward();
      }
    }
  }

  Future<void> _sendFeedback(bool isReport) async {
    final lang = SafeTextApp.localeNotifier.value;
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
           SnackBar(
             content: Text(Translations.get('feedback_sent', lang)),
             behavior: SnackBarBehavior.floating,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
           ),
        );
        if (isReport) {
           await _blockContact();
        } else {
           Navigator.pop(context, false);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Translations.get('error', lang))),
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
    final lang = SafeTextApp.localeNotifier.value;
    final isScam = _confidence != null && _confidence! > 0.6;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.message.address ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Text(
                        widget.message.body ?? '',
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 18, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isLoading)
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(Translations.get('analyzing', lang), style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    else
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isScam ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isScam ? Colors.redAccent.withOpacity(0.5) : Colors.green.withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isScam ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                                    color: isScam ? Colors.redAccent : Colors.green,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${Translations.get('suspicion', lang)}: ${(_confidence! * 100).round()}%',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isScam ? Colors.redAccent : Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _prediction,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: theme.textTheme.bodyMedium?.color,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (!_isLoading)
              FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _sendFeedback(false),
                          icon: const Icon(Icons.verified_user),
                          label: Text(Translations.get('ignore', lang)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _sendFeedback(true),
                          icon: const Icon(Icons.report_problem),
                          label: Text(Translations.get('report', lang)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
