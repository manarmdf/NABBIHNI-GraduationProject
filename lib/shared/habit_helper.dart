import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// نتيجة التوقع ثنائي الرأس من نموذج العادات.
/// `locationType` يكون null عندما يكون أفضل تخمين هو "none".
class HabitSuggestion {
  final String category;
  final double confidence;
  final String? locationType;
  final double locationConfidence;
  final String message;
  final String suggestedTitle;

  HabitSuggestion({
    required this.category,
    required this.confidence,
    required this.message,
    required this.suggestedTitle,
    this.locationType,
    this.locationConfidence = 0.0,
  });
}

/// يُحمّل نموذج TFLite للعادات ويتوقع فئة التذكير ونوع الموقع المستهدف.
///
/// معمارية النموذج: جذع مشترك 128→64 مع رأسين softmax.
/// المدخلات: 4 قيم زمنية دورية + أعلام كلمات مفتاحية ثنائية اللغة.
class HabitHelper {
  Interpreter? _interpreter;
  List<String> _categories     = const ['personal', 'work', 'family', 'other'];
  List<String> _locationTypes  = const [
    'none', 'pharmacy', 'grocery', 'work', 'home', 'gym', 'hospital',
    'bank', 'store', 'restaurant', 'cafe', 'school',
  ];
  List<String> _vocabulary     = [];
  Map<String, int> _vocabIdx   = {};
  int _catOutIndex = 0;
  int _locOutIndex = 1;
  bool _ready = false;

  /// يُهيئ النموذج بتحميل الملفات والمفردات من assets.
  Future<void> init() async {
    try {
      _interpreter =
          await Interpreter.fromAsset('assets/models/model.tflite');

      _categories = (json.decode(
        await rootBundle.loadString('assets/models/categories.json'),
      ) as List).cast<String>();

      _locationTypes = (json.decode(
        await rootBundle.loadString('assets/models/location_types.json'),
      ) as List).cast<String>();

      _vocabulary = (json.decode(
        await rootBundle.loadString('assets/models/vocabulary.json'),
      ) as List).cast<String>();
      _vocabIdx = {
        for (var i = 0; i < _vocabulary.length; i++) _vocabulary[i]: i,
      };

      // Resolve which output tensor is which head by their last-dim size.
      final outTensors = _interpreter!.getOutputTensors();
      int? catIdx;
      int? locIdx;
      for (var i = 0; i < outTensors.length; i++) {
        final lastDim = outTensors[i].shape.last;
        if (lastDim == _categories.length)    catIdx = i;
        if (lastDim == _locationTypes.length) locIdx = i;
      }
      if (catIdx == null) {
        throw StateError(
            'TFLite has no category-shaped output — regenerate model.tflite');
      }
      _catOutIndex = catIdx;
      _locOutIndex = locIdx ?? -1;

      _ready = true;
      debugPrint('[HabitHelper] ready — vocab=${_vocabulary.length} '
          'cats=$_categories locs=$_locationTypes '
          'catIdx=$_catOutIndex locIdx=$_locOutIndex');
    } catch (e) {
      debugPrint('[HabitHelper] init FAILED: $e');
      _ready = false;
    }
  }

