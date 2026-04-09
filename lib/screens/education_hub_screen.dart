import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/translations.dart';
import '../main.dart';
import '../firebase/firestore_service.dart';

class EducationHubScreen extends StatefulWidget {
  const EducationHubScreen({super.key});

  @override
  State<EducationHubScreen> createState() => _EducationHubScreenState();
}

class _EducationHubScreenState extends State<EducationHubScreen> {
  static const _cacheKey = 'cached_educational_alerts';

  final List<Map<String, String>> _hardcodedTopics = [
    {
      'title': 'Phishing Attacks',
      'desc': 'Scammers send fake emails or texts to steal passwords and bank details. Never click unverified links.',
      'icon': 'fishing',
    },
    {
      'title': 'Smishing (SMS Phishing)',
      'desc': 'Scams delivered via SMS — often impersonating banks or delivery services to request payment.',
      'icon': 'sms',
    },
    {
      'title': 'Wangiri (One Ring Scam)',
      'desc': 'Your phone rings once from an overseas number. Calling back charges premium rates to the scammer.',
      'icon': 'phone',
    },
    {
      'title': 'Lottery & Sweepstakes',
      'desc': 'Texts claiming you won a prize but need to pay an "admin fee" first. Legitimate lotteries never do this.',
      'icon': 'gift',
    },
  ];

  List<Map<String, String>> _cachedAlerts = [];

  @override
  void initState() {
    super.initState();
    _loadCachedAlerts();
  }

  Future<void> _loadCachedAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && mounted) {
        setState(() {
          _cachedAlerts = (jsonDecode(raw) as List)
              .map((e) => Map<String, String>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _persistAlerts(List<Map<String, String>> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(alerts));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final lang = SafeTextApp.localeNotifier.value;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(Translations.get('education_hub', lang),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(child: Icon(Icons.school, size: 80, color: Colors.white24)),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(Translations.get('latest_trends', lang),
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirestoreService().getPublishedAlerts(),
                  builder: (context, snapshot) {
                    final liveAlerts = <Map<String, String>>[];
                    if (snapshot.hasData) {
                      for (final doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        liveAlerts.add({
                          'title': data['title']?.toString() ?? 'Live Alert',
                          'desc': data['content']?.toString() ??
                              data['description']?.toString() ?? '',
                          'icon': 'info',
                        });
                      }
                      if (liveAlerts.isNotEmpty) {
                        _persistAlerts(liveAlerts);
                        if (_cachedAlerts.length != liveAlerts.length) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _cachedAlerts = liveAlerts);
                          });
                        }
                      }
                    }

                    final firestoreTopics = snapshot.hasData ? liveAlerts : _cachedAlerts;
                    final allTopics = [...firestoreTopics, ..._hardcodedTopics];

                    if (snapshot.connectionState == ConnectionState.waiting &&
                        firestoreTopics.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: allTopics.map((t) => _buildTopicCard(context, t, lang)).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildToolsSection(lang, context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicCard(BuildContext context, Map<String, String> topic, String lang) {
    final iconData = switch (topic['icon']) {
      'fishing' => Icons.phishing,
      'sms' => Icons.sms_failed,
      'phone' => Icons.phone_callback,
      'gift' => Icons.card_giftcard,
      _ => Icons.info,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  child: Icon(iconData, color: Theme.of(context).primaryColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(topic['title']!,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(topic['desc']!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                Translations.get('read_more', lang),
                style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsSection(String lang, BuildContext context) {
    final tools = [
      {
        'title': 'Check Link Safety',
        'icon': Icons.link,
        'action': () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Coming soon!')),
            ),
      },
      {
        'title': 'Report to Authorities',
        'icon': Icons.local_police,
        'action': () async {
          const url = 'https://www.ic3.gov/';
          if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
        },
      },
      {
        'title': 'Security Settings',
        'icon': Icons.security,
        'action': () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Opening device security settings...')),
            ),
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Important Tools', style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: tools.length,
            itemBuilder: (_, i) => _buildToolItem(context, tools[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildToolItem(BuildContext context, Map<String, dynamic> tool) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 16),
      child: InkWell(
        onTap: tool['action'] as VoidCallback,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(tool['icon'] as IconData,
                  size: 32, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              tool['title'] as String,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
