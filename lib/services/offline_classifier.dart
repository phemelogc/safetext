// Keyword-based SMS classifier used when the FastAPI backend is unreachable.
// Flagged messages get confidence 0.75; clean messages get 0.15.
// All results include the 'offline_filter' tag so the UI can indicate this.

class OfflineClassifier {
  static const _urgentWords = [
    'urgent', 'immediately', 'account suspended', 'verify now',
    'click here', 'limited time',
  ];
  static const _prizeWords = [
    'you have won', 'claim your prize', 'congratulations you', 'free gift',
  ];
  // Botswana-specific brand and government names used in impersonation scams.
  static const _botswanaContext = [
    'fnb botswana', 'stanbic', 'mascom', 'orange botswana', 'btc', 'smega',
    'government grant', 'dpsm',
  ];
  static const _setswanaBait = [
    'o nnile le morero', 'bua le rona', 'o fitlhelela',
  ];
  static const _credentialHarvest = [
    'enter your pin', 'confirm your password', 'your otp is', 'send your id',
  ];
  static const _suspiciousLinkKeywords = [
    'bit.ly', 'tinyurl', 't.co', 'goo.gl', 'ow.ly',
    'verify-now', 'secure-login', 'account-suspended',
    'gov-payments', 'relief-fund',
  ];
  static final _urlRegex = RegExp(r'https?://\S+', caseSensitive: false);

  static Map<String, dynamic> classify(String message) {
    final lower = message.toLowerCase();
    final tags = <String>[];

    if (_urgentWords.any(lower.contains)) tags.add('urgency');
    if (_prizeWords.any(lower.contains)) tags.add('prize_bait');
    if (_botswanaContext.any(lower.contains)) tags.add('impersonation');
    if (_setswanaBait.any(lower.contains)) tags.add('setswana_bait');
    if (_credentialHarvest.any(lower.contains)) tags.add('credential_harvest');
    if (_suspiciousLinkKeywords.any(lower.contains) || _urlRegex.hasMatch(message)) {
      tags.add('phishing_link');
    }

    tags.add('offline_filter');

    final flagged = tags.length > 1;
    final detectedTags = tags.where((t) => t != 'offline_filter').toList();

    return {
      'flagged': flagged,
      'confidence': flagged ? 0.75 : 0.15,
      'tags': tags,
      'explanation': flagged
          ? 'Flagged by offline keyword filter. Patterns: ${detectedTags.join(', ')}.'
          : 'No suspicious patterns detected (offline analysis).',
    };
  }
}
