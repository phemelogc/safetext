import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  bool _smsPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkInitialPermission();
  }

  Future<void> _checkInitialPermission() async {
    final status = await Permission.sms.status;
    if (status.isGranted && mounted) {
      setState(() => _smsPermissionGranted = true);
    }
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (mounted) {
      setState(() => _smsPermissionGranted = status.isGranted);
      final text = status.isGranted
          ? 'SMS permission granted.'
          : 'SMS permission denied. SafeText needs access to filter messages.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 10 : 8,
          height: isActive ? 10 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? const Color(0xFF2196F3) : const Color(0xFF424242),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = <Widget>[
      _buildStep(
        step: 1,
        title: 'Most Secure App',
        description:
            'SafeText works in private mode to protect you from scam and phishing SMS before you even open them.',
        icon: Icons.shield_outlined,
        extra: null,
        bottomButton: ElevatedButton(
          onPressed: _nextPage,
          child: const Text('Next'),
        ),
      ),
      _buildStep(
        step: 2,
        title: 'Your Privacy First',
        description:
            'To detect smishing, SMS text is sent to our secure backend for analysis but never stored.\n\n'
            'No phonebook, no call logs, no media — only message text is analyzed.',
        icon: Icons.lock_outline,
        extra: null,
        bottomButton: ElevatedButton(
          onPressed: _nextPage,
          child: const Text('Next'),
        ),
      ),
      _buildStep(
        step: 3,
        title: 'Allow SMS Access',
        description:
            'SafeText reads your SMS inbox to detect suspicious messages instantly.\n\n'
            'We never send your contacts and never write or delete your SMS.',
        icon: Icons.sms_failed_outlined,
        extra: Column(
          children: [
            ElevatedButton(
              onPressed: _requestSmsPermission,
              child: const Text('Grant SMS Permission'),
            ),
            const SizedBox(height: 12),
            Text(
              _smsPermissionGranted
                  ? 'Permission granted. You can continue.'
                  : 'You can change this later in system settings.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        bottomButton: ElevatedButton(
          onPressed: _nextPage,
          child: const Text('Next'),
        ),
      ),
      _buildStep(
        step: 4,
        title: 'Ready to Protect You',
        description:
            'SafeText will watch new SMS in real time and warn you before you tap.\n\n'
            'Stay safe from fake bank alerts, prize wins, and phishing links.',
        icon: Icons.verified_user_outlined,
        extra: null,
        bottomButton: ElevatedButton(
          onPressed: _completeOnboarding,
          child: const Text('Start'),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(
              'SafeText',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Step ${_currentPage + 1} / 4',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (_, index) => pages[index],
              ),
            ),
            const SizedBox(height: 12),
            _buildDots(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStep({
    required int step,
    required String title,
    required String description,
    required IconData icon,
    required Widget? extra,
    required Widget bottomButton,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(80),
            ),
            padding: const EdgeInsets.all(28),
            child: Icon(
              icon,
              size: 64,
              color: const Color(0xFF2196F3),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (extra != null) extra,
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: bottomButton,
          ),
        ],
      ),
    );
  }
}