  // خريطة المرادفات — تُستخدم فقط لتفعيل أعلام المفردات وليس لتعيين التسميات.
  static const _synonyms = <String, List<String>>{
    // ── English ─────────────────────────────────────────────────────────────
    'work':        ['meeting', 'task', 'project'],
    'working':     ['meeting', 'task', 'project'],
    'office':      ['meeting', 'task'],
    'company':     ['meeting', 'task'],
    'job':         ['meeting', 'task'],
    'class':       ['lecture', 'study'],
    'classes':     ['lecture', 'study'],
    'university':  ['lecture', 'study', 'exam'],
    'assignment':  ['homework', 'submit'],
    'thesis':      ['project', 'study'],
    'interview':   ['meeting'],
    'conference':  ['meeting'],
    'seminar':     ['lecture'],
    'tutorial':    ['lecture', 'study'],
    'test':        ['exam'],
    'run':         ['exercise'],
    'running':     ['exercise'],
    'jog':         ['exercise'],
    'jogging':     ['exercise'],
    'workout':     ['exercise', 'gym'],
    'sport':       ['exercise', 'gym'],
    'sports':      ['exercise', 'gym'],
    'swim':        ['exercise'],
    'yoga':        ['exercise', 'meditation'],
    'cycling':     ['exercise'],
    'hiking':      ['exercise'],
    'walking':     ['exercise'],
    'stretching':  ['exercise'],
    'eat':         ['dinner', 'lunch'],
    'eating':      ['dinner', 'lunch'],
    'breakfast':   ['lunch', 'cook'],
    'meal':        ['dinner', 'lunch', 'cook'],
    'cooking':     ['cook'],
    'baking':      ['cook', 'bakery'],
    'recipe':      ['cook'],
    'prepare':     ['cook'],
    'shop':        ['shopping', 'store'],
    'market':      ['groceries', 'store'],
    'supermarket': ['groceries', 'store'],
    'purchase':    ['buy', 'shopping'],
    'order':       ['buy', 'store'],
    'grocery':     ['groceries'],
    'pick':        ['pickup'],
    'package':     ['pickup'],
    'parcel':      ['pickup'],
    'deliver':     ['pickup'],
    'delivery':    ['pickup'],
    'drive':       ['car'],
    'driving':     ['car'],
    'garage':      ['fix', 'car'],
    'repair':      ['fix'],
    'maintenance': ['fix'],
    'medicine':    ['medication', 'pharmacy'],
    'drug':        ['pharmacy'],
    'drugstore':   ['pharmacy'],
    'clinic':      ['doctor', 'hospital'],
    'dentist':     ['doctor', 'appointment'],
    'pill':        ['medication', 'pharmacy'],
    'prescription':['medication', 'pharmacy'],
    'refill':      ['medication', 'pharmacy'],
    'checkup':     ['doctor', 'appointment'],
    'children':    ['kids', 'family'],
    'son':         ['kids', 'family'],
    'daughter':    ['kids', 'family'],
    'wife':        ['family'],
    'husband':     ['family'],
    'parent':      ['family', 'visit'],
    'parents':     ['family', 'visit'],
    'brother':     ['family'],
    'sister':      ['family'],
    'uncle':       ['family'],
    'aunt':        ['family'],
    'cousin':      ['family'],
    'grandma':     ['family', 'visit'],
    'grandpa':     ['family', 'visit'],
    'grandmother': ['family', 'visit'],
    'grandfather': ['family', 'visit'],
    'relatives':   ['family', 'visit'],
    'mom':         ['family', 'call'],
    'dad':         ['family', 'call'],
    'money':       ['pay', 'bank'],
    'payment':     ['pay', 'bank'],
    'bill':        ['pay'],
    'bills':       ['pay'],
    'transfer':    ['bank', 'pay'],
    'atm':         ['bank'],
    'deposit':     ['bank', 'pay'],
    'withdraw':    ['bank'],
    'tax':         ['pay'],
    'rent':        ['pay'],
    'insurance':   ['pay'],
    'cleaning':    ['clean'],
    'tidying':     ['clean'],
    'washing':     ['laundry', 'clean'],
    'ironing':     ['laundry'],
    // ── Arabic → activate Arabic + English vocab flags ──────────────────────
    'نادي':       ['نادي', 'gym', 'exercise'],
    'صالة':       ['صالة', 'gym'],
    'رياضة':      ['رياضة', 'exercise', 'gym'],
    'جيم':        ['جيم', 'gym'],
    'صيدلية':     ['صيدلية', 'pharmacy', 'medication'],
    'دواء':       ['دواء', 'medication', 'pharmacy'],
    'مستشفى':     ['مستشفى', 'hospital'],
    'طبيب':       ['طبيب', 'doctor', 'hospital'],
    'عيادة':      ['عيادة', 'doctor', 'hospital'],
    'خبز':        ['خبز', 'groceries', 'bread'],
    'حليب':       ['حليب', 'groceries', 'milk'],
    'بيض':        ['بيض', 'groceries', 'eggs'],
    'سوق':        ['سوق', 'groceries', 'store'],
    'بقالة':      ['بقالة', 'groceries'],
    'سوبرماركت':  ['سوبرماركت', 'groceries'],
    'محل':        ['محل', 'store'],
    'مدرسة':      ['مدرسة', 'school'],
    'جامعة':      ['جامعة', 'school', 'study', 'lecture'],
    'محاضرة':     ['محاضرة', 'lecture', 'study'],
    'امتحان':     ['امتحان', 'exam', 'study'],
    'واجب':       ['واجب', 'homework'],
    'دراسة':      ['دراسة', 'study'],
    'اجتماع':     ['اجتماع', 'meeting'],
    'مشروع':      ['مشروع', 'project'],
    'شغل':        ['شغل', 'work', 'task'],
    'عمل':        ['عمل', 'work', 'task'],
    'مكتب':       ['مكتب', 'work'],
    'عائلة':      ['عائلة', 'family'],
    'اهل':        ['اهل', 'family'],
    'اولاد':      ['اولاد', 'kids', 'family'],
    'اطفال':      ['اطفال', 'kids', 'family'],
    'ام':         ['ام', 'family'],
    'اب':         ['اب', 'family'],
    'اخ':         ['اخ', 'family'],
    'اخت':        ['اخت', 'family'],
    'مطعم':       ['مطعم', 'restaurant'],
    'قهوة':       ['قهوة', 'cafe', 'coffee'],
    'كافيه':      ['كافيه', 'cafe', 'coffee'],
    'بنك':        ['بنك', 'bank'],
    'مصرف':       ['مصرف', 'bank'],
    'صراف':       ['صراف', 'bank'],
    'فاتورة':     ['فاتورة', 'pay'],
    'دفع':        ['دفع', 'pay'],
    'منزل':       ['منزل', 'home'],
    'بيت':        ['بيت', 'home'],
    'جمعة':       ['جمعة', 'friday'],
    'تسوق':       ['تسوق', 'shopping'],
    'شراء':       ['شراء', 'buy', 'shopping'],
  };

