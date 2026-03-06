/// Base URL for the SafeText backend. Change for localhost or another host.
const String apiBaseUrl = 'https://safetextbackend.onrender.com';

String get predictUrl => '$apiBaseUrl/predict';
String get feedbackUrl => '$apiBaseUrl/feedback';
