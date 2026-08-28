
/// نتيجة تحليل نص التذكير بالّلغة الطبيعية.
class ParsedReminder {
  final String title;
  final DateTime? dateTime;
  final String? locationType;
  final String? category;

  ParsedReminder({
    required this.title,
    this.dateTime,
    this.locationType,
    this.category,
  });
}

/// خريطة المنتج → نوع المكان. إذا احتوى عنوان التذكير على أي كلمة مفتاحية
/// يُعيَّن نوع الموقع المقابل تلقائياً.
const productMap = <String, String>{
  'milk': 'grocery',
  'bread': 'grocery',
  'panadol': 'pharmacy',
  'medicine': 'pharmacy',
  'workout': 'gym',
};

/// يحلّل نصاً بالّلغة الطبيعية (إنجليزي وعربي) ويستخرج
/// العنوان النظيف والتاريخ والوقت ونوع المكان والفئة.
ParsedReminder parseReminderText(String input) {
  var text = input.trim();
  if (text.isEmpty) return ParsedReminder(title: text);

  // اختصار خريطة المنتجات: يُفحص قبل التحليل الكامل
  final lcInput = text.toLowerCase();
  String? productLocType;
  for (final entry in productMap.entries) {
    if (lcInput.contains(entry.key)) {
      productLocType = entry.value;
      break;
    }
  }

  // تحويل الأرقام العربية/الشرقية إلى غربية
  text = _normalizeDigits(text);

  DateTime? date;
  TimeOfDay? time;
  String remaining = text;

  // حذف بادئات التذكير (ذكرني، نبهني، remind me)
  remaining = remaining.replaceFirst(
    RegExp(r'^(?:ذكرني|ذكّرني|نبهني|فكرني|remind\s+me\s+(?:to\s+)?)', caseSensitive: false),
    '',
  ).trim();

  // استخراج الوقت

  // أنماط الوقت العربية
  final arTimePatterns = [
    // الساعة 5:30 صباحا/مساء
    RegExp(r'(?:ال)?ساعة\s+(\d{1,2}):(\d{2})\s*(صباح[اً]?|مساء[ً]?)?'),
    // الساعة 5 ونص / وربع / إلا ربع
    RegExp(r'(?:ال)?ساعة\s+(\d{1,2})\s+و\s*نص(?:ف)?\s*(صباح[اً]?|مساء[ً]?)?'),
    RegExp(r'(?:ال)?ساعة\s+(\d{1,2})\s+و\s*ربع\s*(صباح[اً]?|مساء[ً]?)?'),
    RegExp(r'(?:ال)?ساعة\s+(\d{1,2})\s+إلا\s*ربع\s*(صباح[اً]?|مساء[ً]?)?'),
    // الساعة 5 صباحا/مساء
    RegExp(r'(?:ال)?ساعة\s+(\d{1,2})\s*(صباح[اً]?|مساء[ً]?)?'),
  ];

  for (final pattern in arTimePatterns) {
    final match = pattern.firstMatch(remaining);
    if (match != null) {
      var h = int.parse(match.group(1)!);
      var m = 0;

      if (pattern == arTimePatterns[0]) {
        m = int.parse(match.group(2)!);
        final ampm = match.group(3) ?? '';
        if (ampm.startsWith('مساء') && h < 12) h += 12;
        if (ampm.startsWith('صباح') && h == 12) h = 0;
      } else if (pattern == arTimePatterns[1]) {
        m = 30; // ونص
        final ampm = match.group(2) ?? '';
        if (ampm.startsWith('مساء') && h < 12) h += 12;
      } else if (pattern == arTimePatterns[2]) {
        m = 15; // وربع
        final ampm = match.group(2) ?? '';
        if (ampm.startsWith('مساء') && h < 12) h += 12;
      } else if (pattern == arTimePatterns[3]) {
        m = 45; // إلا ربع → previous hour + 45min
        h = h - 1;
        if (h < 0) h = 23;
        final ampm = match.group(2) ?? '';
        if (ampm.startsWith('مساء') && h < 12) h += 12;
      } else {
        // Simple hour
        final ampm = match.group(2) ?? '';
        if (ampm.startsWith('مساء') && h < 12) h += 12;
        if (ampm.startsWith('صباح') && h == 12) h = 0;
        // If no am/pm and hour <= 6, assume PM (common Arabic usage)
        if (ampm.isEmpty && h >= 1 && h <= 6) h += 12;
      }

      if (h < 24 && m < 60) {
        time = TimeOfDay(hour: h, minute: m);
        remaining = remaining.replaceFirst(match.group(0)!, '');
      }
      break;
    }
  }

  // أنماط الوقت الإنجليزية
  if (time == null) {
    final timePatterns = [
      RegExp(r'\b(?:at\s+)?(\d{1,2}):(\d{2})\s*(am|pm)\b', caseSensitive: false),
      RegExp(r'\b(?:at\s+)?(\d{1,2})\s*(am|pm)\b', caseSensitive: false),
      RegExp(r'\bat\s+(\d{1,2}):(\d{2})\b', caseSensitive: false),
      RegExp(r"\b(?:at\s+)?(\d{1,2})\s*o['’]?clock\b", caseSensitive: false),
    ];

    for (final pattern in timePatterns) {
      final match = pattern.firstMatch(remaining);
      if (match != null) {
        if (pattern == timePatterns[0]) {
          var h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          final ampm = match.group(3)!.toLowerCase();
          if (ampm == 'pm' && h < 12) h += 12;
          if (ampm == 'am' && h == 12) h = 0;
          time = TimeOfDay(hour: h, minute: m);
        } else if (pattern == timePatterns[1]) {
          var h = int.parse(match.group(1)!);
          final ampm = match.group(2)!.toLowerCase();
          if (ampm == 'pm' && h < 12) h += 12;
          if (ampm == 'am' && h == 12) h = 0;
          time = TimeOfDay(hour: h, minute: 0);
        } else if (pattern == timePatterns[2]) {
          final h = int.parse(match.group(1)!);
          final m = int.parse(match.group(2)!);
          if (h < 24 && m < 60) {
            time = TimeOfDay(hour: h, minute: m);
          }
        } else {
          // "5 o'clock" — assume PM if hour 1..7, else as-is
          var h = int.parse(match.group(1)!);
          if (h >= 1 && h <= 7) h += 12;
          if (h < 24) time = TimeOfDay(hour: h, minute: 0);
        }
        if (time != null) {
          remaining = remaining.replaceFirst(match.group(0)!, '');
          break;
        }
      }
    }
  }

  // أوقات بالكلمات: noon, midnight
  if (time == null) {
    final wordTime = <RegExp, TimeOfDay>{
      RegExp(r'\bnoon\b', caseSensitive: false):     const TimeOfDay(hour: 12, minute: 0),
      RegExp(r'\bmidnight\b', caseSensitive: false): const TimeOfDay(hour: 0,  minute: 0),
    };
    for (final entry in wordTime.entries) {
      final m = entry.key.firstMatch(remaining);
      if (m != null) {
        time = entry.value;
        remaining = remaining.replaceFirst(m.group(0)!, '');
        break;
      }
    }
  }

  // استخراج التواريخ
  final now = DateTime.now();

  // التواريخ النسبية العربية
  final arToday = RegExp(r'(^|[^\p{L}\p{N}])اليوم($|[^\p{L}\p{N}])', unicode: true);
  final arBeforeTomorrow = RegExp(r'بعد\s*(?:بكر[ةاه]|غد[اً]?)', unicode: true);
  final arTomorrow = RegExp(r'(^|[^\p{L}\p{N}])(?:بكر[ةاه]|غد[اً]?)($|[^\p{L}\p{N}])', unicode: true);
  // "اليوم"
  if (arToday.hasMatch(remaining)) {
    date = DateTime(now.year, now.month, now.day);
    remaining = remaining.replaceAll(arToday, ' ');
  }
  // "بعد بكرة" / "بعد غد" — must come before plain tomorrow.
  else if (arBeforeTomorrow.hasMatch(remaining)) {
    date = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
    remaining = remaining.replaceAll(arBeforeTomorrow, ' ');
  }
  // "بكرة" / "بكرا" / "غدا" / "غداً"
  else if (arTomorrow.hasMatch(remaining)) {
    date = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    remaining = remaining.replaceAll(arTomorrow, ' ');
  }
  // "بعد أسبوع" / "بعد اسبوع"
  else if (RegExp(r'بعد\s+[اأ]سبوع').hasMatch(remaining)) {
    date = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
    remaining = remaining.replaceFirst(RegExp(r'بعد\s+[اأ]سبوع'), '');
  }
  // "بعد شهر"
  else if (RegExp(r'بعد\s+شهر').hasMatch(remaining)) {
    date = DateTime(now.year, now.month + 1, now.day);
    remaining = remaining.replaceFirst(RegExp(r'بعد\s+شهر'), '');
  }
  // "بعد X يوم/أيام"
  else {
    final daysMatch = RegExp(r'بعد\s+(\d+)\s*(?:يوم|أيام|ايام)').firstMatch(remaining);
    if (daysMatch != null) {
      final days = int.parse(daysMatch.group(1)!);
      date = DateTime(now.year, now.month, now.day).add(Duration(days: days));
      remaining = remaining.replaceFirst(daysMatch.group(0)!, '');
    }
  }
  // أسماء الأيام العربية
  if (date == null) {
    const arDays = {
      'يوم السبت': 6, 'يوم الاحد': 7, 'يوم الأحد': 7, 'يوم الاثنين': 1,
      'يوم الإثنين': 1, 'يوم الثلاثاء': 2, 'يوم الاربعاء': 3,
      'يوم الأربعاء': 3, 'يوم الخميس': 4, 'يوم الجمعة': 5,
      'السبت': 6, 'الاحد': 7, 'الأحد': 7, 'الاثنين': 1, 'الإثنين': 1,
      'الثلاثاء': 2, 'الاربعاء': 3, 'الأربعاء': 3, 'الخميس': 4, 'الجمعة': 5,
    };
    for (final entry in arDays.entries) {
      if (remaining.contains(entry.key)) {
        final targetDay = entry.value;
        var diff = targetDay - now.weekday;
        if (diff <= 0) diff += 7;
        date = DateTime(now.year, now.month, now.day).add(Duration(days: diff));
        remaining = remaining.replaceFirst(entry.key, '');
        break;
      }
    }
  }

  // التواريخ الإنجليزية
  if (date == null) {
    // "today"
    if (RegExp(r'\btoday\b', caseSensitive: false).hasMatch(remaining)) {
      date = DateTime(now.year, now.month, now.day);
      remaining = remaining.replaceFirst(
        RegExp(r'\b(?:on\s+)?today\b', caseSensitive: false), '',
      );
    }
    // "tomorrow"
    else if (RegExp(r'\btomorrow\b', caseSensitive: false).hasMatch(remaining)) {
      date = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      remaining = remaining.replaceFirst(
        RegExp(r'\b(?:on\s+)?tomorrow\b', caseSensitive: false), '',
      );
    }
    // "tonight"
    else if (RegExp(r'\btonight\b', caseSensitive: false).hasMatch(remaining)) {
      date = DateTime(now.year, now.month, now.day);
      time ??= const TimeOfDay(hour: 20, minute: 0);
      remaining = remaining.replaceFirst(
        RegExp(r'\btonight\b', caseSensitive: false), '',
      );
    }
    // "after a month" / "in a month" / "next month"
    else if (RegExp(r'\b(?:after|in|next)\s+(?:a\s+)?month\b', caseSensitive: false).hasMatch(remaining)) {
      date = DateTime(now.year, now.month + 1, now.day);
      remaining = remaining.replaceFirst(
        RegExp(r'\b(?:after|in|next)\s+(?:a\s+)?month\b', caseSensitive: false), '',
      );
    }
    // "after a week" / "in a week" / "next week"
    else if (RegExp(r'\b(?:after|in|next)\s+(?:a\s+)?week\b', caseSensitive: false).hasMatch(remaining)) {
      date = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
      remaining = remaining.replaceFirst(
        RegExp(r'\b(?:after|in|next)\s+(?:a\s+)?week\b', caseSensitive: false), '',
      );
    }
    // "after X days/weeks/months" / "in X days/weeks/months"
    else {
      final relMatch = RegExp(
        r'\b(?:after|in)\s+(\d+)\s+(days?|weeks?|months?)\b',
        caseSensitive: false,
      ).firstMatch(remaining);
      if (relMatch != null) {
        final n = int.parse(relMatch.group(1)!);
        final unit = relMatch.group(2)!.toLowerCase();
        if (unit.startsWith('day')) {
          date = DateTime(now.year, now.month, now.day).add(Duration(days: n));
        } else if (unit.startsWith('week')) {
          date = DateTime(now.year, now.month, now.day).add(Duration(days: n * 7));
        } else if (unit.startsWith('month')) {
          date = DateTime(now.year, now.month + n, now.day);
        }
        remaining = remaining.replaceFirst(relMatch.group(0)!, '');
      }
    }
    // أسماء الأيام الإنجليزية
    if (date == null) {
      final dayNames = [
        'monday', 'tuesday', 'wednesday', 'thursday',
        'friday', 'saturday', 'sunday',
      ];
      final dayMatch = RegExp(
        r'\b(?:on\s+|next\s+|this\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
        caseSensitive: false,
      ).firstMatch(remaining);
      if (dayMatch != null) {
        final targetDay = dayNames.indexOf(dayMatch.group(1)!.toLowerCase()) + 1;
        var diff = targetDay - now.weekday;
        if (diff <= 0) diff += 7;
        date = DateTime(now.year, now.month, now.day).add(Duration(days: diff));
        remaining = remaining.replaceFirst(dayMatch.group(0)!, '');
      }
    }
  }

  // استخراج التواريخ الصريحة (أبريل 7، 4/7/2026)
  if (date == null) {
    final months = [
      'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december',
    ];
    final shortMonths = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];

    int monthIndex(String s) {
      final low = s.toLowerCase();
      var i = months.indexOf(low);
      if (i >= 0) return i;
      i = shortMonths.indexOf(low);
      return i;
    }

    final monthAlt =
        '${months.join("|")}|${shortMonths.join("|")}';

    // "April 7", "April 7th", "April 7 2026"
    final namedDateMatch = RegExp(
      r'\b(?:on\s+)?(' + monthAlt + r')\s+(\d{1,2})(?:st|nd|rd|th)?(?:[,\s]+(\d{4}))?\b',
      caseSensitive: false,
    ).firstMatch(remaining);
    if (namedDateMatch != null) {
      final month = monthIndex(namedDateMatch.group(1)!) + 1;
      final day = int.parse(namedDateMatch.group(2)!);
      final year = namedDateMatch.group(3) != null
          ? int.parse(namedDateMatch.group(3)!)
          : now.year;
      if (month >= 1 && day >= 1 && day <= 31) {
        var d = DateTime(year, month, day);
        if (d.isBefore(DateTime(now.year, now.month, now.day)) &&
            namedDateMatch.group(3) == null) {
          d = DateTime(year + 1, month, day);
        }
        date = d;
        remaining = remaining.replaceFirst(namedDateMatch.group(0)!, '');
      }
    }

    // "7 April" or "7th April"
    if (date == null) {
      final reverseDateMatch = RegExp(
        r'\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(' + monthAlt + r')(?:[,\s]+(\d{4}))?\b',
        caseSensitive: false,
      ).firstMatch(remaining);
      if (reverseDateMatch != null) {
        final day = int.parse(reverseDateMatch.group(1)!);
        final month = monthIndex(reverseDateMatch.group(2)!) + 1;
        final year = reverseDateMatch.group(3) != null
            ? int.parse(reverseDateMatch.group(3)!)
            : now.year;
        if (month >= 1 && day >= 1 && day <= 31) {
          var d = DateTime(year, month, day);
          if (d.isBefore(DateTime(now.year, now.month, now.day)) &&
              reverseDateMatch.group(3) == null) {
            d = DateTime(year + 1, month, day);
          }
          date = d;
          remaining = remaining.replaceFirst(reverseDateMatch.group(0)!, '');
        }
      }
    }

    // "4/7" or "4/7/2026" (M/D or M/D/YYYY) — also accept "-" or "."
    if (date == null) {
      final slashDateMatch = RegExp(
        r'\b(?:on\s+)?(\d{1,2})[\/\-\.](\d{1,2})(?:[\/\-\.](\d{2,4}))?\b',
      ).firstMatch(remaining);
      if (slashDateMatch != null) {
        final month = int.parse(slashDateMatch.group(1)!);
        final day = int.parse(slashDateMatch.group(2)!);
        var year = now.year;
        if (slashDateMatch.group(3) != null) {
          year = int.parse(slashDateMatch.group(3)!);
          if (year < 100) year += 2000;
        }
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          var d = DateTime(year, month, day);
          if (d.isBefore(DateTime(now.year, now.month, now.day)) &&
              slashDateMatch.group(3) == null) {
            d = DateTime(year + 1, month, day);
          }
          date = d;
          remaining = remaining.replaceFirst(slashDateMatch.group(0)!, '');
        }
      }
    }
  }

  // بناء التاريخ والوقت النهائي
  DateTime? result;
  if (date != null && time != null) {
    result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  } else if (date != null) {
    result = date;
  } else if (time != null) {
    result = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (result.isBefore(now)) {
      result = result.add(const Duration(days: 1));
    }
  }

  // كشف نوع المكان والفئة من الكلمات المفتاحية (على النص الأصلي)
  final lcText = text.toLowerCase();
  final locationType = productLocType ?? _detectLocationType(lcText);
  final category = _detectCategory(lcText, locationType);

  // تنظيف العنوان
  remaining = remaining
      .replaceAll(RegExp(r'\b(?:on|at|in|by)\b\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^\s*(?:on|at|in|by)\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^\s*[,.\-–—]\s*'), '')
      .replaceAll(RegExp(r'\s*[,.\-–—]\s*$'), '')
      .trim();

  // تكبير الحرف الأول (للاتينية فقط)
  if (remaining.isNotEmpty && RegExp(r'[a-z]').hasMatch(remaining[0])) {
    remaining = remaining[0].toUpperCase() + remaining.substring(1);
  }

  return ParsedReminder(
    title: remaining,
    dateTime: result,
    locationType: locationType,
    category: category,
  );
}