  /// يتحقق ما إذا كانت الكلمة عربية (نطاق Unicode العربي).
  bool _isArabic(String word) {
    for (final c in word.runes) {
      if (c < 0x0600 || c > 0x06FF) return false;
    }
    return word.isNotEmpty;
  }

  /// يُجذّع الكلمات الإنجليزية. لا يفعل شيئاً للكلمات العربية.
  String _stem(String word) {
    if (_isArabic(word) || word.length <= 3) return word;
    if (word.endsWith('ies') && word.length > 4) {
      return '${word.substring(0, word.length - 3)}y';
    }
    if (word.endsWith('ing') && word.length > 5) {
      return word.substring(0, word.length - 3);
    }
    if (word.endsWith('ed') && word.length > 4) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  // مُقسّم ثنائي اللغة: يقبل الحروف اللاتينية والعربية.
  static final RegExp _tokenRe = RegExp(r'[a-z\u0600-\u06FF]+');

  /// يُشفّر العنوان إلى متجه كلمات مفتاحية ثنائي مطابق للمفردات.
  List<double> _encodeTitle(String title) {
    final vec = List.filled(_vocabulary.length, 0.0);
    if (title.isEmpty) return vec;
    final words = _tokenRe
        .allMatches(title.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    for (final w in words) {
      final idx = _vocabIdx[w];
      if (idx != null) { vec[idx] = 1.0; continue; }
      final syns = _synonyms[w];
      if (syns != null) {
        for (final s in syns) {
          final si = _vocabIdx[s];
          if (si != null) vec[si] = 1.0;
        }
        continue;
      }
      final stemmed = _stem(w);
      final si = _vocabIdx[stemmed];
      if (si != null) { vec[si] = 1.0; continue; }
      final stemSyns = _synonyms[stemmed];
      if (stemSyns != null) {
        for (final s in stemSyns) {
          final ssi = _vocabIdx[s];
          if (ssi != null) vec[ssi] = 1.0;
        }
      }
    }
    return vec;
  }

  /// يبني متجه الإدخال الكامل: 4 قيم زمنية دورية + أعلام الكلمات.
  List<double> _buildInput(int day, double hour, String title) {
    return [
      sin(2 * pi * day  / 7),
      cos(2 * pi * day  / 7),
      sin(2 * pi * hour / 24),
      cos(2 * pi * hour / 24),
      ..._encodeTitle(title),
    ];
  }

  
  HabitSuggestion? predict({int? day, double? hour, String title = ''}) {
    final now = DateTime.now();
    day  ??= now.weekday % 7;
    hour ??= now.hour + now.minute / 60.0;

    if (!_ready || _interpreter == null) return _fallback(day, hour);

    final input = [_buildInput(day, hour, title)];
    final catOut = [List.filled(_categories.length,    0.0)];
    final locOut = _locOutIndex >= 0
        ? [List.filled(_locationTypes.length, 0.0)]
        : null;
    try {
      final outputs = <int, Object>{_catOutIndex: catOut};
      if (locOut != null) outputs[_locOutIndex] = locOut;
      _interpreter!.runForMultipleInputs([input], outputs);
    } catch (e) {
      debugPrint('[HabitHelper] interpreter failed: $e');
      return _fallback(day, hour);
    }

    final (catIdx, catConf) = _argmax(catOut[0]);
    final category = _categories[catIdx];
    String? locType;
    double locConf = 0.0;
    if (locOut != null) {
      final (li, lc) = _argmax(locOut[0]);
      final t = _locationTypes[li];
      if (t != 'none') { locType = t; locConf = lc; }
    }

    final msg = _suggestTitle(category, day, hour);
    return HabitSuggestion(
      category: category,
      confidence: catConf,
      message: msg,
      suggestedTitle: msg,
      locationType: locType,
      locationConfidence: locConf,
    );
  }

  /// يُرجع جميع الفئات مرتبة حسب الاحتمال (الأعلى أولاً).
  List<HabitSuggestion> predictAll({int? day, double? hour, String title = ''}) {
    final now = DateTime.now();
    day  ??= now.weekday % 7;
    hour ??= now.hour + now.minute / 60.0;

    if (!_ready || _interpreter == null) return [_fallback(day, hour)];

    final input  = [_buildInput(day, hour, title)];
    final catOut = [List.filled(_categories.length,    0.0)];
    final locOut = _locOutIndex >= 0
        ? [List.filled(_locationTypes.length, 0.0)]
        : null;
    try {
      final outputs = <int, Object>{_catOutIndex: catOut};
      if (locOut != null) outputs[_locOutIndex] = locOut;
      _interpreter!.runForMultipleInputs([input], outputs);
    } catch (e) {
      debugPrint('[HabitHelper] predictAll failed: $e');
      return [_fallback(day, hour)];
    }

    String? topLoc;
    double  topLocConf = 0.0;
    if (locOut != null) {
      final (li, lc) = _argmax(locOut[0]);
      final t = _locationTypes[li];
      if (t != 'none') { topLoc = t; topLocConf = lc; }
    }

    final entries = <HabitSuggestion>[];
    for (var i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      final msg = _suggestTitle(cat, day, hour);
      entries.add(HabitSuggestion(
        category: cat,
        confidence: catOut[0][i],
        message: msg,
        suggestedTitle: msg,
        locationType: topLoc,
        locationConfidence: topLocConf,
      ));
    }
    entries.sort((a, b) => b.confidence.compareTo(a.confidence));
    return entries;
  }

  /// يُرجع فهرس وقيمة أكبر عنصر في القائمة.
  static (int, double) _argmax(List<double> xs) {
    var bestIdx = 0;
    var bestVal = xs[0];
    for (var i = 1; i < xs.length; i++) {
      if (xs[i] > bestVal) { bestVal = xs[i]; bestIdx = i; }
    }
    return (bestIdx, bestVal);
  }

  /// بديل احتياطي عندما لا يكون النموذج محمّلاً.
  HabitSuggestion _fallback(int day, double hour) {
    String cat;
    if (hour < 6) {
      cat = 'personal';
    } else if (hour < 14 && day < 5) {
      cat = 'work';
    } else if (hour >= 18 && hour < 21) {
      cat = 'family';
    } else {
      cat = 'other';
    }
    final title = _suggestTitle(cat, day, hour);
    return HabitSuggestion(
      category: cat,
      confidence: 0.6,
      message: title,
      suggestedTitle: title,
    );
  }

 
  static const _taskSuggestions = <String, Map<String, List<String>>>{
    'personal': {
      'early':     ['Morning Meditation', 'Take Vitamins', 'Morning Workout'],
      'morning':   ['Exercise', 'Gym Session', 'Skincare Routine', 'Morning Walk'],
      'afternoon': ['Clean House', 'Gym Workout', 'Do Laundry'],
      'evening':   ['Cook Dinner', 'Evening Workout', 'Evening Meditation'],
      'night':     ['Journal Writing', 'Take Medication', 'Read a Book'],
    },
    'work': {
      'early':     ['Check Email', 'Review Tasks'],
      'morning':   ['Team Meeting', 'Submit Report', 'Work on Project'],
      'afternoon': ['Finish Report', 'Study Session', 'Review Code', 'Prepare Presentation'],
      'evening':   ['Do Homework', 'Study for Exam', 'Submit Assignment'],
      'night':     ['Study Session', 'Finish Project', 'Submit Homework'],
    },
    'family': {
      'early':     ['Family Breakfast'],
      'morning':   ['Take Kids to School', 'Call Parents'],
      'afternoon': ['Kids Activities', 'Visit Parents', 'Family Picnic'],
      'evening':   ['Family Dinner', 'Family Gathering', 'Play with Kids'],
      'night':     ['Family Time', 'Call Mom', 'Birthday Celebration'],
    },
    'other': {
      'early':     ['Pay Bills'],
      'morning':   ['Go to Bank', 'Pay Bills', 'Buy Groceries'],
      'afternoon': ['Buy Groceries', 'Go Shopping', 'Pick Up Package', 'Go to Pharmacy'],
      'evening':   ['Run Errands', 'Go Shopping', 'Return Items'],
      'night':     ['Pay Bills', 'Car Service'],
    },
  };

  /// يقترح عنواناً بناءً على الفئة واليوم والساعة.
  String _suggestTitle(String cat, int day, double hour) {
    final h = hour.floor();
    final period = h < 6
        ? 'early'
        : h < 12
            ? 'morning'
            : h < 17
                ? 'afternoon'
                : h < 21
                    ? 'evening'
                    : 'night';
    final tasks = _taskSuggestions[cat]?[period]
        ?? _taskSuggestions[cat]?['morning']
        ?? const ['Reminder'];
    return tasks[day % tasks.length];
  }

  /// توقع مخصّص باستخدام تذكيرات المستخدم الفعلية من Firestore.
  /// أقل من minRecords → TFLite فقط | بينهما → مزيج | أكثر → بيانات المستخدم فقط.
  Future<HabitSuggestion?> predictPersonalized({
    int? day,
    double? hour,
    String title = '',
    int minRecords = 5,
    int blendThreshold = 10,
    double recencyDays = 30.0,
    double timeSigma = 1.5,
  }) async {
    final now = DateTime.now();
    day  ??= now.weekday % 7;
    hour ??= now.hour + now.minute / 60.0;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return predict(day: day, hour: hour, title: title);

    QuerySnapshot snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .get();
    } catch (_) {
      return predict(day: day, hour: hour, title: title);
    }

    final docs = snap.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((m) => m['dateTime'] != null && m['category'] != null)
        .toList();

    if (docs.length < minRecords) {
      return predict(day: day, hour: hour, title: title);
    }

    // تسجيل كثافة النواة على تذكيرات المستخدم.
    final Map<String, double> scores = {
      for (final c in _categories) c: 1.0,
    };

    for (final m in docs) {
      final dtStr = m['dateTime'] as String?;
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) continue;
      final cat = m['category'] as String? ?? 'other';

      final ageDays = now.difference(dt).inDays.toDouble();
      final recencyWeight = exp(-ageDays / recencyDays);

      final remHour = dt.hour + dt.minute / 60.0;
      var timeDiff = (remHour - hour).abs();
      if (timeDiff > 12) timeDiff = 24 - timeDiff;
      final kernel =
          exp(-(timeDiff * timeDiff) / (2 * timeSigma * timeSigma));

      scores[cat] = (scores[cat] ?? 1.0) + recencyWeight * kernel;
    }

    final total = scores.values.reduce((a, b) => a + b);
    final userProbs = scores.map((k, v) => MapEntry(k, v / total));

    // مزج مع TFLite العام عندما تكون البيانات في نطاق التصعيد.
    if (docs.length <= blendThreshold && _ready && _interpreter != null) {
      final alpha = docs.length / blendThreshold;

      final input  = [_buildInput(day, hour, title)];
      final catOut = [List.filled(_categories.length,    0.0)];
      final locOut = _locOutIndex >= 0
          ? [List.filled(_locationTypes.length, 0.0)]
          : null;
      try {
        final outputs = <int, Object>{_catOutIndex: catOut};
        if (locOut != null) outputs[_locOutIndex] = locOut;
        _interpreter!.runForMultipleInputs([input], outputs);
      } catch (_) {
        final best =
            userProbs.entries.reduce((a, b) => a.value > b.value ? a : b);
        final fbMsg = _suggestTitle(best.key, day, hour);
        return HabitSuggestion(
          category: best.key,
          confidence: best.value,
          message: fbMsg,
          suggestedTitle: fbMsg,
        );
      }

      final Map<String, double> blended = {};
      for (var i = 0; i < _categories.length; i++) {
        final c = _categories[i];
        final up = userProbs[c] ?? 0.0;
        final gp = catOut[0][i];
        blended[c] = alpha * up + (1 - alpha) * gp;
      }

      final bTotal = blended.values.reduce((a, b) => a + b);
      final bNorm  = blended.map((k, v) => MapEntry(k, v / bTotal));
      final best   = bNorm.entries.reduce((a, b) => a.value > b.value ? a : b);

      String? topLoc;
      double  topLocConf = 0.0;
      if (locOut != null) {
        final (li, lc) = _argmax(locOut[0]);
        final t = _locationTypes[li];
        if (t != 'none') { topLoc = t; topLocConf = lc; }
      }

      final msg = _suggestTitle(best.key, day, hour);
      return HabitSuggestion(
        category: best.key,
        confidence: best.value,
        message: msg,
        suggestedTitle: msg,
        locationType: topLoc,
        locationConfidence: topLocConf,
      );
    }

   
    final best = userProbs.entries.reduce((a, b) => a.value > b.value ? a : b);
    final udMsg = _suggestTitle(best.key, day, hour);
    return HabitSuggestion(
      category: best.key,
      confidence: best.value,
      message: udMsg,
      suggestedTitle: udMsg,
    );
  }

  
  void dispose() {
    _interpreter?.close();
  }
}
