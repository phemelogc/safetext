/// Offline keyword-based SMS classifier.
/// Used as fallback when the FastAPI backend is unreachable.
/// Returns confidence 0.75 for flagged messages, 0.15 for clean ones.
// ignore_for_file: unintended_html_in_doc_comment
class OfflineClassifier {
  static const _urgentWords = [
    'urgent', 'immediately', 'account suspended', 'verify now',
    'click here', 'limited time',
  ];

  static const _prizeWords = [
    'you have won', 'claim your prize', 'congratulations you', 'free gift',
  ];

  // Botswana-specific impersonation bait
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

  /// Classify [message] locally without network.
  /// Returns a map with keys: flagged (bool), confidence (double),
  /// tags (List<String>), explanation (String).
  static Map<String, dynamic> classify(String message) {
    final lower = message.toLowerCase();
    final tags = <String>[];

    if (_urgentWords.any((w) => lower.contains(w))) tags.add('urgency');
    if (_prizeWords.any((w) => lower.contains(w))) tags.add('prize_bait');
    if (_botswanaContext.any((w) => lower.contains(w))) tags.add('impersonation');
    if (_setswanaBait.any((w) => lower.contains(w))) tags.add('setswana_bait');
    if (_credentialHarvest.any((w) => lower.contains(w))) tags.add('credential_harvest');
    if (_suspiciousLinkKeywords.any((w) => lower.contains(w)) ||
        _urlRegex.hasMatch(message)) {
      tags.add('phishing_link');
    }

    // Always include the offline marker
    tags.add('offline_filter');

    final flagged = tags.length > 1; // flagged only if real tags detected beyond offline_filter
    final confidence = flagged ? 0.75 : 0.15;

    final detectedTags = tags.where((t) => t != 'offline_filter').toList();
    final explanation = flagged
        ? 'Flagged by offline keyword filter (no network). '
          'Suspicious patterns found: ${detectedTags.join(', ')}.'
        : 'No suspicious patterns detected (offline analysis).';

    return {
      'flagged': flagged,
      'confidence': confidence,
      'tags': tags,
      'explanation': explanation,
    };
  }
}