/// يحوّل الأرقام العربية/الشرقية (٠١٢٣٤٥٦٧٨٩) إلى غربية (0123456789).
String _normalizeDigits(String text) {
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final ch in text.runes) {
    final c = String.fromCharCode(ch);
    final idx = eastern.indexOf(c);
    if (idx >= 0) {
      buf.write(idx.toString());
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

// خريطة الكلمات المفتاحية لأنواع المواقع (إنجليزي + عربي).
// الترتيب مهم: أول نوع تتطابق كلماته يفوز.
const _locKeywords = <String, List<String>>{
  'pharmacy': [
    'pharmacy', 'pharmacist', 'drugstore', 'drug store', 'chemist',
    'medicine', 'medication', 'prescription', 'refill', 'pill', 'pills',
    'صيدلية', 'دواء', 'علاج', 'وصفة',
  ],
  'hospital': [
    'hospital', 'clinic', 'doctor', 'dentist', 'physician', 'checkup',
    'surgery', 'lab test', 'blood test', 'x-ray', 'mri', 'er',
    'مستشفى', 'عيادة', 'طبيب', 'دكتور', 'فحص', 'تحليل', 'اشعة',
  ],
  'grocery': [
    'grocery', 'groceries', 'supermarket', 'super market', 'bakery',
    'butcher', 'milk', 'bread', 'eggs', 'fruit', 'vegetable', 'vegetables',
    'fruits', 'meat', 'cheese', 'yogurt', 'rice',
    'سوبرماركت', 'بقالة', 'سوق', 'خبز', 'حليب', 'بيض', 'لحم', 'خضار',
    'فاكهة', 'فواكه', 'ارز', 'أرز', 'جبن', 'لبن', 'زبادي',
  ],
  'bank': [
    'bank', 'atm', 'deposit', 'withdraw', 'transfer money', 'cash',
    'بنك', 'مصرف', 'صراف', 'سحب', 'ايداع', 'تحويل',
  ],
  'gym': [
    'gym', 'workout', 'exercise', 'fitness', 'yoga', 'training', 'crossfit',
    'cardio', 'lift weights',
    'نادي', 'صالة', 'رياضة', 'جيم', 'تمرين', 'تدريب',
  ],
  'school': [
    'school', 'university', 'college', 'class', 'lecture', 'lesson',
    'exam', 'midterm', 'final', 'study', 'homework', 'assignment',
    'مدرسة', 'جامعة', 'كلية', 'محاضرة', 'درس', 'امتحان', 'دراسة', 'واجب',
  ],
  'restaurant': [
    'restaurant', 'dinner', 'lunch', 'kebab', 'burger', 'pizza', 'sushi',
    'shawarma',
    'مطعم', 'غداء', 'عشاء', 'برجر', 'بيتزا', 'شاورما',
  ],
  'cafe': [
    'cafe', 'café', 'coffee', 'latte', 'espresso', 'cappuccino', 'tea',
    'starbucks',
    'قهوة', 'كافيه', 'شاي', 'كوفي',
  ],
  'store': [
    'shop', 'shopping', 'mall', 'store', 'buy clothes', 'clothes',
    'electronics', 'shoes',
    'تسوق', 'محل', 'مول', 'ملابس',
  ],
  'work': [
    'office', 'meeting', 'standup', 'review', 'deadline', 'report',
    'مكتب', 'اجتماع', 'دوام', 'شغل', 'عمل',
  ],
  'home': [
    'home', 'house', 'clean house', 'laundry', 'dishes', 'cook dinner',
    'بيت', 'منزل', 'تنظيف',
  ],
};

// مُقسّم مُجمّع مسبقاً (يُبنى مرة واحدة) لتجنب بناء regex في كل استدعاء.
final RegExp _tokenizer = RegExp(r'[\p{L}\p{N}]+', unicode: true);

// الكلمات المفتاحية متعددة الكلمات تحتاج مطابقة سلسلة فرعية.
final List<MapEntry<String, String>> _locMultiKw = (() {
  final list = <MapEntry<String, String>>[];
  for (final entry in _locKeywords.entries) {
    for (final kw in entry.value) {
      if (kw.contains(' ')) {
        list.add(MapEntry(kw.toLowerCase(), entry.key));
      }
    }
  }
  return list;
})();

/// يكشف نوع الموقع من الكلمات المفتاحية في النص.
String? _detectLocationType(String lc) {
  // فحص الكلمات متعددة الكلمات أولاً
  for (final e in _locMultiKw) {
    if (lc.contains(e.key)) return e.value;
  }
  // كلمة واحدة: تقسيم مرة واحدة والتكرار حسب ترتيب الإعلان
  final tokens = <String>{};
  for (final m in _tokenizer.allMatches(lc)) {
    tokens.add(m.group(0)!);
  }
  if (tokens.isEmpty) return null;
  for (final entry in _locKeywords.entries) {
    for (final kw in entry.value) {
      if (kw.contains(' ')) continue;
      if (tokens.contains(kw.toLowerCase())) return entry.key;
    }
  }
  return null;
}

// خريطة الكلمات المفتاحية لكشف الفئة
const _categoryKeywords = <String, List<String>>{
  'work': [
    'meeting', 'work', 'project', 'office', 'deadline', 'report',
    'standup', 'email', 'invoice', 'client', 'job', 'boss', 'task',
    'اجتماع', 'شغل', 'عمل', 'مكتب', 'مشروع', 'تقرير',
  ],
  'family': [
    'family', 'mom', 'dad', 'mother', 'father', 'son', 'daughter',
    'wife', 'husband', 'kids', 'parent', 'parents', 'grandma', 'grandpa',
    'birthday', 'anniversary',
    'عائلة', 'اهل', 'أهل', 'ام', 'أم', 'اب', 'أب', 'اولاد', 'أولاد',
    'اطفال', 'أطفال', 'زوجة', 'زوج',
  ],
  'personal': [
    'gym', 'workout', 'exercise', 'meditation', 'medicine',
    'doctor', 'dentist', 'haircut', 'shower', 'sleep', 'breakfast',
    'lunch', 'dinner', 'study',
    'دواء', 'تمرين', 'رياضة',
  ],
};

/// يكشف فئة التذكير من الكلمات المفتاحية ونوع الموقع.
String? _detectCategory(String lc, String? loc) {
  // ربط الموقع بالفئة أولاً (مسار سريع)
  if (loc != null) {
    switch (loc) {
      case 'work':
      case 'school':
        return 'work';
      case 'gym':
      case 'pharmacy':
      case 'hospital':
        return 'personal';
      case 'home':
        return 'family';
      case 'grocery':
      case 'bank':
      case 'store':
      case 'restaurant':
      case 'cafe':
        return 'other';
    }
  }
  final tokens = <String>{};
  for (final m in _tokenizer.allMatches(lc)) {
    tokens.add(m.group(0)!);
  }
  if (tokens.isEmpty) return null;
  for (final entry in _categoryKeywords.entries) {
    for (final kw in entry.value) {
      if (tokens.contains(kw.toLowerCase())) return entry.key;
    }
  }
  return null;
}

/// مساعد TimeOfDay بسيط يُستخدم داخلياً في المحلّل.
class TimeOfDay {
  final int hour;
  final int minute;
  const TimeOfDay({required this.hour, required this.minute});
}
