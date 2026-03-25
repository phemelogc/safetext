/// Base URL for the SafeText backend. Change for localhost or another host.
const String apiBaseUrl = 'https://safetext-production.up.railway.app';

String get predictUrl => '$apiBaseUrl/predict';
String get feedbackUrl => '$apiBaseUrl/feedback';
