/// Base URL for the SafeText backend. Change for localhost or another host.
const String apiBaseUrl = 'http://5.4.8.246:8000';

String get predictUrl => '$apiBaseUrl/predict';
String get feedbackUrl => '$apiBaseUrl/feedback';
