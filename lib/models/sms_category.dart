enum SmsCategory { people, business, suspicious }

extension SmsCategoryX on SmsCategory {
  String get label {
    switch (this) {
      case SmsCategory.people:
        return 'People';
      case SmsCategory.business:
        return 'Business';
      case SmsCategory.suspicious:
        return 'Suspicious';
    }
  }
}
