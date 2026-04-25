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

  List<Map<String, dynamic>> _cachedAlerts = [];

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
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _persistAlerts(List<Map<String, dynamic>> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(alerts));
    } catch (_) {}
  }

  /// Maps the icon string stored in Firestore to a Material icon.
  IconData _iconFor(String? icon) => switch (icon) {
        'phishing' || 'fishing' => Icons.phishing,
        'sms' => Icons.sms_failed,
        'phone' => Icons.phone_callback,
        'gift' || 'lottery' => Icons.card_giftcard,
        'warning' => Icons.warning_amber_rounded,
        'lock' => Icons.lock,
        'money' => Icons.money_off,
        'identity' => Icons.badge,
        _ => Icons.info_outline,
      };

  // ── Tool actions ────────────────────────────────────────────────────────────

  Future<void> _checkLinkSafety() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check Link Safety'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'Paste a URL here…',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Scan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final raw = controller.text.trim();
    if (raw.isEmpty) return;

    // VirusTotal's URL-scan page accepts any URL in the query parameter.
    final vtUrl = Uri.parse(
      'https://www.virustotal.com/gui/home/url',
    );
    if (await canLaunchUrl(vtUrl)) {
      await launchUrl(vtUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _reportToAuthorities() async {
    final lang = SafeTextApp.localeNotifier.value;
    final options = [
      _ReportOption(
        label: 'IC3 (USA – Cybercrime)',
        url: 'https://www.ic3.gov/',
        icon: Icons.gavel,
      ),
      _ReportOption(
        label: 'SAPS (South Africa)',
        url: 'https://www.saps.gov.za/services/crimestop.php',
        icon: Icons.local_police,
      ),
      
      _ReportOption(
        label: 'BTRC (Botswana)',
        url: 'https://www.btrc.bw/',
        icon: Icons.public,
      ),
    ];

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Report to Authorities',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            const Divider(),
            ...options.map(
              (opt) => ListTile(
                leading: Icon(opt.icon, color: Theme.of(ctx).primaryColor),
                title: Text(opt.label),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse(opt.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSecuritySettings() async {
    // Android: launch the Security settings screen directly.
    final androidUri =
        Uri.parse('intent:#Intent;action=android.settings.SECURITY_SETTINGS;end');
    if (await canLaunchUrl(androidUri)) {
      await launchUrl(androidUri);
      return;
    }
    // Fallback: general device Settings.
    final settingsUri = Uri.parse('app-settings:');
    if (await canLaunchUrl(settingsUri)) {
      await launchUrl(settingsUri);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open your device Settings → Security.')),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

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
              title: Text(
                Translations.get('education_hub', lang),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF0D47A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.school, size: 80, color: Colors.white24),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    Translations.get('latest_trends', lang),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _buildScamTrendsStream(lang),
                const SizedBox(height: 24),
                _buildToolsSection(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScamTrendsStream(String lang) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirestoreService().getPublishedAlerts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Education hub Firestore error: ${snapshot.error}');
        }

        // Fresh live data
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = snapshot.data!.docs.toList()
            ..sort((a, b) {
              final aTs = (a.data() as Map<String, dynamic>)['published_at'];
              final bTs = (b.data() as Map<String, dynamic>)['published_at'];
              if (aTs == null || bTs == null) return 0;
              return (bTs as Timestamp).compareTo(aTs as Timestamp);
            });
          final liveAlerts = docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return <String, dynamic>{
              'title': d['title']?.toString() ?? 'Alert',
              'desc': d['content']?.toString() ??
                  d['description']?.toString() ?? '',
              'icon': d['icon']?.toString(),
            };
          }).toList();

          // Persist for offline use (fire-and-forget)
          _persistAlerts(liveAlerts);
          if (_cachedAlerts.length != liveAlerts.length) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _cachedAlerts = liveAlerts);
            });
          }

          return _topicList(context, liveAlerts, lang);
        }

        // Still loading — show cached while waiting
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_cachedAlerts.isNotEmpty) {
            return _topicList(context, _cachedAlerts, lang);
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Offline or empty — use cache
        if (_cachedAlerts.isNotEmpty) {
          return _topicList(context, _cachedAlerts, lang);
        }

        // Truly empty
        return _emptyState(context, lang);
      },
    );
  }

  Widget _topicList(
    BuildContext context,
    List<Map<String, dynamic>> topics,
    String lang,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: topics.map((t) => _buildTopicCard(context, t, lang)).toList(),
    );
  }

  Widget _emptyState(BuildContext context, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.article_outlined,
                size: 64, color: Theme.of(context).primaryColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'No scam trends published yet.\nCheck back soon.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicCard(
    BuildContext context,
    Map<String, dynamic> topic,
    String lang,
  ) {
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
                  backgroundColor:
                      Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  child: Icon(
                    _iconFor(topic['icon'] as String?),
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    topic['title'] as String,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              topic['desc'] as String,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                Translations.get('read_more', lang),
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsSection(BuildContext context) {
    final tools = [
      {
        'title': 'Check Link Safety',
        'icon': Icons.link,
        'action': _checkLinkSafety,
      },
      {
        'title': 'Report to Authorities',
        'icon': Icons.local_police,
        'action': _reportToAuthorities,
      },
      {
        'title': 'Security Settings',
        'icon': Icons.security,
        'action': _openSecuritySettings,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Important Tools',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
              child: Icon(
                tool['icon'] as IconData,
                size: 32,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tool['title'] as String,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportOption {
  final String label;
  final String url;
  final IconData icon;
  const _ReportOption({
    required this.label,
    required this.url,
    required this.icon,
  });
}
