/// Base URL for the SafeText backend. Change for localhost or another host.
const String apiBaseUrl = 'http://192.168.197.1:8000';

String get predictUrl => '$apiBaseUrl/predict';
String get feedbackUrl => '$apiBaseUrl/feedback';
