import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ScamTrendDetailScreen extends StatelessWidget {
  final Map<String, dynamic> topic;

  const ScamTrendDetailScreen({super.key, required this.topic});

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

  List<String> _toStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;

    final String title = topic['title'] as String? ?? 'Alert';
    final String desc = topic['desc'] as String? ?? '';
    final String? iconKey = topic['icon'] as String?;
    final String? category = topic['category'] as String?;
    final List<String> tips = _toStringList(topic['tips']);
    final List<String> warningSigns = _toStringList(topic['warning_signs']);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF0A2D6E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            _iconFor(iconKey),
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                        if (category != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              category.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Alert badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Scam Alert',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Description
                  _SectionHeader(
                    icon: Icons.info_outline,
                    label: 'What You Need to Know',
                    color: primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    desc,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
                  ),

                  // Warning signs
                  if (warningSigns.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _SectionHeader(
                      icon: Icons.error_outline,
                      label: 'Warning Signs',
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(height: 12),
                    ...warningSigns.map(
                      (sign) => _BulletItem(
                        text: sign,
                        icon: Icons.chevron_right,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],

                  // Tips / how to stay safe
                  if (tips.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _SectionHeader(
                      icon: Icons.shield_outlined,
                      label: 'How to Stay Safe',
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(height: 12),
                    ...tips.map(
                      (tip) => _BulletItem(
                        text: tip,
                        icon: Icons.check_circle_outline,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],

                  const SizedBox(height: 36),

                  // Report button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _reportScam(context),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Report This Scam Type'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _shareAlert(context, title, desc),
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share This Alert'),
                      style: FilledButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () => _copyAlert(context, title, desc),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('Copy Text'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reportScam(BuildContext context) async {
    final options = [
      _ReportOption('IC3 (USA – Cybercrime)', 'https://www.ic3.gov/complaint', Icons.gavel),
      _ReportOption('SAPS (South Africa)',
          'https://www.saps.gov.za/services/crimestop.php', Icons.local_police),
      _ReportOption('BOCRA (Botswana)',
          'https://www.bocra.org.bw/report-cyber-related-complaint', Icons.public),
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
                leading:
                    Icon(opt.icon, color: Theme.of(ctx).primaryColor),
                title: Text(opt.label),
                trailing:
                    const Icon(Icons.open_in_new, size: 18),
                onTap: () async {
                  Navigator.pop(ctx);
                  final uri = Uri.parse(opt.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
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

  Future<void> _shareAlert(
      BuildContext context, String title, String desc) async {
    final text = '⚠️ Scam Alert: $title\n\n$desc\n\n— Shared via SafeText';
    await Share.share(text, subject: 'Scam Alert: $title');
  }

  Future<void> _copyAlert(
      BuildContext context, String title, String desc) async {
    final text = '⚠️ Scam Alert: $title\n\n$desc\n\n— Shared via SafeText';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert text copied to clipboard.')),
      );
    }
  }
}

// ── Shared small widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _BulletItem({
    required this.text,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportOption {
  final String label;
  final String url;
  final IconData icon;
  const _ReportOption(this.label, this.url, this.icon);
}
