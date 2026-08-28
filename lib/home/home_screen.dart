import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/ocr_helper.dart' as ocr;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../authentication/auth_service.dart';
import '../location/osm_place_service.dart';
import '../reminders/reminder_model.dart';
import '../reminders/reminders_screen.dart';
import '../reminders/widgets/nearby_banner.dart' show NearbyBannerList;
import '../profile/profile_screen.dart';
import '../reminders/add_reminder_sheet.dart';
import '../shared/constants.dart';
import '../shared/habit_helper.dart';
import '../shared/notifications.dart';
import '../shared/text_parser.dart' as nlp;
import '../location/user_locations_service.dart';
import '../location/my_locations_screen.dart';
import 'activity_screen.dart';
import 'calendar_screen.dart';

// الشاشة الرئيسية: تحتوي على شريط التنقل السفلي بين أقسام التطبيق الأربعة.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    _SmartAssistantTab(),
    ActivityScreen(),
    RemindersScreen(),
    CalendarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
        ],
      ),
    );
  }
}

// تبويب المساعد الذكي: مدخل النص والصوت، اقتراحات الذكاء الاصطناعي، وتذكيرات اليوم.
class _SmartAssistantTab extends StatefulWidget {
  const _SmartAssistantTab();

  @override
  State<_SmartAssistantTab> createState() => _SmartAssistantTabState();
}

class _SmartAssistantTabState extends State<_SmartAssistantTab> {
  final _controller = TextEditingController();

  final HabitHelper _habit = HabitHelper();
  HabitSuggestion? _suggestion;
  bool _showSuggestion = true;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _speechLang = 'en';

  List<Map<String, dynamic>> _todayReminders = [];
  List<Reminder> _allReminders = [];
  StreamSubscription<QuerySnapshot>? _sub;

  String _todayPriority = 'All';
  String _todayCategory = 'All';
  static const _priorityOptions = ['All', 'high', 'medium', 'low'];
  static const _categoryOptions = [
    'All',
    'personal',
    'work',
    'family',
    'other',
  ];

  Set<String> _nearbyPlaceTypes = {};
  List<Reminder> _nearbyMatches = [];
  List<NearbyPlace> _nearbyPlaces = [];
  String _nearbyStatus = 'Waiting…';

  Map<String, UserLocation> _personalLocs = {};
  bool _showLocationOnboarding = false;

  Timer? _proximityTimer;

