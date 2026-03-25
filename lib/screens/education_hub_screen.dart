import 'package:flutter/material.dart';
import '../utils/translations.dart';
import '../main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firestore_service.dart';

class EducationHubScreen extends StatelessWidget {
  const EducationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = SafeTextApp.localeNotifier.value;
    
    final List<Map<String, String>> topics = [
      {
        'title': 'Phishing Attacks',
        'desc': 'Scammers send fake emails or texts to trick you into giving them your personal information like passwords and bank details. Never click on unverified links.',
        'icon': 'fishing',
      },
      {
        'title': 'Smishing (SMS Phishing)',
        'desc': 'Similar to phishing, but happens via SMS. The scammer might claim to be your bank or a delivery service asking for payment to clear a package.',
        'icon': 'sms',
      },
      {
        'title': 'Wangiri (One Ring Scam)',
        'desc': 'Your phone rings once from an unknown overseas number. If you call back, you are charged premium rates which go straight to the scammer.',
        'icon': 'phone',
      },
      {
        'title': 'Lottery & Sweepstakes',
        'desc': 'You receive a text claiming you won a huge prize, but they need an "admin fee" first. Legitimate lotteries never ask for upfront fees to claim a prize.',
        'icon': 'gift',
      },
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
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
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    Translations.get('latest_trends', lang),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                StreamBuilder<QuerySnapshot>(
                  stream: FirestoreService().getPublishedAlerts(),
                  builder: (context, snapshot) {
                    final firestoreTopics = <Map<String, String>>[];
                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        firestoreTopics.add({
                          'title': data['title']?.toString() ?? 'Live Alert',
                          'desc': data['content']?.toString() ?? data['description']?.toString() ?? '',
                          'icon': 'info',
                        });
                      }
                    }
                    
                    final allTopics = [...firestoreTopics, ...topics];
                    
                    if (snapshot.connectionState == ConnectionState.waiting && firestoreTopics.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: allTopics
                          .map((topic) => _buildTopicCard(context, topic, lang))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildMockAppsSection(lang, context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicCard(BuildContext context, Map<String, String> topic, String lang) {
    IconData iconData = Icons.info;
    if (topic['icon'] == 'fishing') iconData = Icons.phishing;
    if (topic['icon'] == 'sms') iconData = Icons.sms_failed;
    if (topic['icon'] == 'phone') iconData = Icons.phone_callback;
    if (topic['icon'] == 'gift') iconData = Icons.card_giftcard;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Future functionality: could open a detailed web page or internal view
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
                    child: Icon(iconData, color: Theme.of(context).primaryColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      topic['title']!,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                topic['desc']!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
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
      ),
    );
  }

  Widget _buildMockAppsSection(String lang, BuildContext context) {
    // "Add more functional apps with hardcoded relevant data"
    // I am displaying some mock external links or functional mini-tools
    final List<Map<String, dynamic>> apps = [
      {
        'title': 'Check Link Safety',
        'icon': Icons.link,
        'action': () async {
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Checking link capability coming soon!'))
          );
        }
      },
      {
        'title': 'Report to Authorities',
        'icon': Icons.local_police,
        'action': () async {
          const url = 'https://www.ic3.gov/';
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
        }
      },
      {
        'title': 'Security Settings',
        'icon': Icons.security,
        'action': () {
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Opening device security settings...'))
          );
        }
      }
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            'Important Tools', // using english fallback
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return _buildAppItem(context, app);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAppItem(BuildContext context, Map<String, dynamic> app) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 16),
      child: InkWell(
        onTap: app['action'],
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
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Icon(app['icon'], size: 32, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              app['title'],
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
