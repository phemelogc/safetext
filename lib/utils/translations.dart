class Translations {
  static final Map<String, Map<String, String>> strings = {
    'en': {
      'app_title': 'SafeText',
      'search_messages': 'Search messages',
      'no_messages': 'No messages found.',
      'settings': 'Settings',
      'block_list': 'Block List',
      'allow_list': 'Allow List',
      'resync_inbox': 'Re-Sync Inbox',
      'daily_summary': 'Daily Summary Notifications',
      'theme': 'Theme',
      'language': 'Language',
      'report': 'Report',
      'ignore': 'Ignore',
      'analyzing': 'Analyzing...',
      'suspicion': 'Suspicion',
      'education_hub': 'Education Hub',
      'latest_trends': 'Latest Scamming Trends',
      'read_more': 'Read More',
      'error': 'Error analyzing.',
      'feedback_sent': 'Feedback sent successfully',
    },
    'tn': {
      'app_title': 'SafeText',
      'search_messages': 'Batla melaetsa',
      'no_messages': 'Ga gona melaetsa e e fitlhetsweng.',
      'settings': 'Dithulaganyo',
      'block_list': 'Lenaane la Kganelo',
      'allow_list': 'Lenaane la Tetlelelo',
      'resync_inbox': 'Lekgolaganya gape Lebokose',
      'daily_summary': 'Ditsibiso tsa Tsobokanyo ya Letsatsi',
      'theme': 'Mokgwa wa Tebego',
      'language': 'Puo',
      'report': 'Bega',
      'ignore': 'Itlhokomolose',
      'analyzing': 'E a Sekaseka...',
      'suspicion': 'Pelaelo',
      'education_hub': 'Lefelo la Thuto',
      'latest_trends': 'Mekgwa e Mesha ya Tsietso',
      'read_more': 'Bala mo go oketsegileng',
      'error': 'Phoso mo tshekatshekong.',
      'feedback_sent': 'Tsibogo e rometswe ka katlego',
    }
  };

  static String get(String key, String lang) {
    return strings[lang]?[key] ?? strings['en']?[key] ?? key;
  }
}