  // تهيئة نموذج العادات والتعرف على الكلام والاشتراك في تذكيرات اليوم والمواقع.
  @override
  void initState() {
    super.initState();
    _habit.init().then((_) async {
      final s = await _habit.predictPersonalized();
      if (mounted) {
        setState(() => _suggestion = s);
        _checkSuggestionDismissed(s);
      }
    });
    _speech
        .initialize(
          onError: (val) => debugPrint('Speech Error: $val'),
          onStatus: (val) => debugPrint('Speech Status: $val'),
        )
        .then((ok) {
          if (mounted) setState(() => _speechAvailable = ok);
        });
    _listenTodayReminders();
    _checkNearbyPlaces();
    _listenPersonalLocations();
    _maybeShowLocationOnboarding();
    _proximityTimer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => _checkNearbyPlaces(),
    );
  }

  // التحقق إن كان الاقتراح الحالي قد رُفض أو قُبل مسبقاً في نفس اليوم.
  Future<void> _checkSuggestionDismissed(HabitSuggestion? s) async {
    if (s == null) return;
    final prefs = await SharedPreferences.getInstance();
    final storedDate = prefs.getString('suggestion_dismissed_date');
    final storedTitle = prefs.getString('suggestion_dismissed_title');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (storedDate == today && storedTitle == s.suggestedTitle) {
      if (mounted) setState(() => _showSuggestion = false);
    }
  }

  // حفظ رفض الاقتراح حتى لا يظهر مرة أخرى قبل اليوم التالي.
  Future<void> _persistSuggestionDismiss() async {
    if (_suggestion == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString('suggestion_dismissed_date', today);
    await prefs.setString(
      'suggestion_dismissed_title',
      _suggestion!.suggestedTitle,
    );
  }

  // الاشتراك بتذكيرات Firestore وتصفية الخاصة باليوم الحالي فقط.
  void _listenTodayReminders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = today.add(const Duration(days: 1));

          setState(() {
            _todayReminders = snap.docs.map((d) => d.data()).where((m) {
              final dt = m['dateTime'] as String?;
              if (dt == null) return false;
              final d = DateTime.parse(dt);
              return !d.isBefore(today) && d.isBefore(tomorrow);
            }).toList();
            _allReminders = snap.docs
                .map((d) => Reminder.fromMap(d.data()))
                .where((r) => !r.isCompleted)
                .toList();
          });
          _matchNearby();
        });
  }

  // إغلاق كل الموارد عند إغلاق التبويب لتجنب تسرب الذاكرة.
  @override
  void dispose() {
    _controller.dispose();
    _sub?.cancel();
    _proximityTimer?.cancel();
    _habit.dispose();
    super.dispose();
  }

  // فحص المواقع القريبة من الجهاز عبر GPS وOverpass والمواقع الشخصية.
  Future<void> _checkNearbyPlaces() async {
    if (mounted) setState(() => _nearbyStatus = 'Checking…');
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('[Nearby] permission=$perm — aborting');
        if (mounted) {
          setState(() => _nearbyStatus = 'Location permission denied');
        }
        return;
      }

      if (mounted) setState(() => _nearbyStatus = 'Getting GPS…');
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      debugPrint('[Nearby] pos=${pos.latitude},${pos.longitude}');

      if (mounted) setState(() => _nearbyStatus = 'Querying Overpass…');
      final osmPlaces = await OsmPlaceService.getNearbyPlaces(
        pos.latitude,
        pos.longitude,
        radiusMeters: AppConfig.nearbyRadiusMeters,
      );
      final allPlaces = List<NearbyPlace>.from(osmPlaces);
      final types = osmPlaces.map((p) => p.type).toSet();
      debugPrint(
        '[Nearby] OSM returned ${osmPlaces.length} places, types=$types',
      );

      for (final entry in _personalLocs.entries) {
        final loc = entry.value;
        if (loc.lat == null || loc.lng == null) continue;
        final dist = UserLocationsService.distanceMeters(
          pos.latitude,
          pos.longitude,
          loc.lat!,
          loc.lng!,
        );
        if (dist <= AppConfig.nearbyRadiusMeters) {
          final displayName = (loc.name != null && loc.name!.isNotEmpty)
              ? loc.name!
              : entry.key;
          allPlaces.add(
            NearbyPlace(
              type: entry.key,
              name: displayName,
              lat: loc.lat!,
              lng: loc.lng!,
              distanceMeters: dist,
            ),
          );
          types.add(entry.key);
        }
      }

      if (!mounted) return;
      setState(() {
        _nearbyPlaceTypes = types;
        _nearbyPlaces = allPlaces;
      });
      _matchNearby();

      final locTypes = _allReminders
          .where((r) => r.locationType != null)
          .length;
      debugPrint(
        '[Nearby] allReminders=${_allReminders.length}, withLocType=$locTypes, matches=${_nearbyMatches.length}',
      );
      if (mounted) {
        setState(
          () => _nearbyStatus = types.isEmpty
              ? 'No place types nearby'
              : 'Types: ${types.join(", ")} | ${_nearbyMatches.length} match(es)',
        );
      }
    } catch (e, st) {
      debugPrint('[Nearby] ERROR: $e\n$st');
      if (mounted) setState(() => _nearbyStatus = 'Error: $e');
    }
  }

  // الاشتراك بمواقع المستخدم الشخصية لإعادة فحص القرب عند التغيير.
  void _listenPersonalLocations() {
    UserLocationsService.locationsStream().listen((locs) {
      if (!mounted) return;
      setState(() => _personalLocs = locs);
      _checkNearbyPlaces();
    });
  }

  // عرض لافتة تعريفية للمواقع إن لم يكن المستخدم قد أضاف أي موقع بعد.
  Future<void> _maybeShowLocationOnboarding() async {
    final hasAny = await UserLocationsService.hasAnyLocation();
    if (!hasAny && mounted) {
      setState(() => _showLocationOnboarding = true);
    }
  }

  // إخفاء لافتة تعريف المواقع.
  void _dismissLocationOnboarding() {
    setState(() => _showLocationOnboarding = false);
  }

  // مطابقة التذكيرات التي تحتوي نوع موقع مع الأنواع القريبة الحالية.
  void _matchNearby() {
    if (_nearbyPlaceTypes.isEmpty) {
      if (_nearbyMatches.isNotEmpty) setState(() => _nearbyMatches = []);
      return;
    }
    final matches = _allReminders
        .where(
          (r) =>
              r.locationType != null &&
              _nearbyPlaceTypes.contains(r.locationType),
        )
        .toList();
    if (mounted) setState(() => _nearbyMatches = matches);
  }

  // فتح ورقة إضافة/تعديل تذكير مع تمرير القيم المعبأة مسبقاً.
  Future<Reminder?> _showAddSheet({
    String prefill = '',
    DateTime? prefillDate,
    String? prefillCategory,
  }) {
    return showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddReminderSheet(
        prefill: prefill,
        prefillDate: prefillDate,
        prefillCategory: prefillCategory,
        speech: _speech,
        speechAvailable: _speechAvailable,
        habitHelper: _habit,
        personalLocs: _personalLocs,
      ),
    );
  }

  // حفظ التذكير في Firestore وجدولة إشعار محلي إن كان له موعد.
  Future<void> _saveReminder(
    Reminder reminder, {
    bool showSnack = false,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .doc(reminder.id)
        .set(reminder.toMap());

    if (reminder.dateTime != null) {
      await scheduleNotification(
        id: reminder.id.hashCode.abs() % 2000000000,
        title: reminder.title,
        scheduledDate: reminder.dateTime!,
      );
    }

    if (showSnack && mounted) {
      final dt = reminder.dateTime;
      final timeInfo = dt != null
          ? ' (${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')})'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Reminder saved: ${reminder.title}$timeInfo'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // إرسال النص المكتوب في حقل المساعد الذكي ليصبح تذكيراً جديداً.
  Future<void> _submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final reminder = await _showAddSheet(prefill: text);
    if (reminder == null) return;
    await _saveReminder(reminder, showSnack: true);
    _controller.clear();
  }

  // قبول اقتراح الذكاء الاصطناعي وفتح ورقة الإضافة بوقت افتراضي حسب التصنيف.
  Future<void> _submitFromSuggestion() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final defaultTime = switch (_suggestion?.category) {
      'work' => const TimeOfDay(hour: 9, minute: 0),
      'family' => const TimeOfDay(hour: 19, minute: 0),
      'personal' => const TimeOfDay(hour: 6, minute: 0),
      _ => const TimeOfDay(hour: 17, minute: 0),
    };
    var prefillDate = DateTime(
      today.year,
      today.month,
      today.day,
      defaultTime.hour,
      defaultTime.minute,
    );
    if (prefillDate.isBefore(now)) {
      prefillDate = prefillDate.add(const Duration(days: 1));
    }

    final reminder = await _showAddSheet(
      prefill: _suggestion?.suggestedTitle ?? '',
      prefillDate: prefillDate,
      prefillCategory: _suggestion?.category,
    );
    if (reminder == null) return;
    await _saveReminder(reminder);
  }

  // تشغيل/إيقاف التعرف على الصوت وكتابة النص المسموع في حقل الإدخال.
  // ملاحظة: لا تستخدم await مع stop() لأن ذلك يسبب انهيار الميكروفون على أندرويد.
  Future<void> _toggleMic() async {
    if (!_speechAvailable) return;

    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    final locale = _speechLang == 'ar' ? 'ar_SA' : 'en_US';

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _controller.text = '';
    });

    try {
      await _speech.listen(
        localeId: locale,
        onResult: (result) {
          if (!mounted) return;

          setState(() {
            _controller.text = result.recognizedWords;
          });

          if (result.finalResult) {
            setState(() => _isListening = false);

            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted && _controller.text.trim().isNotEmpty) {
                _submitText();
              }
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  // التقاط صورة من الكاميرا وقراءة النص منها عبر خدمة OCR ثم فتح ورقة الإضافة.
  Future<void> _scanFromCamera() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const _OcrLoadingDialog(),
    );

    String scannedText = '';
    String? error;
    try {
      scannedText = await ocr.recognizeText(picked.path);
    } catch (e) {
      error = e.toString();
      debugPrint('OCR error: $e');
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('OCR failed: $error')));
      return;
    }
    if (scannedText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No text found in image')));
      return;
    }
    final parsed = nlp.parseReminderText(scannedText);
    final title = parsed.title.isNotEmpty ? parsed.title : scannedText;
    final reminder = await _showAddSheet(
      prefill: title,
      prefillDate: parsed.dateTime,
    );
    if (reminder == null) return;
    await _saveReminder(reminder, showSnack: true);
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'there';

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [const SizedBox(width: 8), Text('$greeting, $name')],
        ),
        actions: [
          IconButton(
            icon: user?.photoURL != null
                ? CircleAvatar(
                    radius: 14,
                    backgroundImage: NetworkImage(user!.photoURL!),
                  )
                : const Icon(Icons.person_outline_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Smart Assistant',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    onSubmitted: (_) => _submitText(),
                    decoration: InputDecoration(
                      hintText: 'Remind me to...',
                      prefixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isListening
                                  ? Icons.mic_rounded
                                  : Icons.mic_none_rounded,
                              size: 20,
                              color: _isListening
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                            onPressed: _toggleMic,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.document_scanner_outlined,
                              size: 20,
                              color: AppColors.textSecondary,
                            ),
                            tooltip: 'Scan from camera',
                            onPressed: _scanFromCamera,
                          ),
                        ],
                      ),
                      prefixIconConstraints: const BoxConstraints(),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: AppColors.primary,
                        ),
                        onPressed: _submitText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text(
                        'Voice Input Lang: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'en',
                            label: Text('EN', style: TextStyle(fontSize: 12)),
                          ),
                          ButtonSegment(
                            value: 'ar',
                            label: Text('AR', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                        selected: {_speechLang},
                        onSelectionChanged: (set) {
                          setState(() => _speechLang = set.first);
                        },
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          if (_showLocationOnboarding)
            _LocationOnboardingBanner(
              onSet: () {
                _dismissLocationOnboarding();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyLocationsScreen()),
                );
              },
              onDismiss: _dismissLocationOnboarding,
            ),

          if (_showLocationOnboarding) const SizedBox(height: 16),

          if (_showSuggestion && _suggestion != null)
            _AiSuggestionBanner(
              message: _suggestion!.message,
              category: _suggestion!.category,
              onDismiss: () {
                setState(() => _showSuggestion = false);
                _persistSuggestionDismiss();
              },
              onAccept: () {
                setState(() => _showSuggestion = false);
                _persistSuggestionDismiss();
                _submitFromSuggestion();
              },
            ),

          if (_showSuggestion && _suggestion != null)
            const SizedBox(height: 16),

          GestureDetector(
            onTap: _checkNearbyPlaces,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.textSecondary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.near_me_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _nearbyStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.refresh_rounded,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          if (_nearbyMatches.isNotEmpty) ...[
            NearbyBannerList(
              nearbyPlaces: _nearbyPlaces,
              reminders: _nearbyMatches,
              onTap: (_) => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RemindersScreen()),
              ),
            ),
            const SizedBox(height: 8),
          ],

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reminders for Today',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Filter today',
                    icon: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.filter_list_rounded,
                          color: AppColors.textSecondary,
                        ),
                        if (_todayFiltersActive)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onPressed: _openTodayFilterSheet,
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RemindersScreen(),
                      ),
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ],
          ),
          if (_todayFiltersActive) _buildTodayActiveFilterChips(),
          const SizedBox(height: 8),

          if (_filteredTodayReminders.isEmpty)
            _EmptyState(
              icon: Icons.task_alt_rounded,
              message: _todayReminders.isEmpty
                  ? 'No reminders today.'
                  : 'No reminders match these filters.',
              hint: _todayReminders.isEmpty
                  ? 'Type above to add one.'
                  : 'Tap the filter icon to adjust.',
            )
          else
            ..._filteredTodayReminders.map((m) => _ReminderTile(data: m)),
        ],
      ),
    );
  }

  // هل توجد فلاتر مفعّلة على قسم تذكيرات اليوم؟
  bool get _todayFiltersActive =>
      _todayPriority != 'All' || _todayCategory != 'All';

  // قائمة تذكيرات اليوم بعد تطبيق فلاتر الأولوية والتصنيف.
  List<Map<String, dynamic>> get _filteredTodayReminders {
    return _todayReminders.where((m) {
      if (_todayPriority != 'All' &&
          (m['priority'] as String? ?? 'medium') != _todayPriority) {
        return false;
      }
      if (_todayCategory != 'All' &&
          (m['category'] as String? ?? 'other') != _todayCategory) {
        return false;
      }
      return true;
    }).toList();
  }

  // بناء شرائح تعرض الفلاتر المفعّلة حالياً على تذكيرات اليوم.
  Widget _buildTodayActiveFilterChips() {
    final chips = <Widget>[];
    if (_todayPriority != 'All') {
      chips.add(
        _todayFilterChip(
          label: 'Priority: ${_capitalize(_todayPriority)}',
          onClear: () => setState(() => _todayPriority = 'All'),
        ),
      );
    }
    if (_todayCategory != 'All') {
      chips.add(
        _todayFilterChip(
          label: 'Category: ${_capitalize(_todayCategory)}',
          onClear: () => setState(() => _todayCategory = 'All'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  // شريحة فلتر فردية مع زر إغلاق لإزالة الفلتر.
  Widget _todayFilterChip({
    required String label,
    required VoidCallback onClear,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  // فتح ورقة سفلية لاختيار فلاتر الأولوية والتصنيف لتذكيرات اليوم.
  Future<void> _openTodayFilterSheet() async {
    String tempPriority = _todayPriority;
    String tempCategory = _todayCategory;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    "Filter Today's Reminders",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setLocal(() {
                      tempPriority = 'All';
                      tempCategory = 'All';
                    }),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Priority',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _priorityOptions.map((p) {
                  final selected = tempPriority == p;
                  return ChoiceChip(
                    label: Text(_capitalize(p)),
                    selected: selected,
                    onSelected: (_) => setLocal(() => tempPriority = p),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Category',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categoryOptions.map((c) {
                  final selected = tempCategory == c;
                  return ChoiceChip(
                    label: Text(_capitalize(c)),
                    selected: selected,
                    onSelected: (_) => setLocal(() => tempCategory = c),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _todayPriority = tempPriority;
                      _todayCategory = tempCategory;
                    });
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// بطاقة عرض تذكير مختصرة مع شارة الحالة (مكتمل/متأخر/قيد الانتظار).
class _ReminderTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReminderTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final done = data['isCompleted'] as bool? ?? false;
    final dtStr = data['dateTime'] as String?;
    final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;

    final now = DateTime.now();
    final isOverdue = dt != null && dt.isBefore(now) && !done;

    final Color color;
    final String label;
    if (done) {
      color = AppColors.success;
      label = 'Completed';
    } else if (isOverdue) {
      color = AppColors.error;
      label = 'Overdue';
    } else {
      color = AppColors.warning;
      label = 'Pending';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: 14,
            decoration: done ? TextDecoration.lineThrough : null,
            color: done ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
        subtitle: dt != null
            ? Text(
                '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              )
            : null,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// لافتة اقتراح الذكاء الاصطناعي مع زر قبول وزر رفض.
class _AiSuggestionBanner extends StatelessWidget {
  final String message;
  final String category;
  final VoidCallback onDismiss;
  final VoidCallback onAccept;

  const _AiSuggestionBanner({
    required this.message,
    required this.category,
    required this.onDismiss,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onAccept,
                child: const Text(
                  'Add reminder',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// لافتة تشجع المستخدم على إضافة مواقعه الشخصية للحصول على تذكيرات بناءً على الموقع.
class _LocationOnboardingBanner extends StatelessWidget {
  final VoidCallback onSet;
  final VoidCallback onDismiss;

  const _LocationOnboardingBanner({
    required this.onSet,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Set your personal locations (home, gym, work, school) so we can remind you when you are nearby.',
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: onDismiss,
                child: const Text('Later', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onSet,
                child: const Text(
                  'Set Locations',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// عرض حالة فارغة عند عدم وجود تذكيرات مع أيقونة ورسالة وتلميح.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String hint;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              icon,
              size: 56,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// مربع حوار يظهر أثناء استخراج النص من الصورة عبر OCR.
class _OcrLoadingDialog extends StatelessWidget {
  const _OcrLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text(
              'Reading text from image…',
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
            SizedBox(height: 4),
            Text(
              'This can take up to a minute.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
