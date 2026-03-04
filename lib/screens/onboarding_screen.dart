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
  final PageController _pageController = PageController();
  int _currentPage = 0;

  Future<void> _requestPermissions() async {
    final statuses = await [Permission.sms, Permission.phone].request();

    final smsGranted = statuses[Permission.sms]!.isGranted;

    if (!smsGranted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'SMS permission is required for SafeText to detect smishing. '
              'Please enable it in your app settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarded', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _currentPage = index),
        children: [
          _buildPage(
            'Welcome to SafeText',
            'Protect against smishing with ML-powered warnings.',
            Icons.shield,
          ),
          _buildPage(
            'Privacy First',
            'We process SMS locally where possible, but detections use a secure cloud API (data is sent temporarily for analysis). No storage.',
            Icons.lock,
          ),
          _buildPage(
            'Permissions Needed',
            'Grant SMS access to monitor and flag messages.',
            Icons.security,
            buttonText: 'Grant',
            onButtonPress: _requestPermissions,
          ),
          _buildPage(
            'Ready to Go',
            'Stay safe with real-time alerts and education.',
            Icons.check_circle,
            buttonText: 'Start',
            onButtonPress: _completeOnboarding,
          ),
        ],
      ),
      bottomNavigationBar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(4, (index) => _buildDot(index == _currentPage)),
      ),
    );
  }

  Widget _buildPage(
    String title,
    String desc,
    IconData icon, {
    String? buttonText,
    VoidCallback? onButtonPress,
  }) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 100, color: const Color(0xFF2196F3)),
          const SizedBox(height: 32),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (buttonText != null) ...[
            const SizedBox(height: 32),
            ElevatedButton(onPressed: onButtonPress, child: Text(buttonText)),
          ],
        ],
      ),
    );
  }

  Widget _buildDot(bool active) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      width: active ? 12 : 8,
      height: active ? 12 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? const Color(0xFF2196F3) : Colors.grey,
      ),
    );
  }
}
