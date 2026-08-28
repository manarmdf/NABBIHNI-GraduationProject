import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../location/osm_place_service.dart' show OsmPlaceService, NearbyPlace;
import '../location/user_locations_service.dart';
import '../shared/constants.dart';
import '../shared/habit_helper.dart';
import '../shared/notifications.dart';
import 'add_reminder_sheet.dart';
import 'reminder_model.dart';
import 'widgets/nearby_banner.dart' show NearbyBannerList;
import 'widgets/reminder_card.dart';

/// شاشة التذكيرات الرئيسية — تعرض جميع التذكيرات مع فلاتر وأزرار إضافة.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Reminder> _reminders = [];
  StreamSubscription<QuerySnapshot>? _sub;
  Set<String> _nearbyPlaceTypes = {};
  List<Reminder> _nearbyMatches = [];
  List<NearbyPlace> _nearbyPlaces = [];
  Map<String, UserLocation> _personalLocs = {};

  final HabitHelper _habitHelper = HabitHelper();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;
  bool _isListening = false;
  String _filter = 'Active';
  String _priorityFilter = 'All';
  String _categoryFilter = 'All';

  static const _filters = ['Active', 'Completed'];
  static const _priorityOptions = ['All', 'high', 'medium', 'low'];
  static const _categoryOptions = ['All', 'personal', 'work', 'family', 'other'];

  /// مرجع مجموعة التذكيرات في Firestore للمستخدم الحالي.
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid ?? 'anonymous')
          .collection('reminders');

  // ── دورة الحياة ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _speech.initialize(
      onError: (val) {
        if (mounted && _isListening) setState(() => _isListening = false);
      },
      onStatus: (val) {
        if ((val == 'done' || val == 'notListening') && mounted && _isListening) {
          setState(() => _isListening = false);
        }
      },
    ).then((ok) {
      if (mounted) setState(() => _speechAvailable = ok);
    });
    _tts.setLanguage('en-US');
    _habitHelper.init();

    _sub = _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _reminders = snap.docs.map((d) => Reminder.fromMap(d.data())).toList();
      });
      _matchNearbyReminders();
    });

    _checkNearbyPlaces();
    UserLocationsService.locationsStream().listen((locs) {
      if (!mounted) return;
      setState(() => _personalLocs = locs);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tts.stop();
    _habitHelper.dispose();
    super.dispose();
  }

  /// ينطق النص باستخدام محرّك تحويل النص إلى كلام.
  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  // ── الموقع و OSM ──────────────────────────────────────────────────────

  /// يفحص الأماكن القريبة من موقع المستخدم الحالي عبر OSM ومواقعه الشخصية.
  Future<void> _checkNearbyPlaces() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final osmPlaces = await OsmPlaceService.getNearbyPlaces(
        pos.latitude, pos.longitude,
        radiusMeters: AppConfig.nearbyRadiusMeters,
      );
      final allPlaces = List<NearbyPlace>.from(osmPlaces);
      final types = osmPlaces.map((p) => p.type).toSet();

      for (final entry in _personalLocs.entries) {
        final loc = entry.value;
        if (loc.lat == null || loc.lng == null) continue;
        final dist = UserLocationsService.distanceMeters(
          pos.latitude, pos.longitude, loc.lat!, loc.lng!,
        );
        if (dist <= AppConfig.nearbyRadiusMeters) {
          final displayName = (loc.name != null && loc.name!.isNotEmpty)
              ? loc.name!
              : entry.key;
          allPlaces.add(NearbyPlace(
            type: entry.key, name: displayName,
            lat: loc.lat!, lng: loc.lng!, distanceMeters: dist,
          ));
          types.add(entry.key);
        }
      }
      if (!mounted) return;
      setState(() {
        _nearbyPlaceTypes = types;
        _nearbyPlaces = allPlaces;
      });
      _matchNearbyReminders();
    } catch (e, st) {
      debugPrint('[Reminders] Nearby ERROR: $e\n$st');
    }
  }

  /// يُطابق التذكيرات النشطة مع أنواع الأماكن القريبة.
  void _matchNearbyReminders() {
    if (_nearbyPlaceTypes.isEmpty) {
      if (_nearbyMatches.isNotEmpty) setState(() => _nearbyMatches = []);
      return;
    }
    final matches = _reminders
        .where((r) =>
            !r.isCompleted &&
            r.locationType != null &&
            _nearbyPlaceTypes.contains(r.locationType))
        .toList();
    if (mounted) setState(() => _nearbyMatches = matches);
  }

  // ── عمليات CRUD ────────────────────────────────────────────────────────

  /// يولّد معرّف إشعار فريد من معرّف التذكير.
  int _notifId(String id) => id.hashCode.abs() % 2000000000;

  /// يضيف تذكيراً جديداً إلى Firestore ويجدول إشعاراً إن وُجد تاريخ.
  Future<void> _addReminder(Reminder r) async {
    await _col.doc(r.id).set(r.toMap());
    if (r.dateTime != null) {
      await scheduleNotification(
          id: _notifId(r.id), title: r.title, scheduledDate: r.dateTime!);
    }
  }

  /// يحدّث تذكيراً موجوداً ويعيد جدولة إشعاره.
  Future<void> _updateReminder(Reminder r) async {
    await _col.doc(r.id).update(r.toMap());
    await cancelNotification(_notifId(r.id));
    if (r.dateTime != null && r.dateTime!.isAfter(DateTime.now())) {
      await scheduleNotification(
          id: _notifId(r.id), title: r.title, scheduledDate: r.dateTime!);
    }
  }

  /// يُبدّل حالة إكمال التذكير.
  Future<void> _toggleComplete(Reminder r) async =>
      _col.doc(r.id).update({'isCompleted': !r.isCompleted});

  /// يحذف التذكير ويلغي إشعاره.
  Future<void> _delete(Reminder r) async {
    await _col.doc(r.id).delete();
    await cancelNotification(_notifId(r.id));
  }

  /// يؤجّل التذكير بعدد الدقائق المحدد ويعيد جدولة الإشعار.
  Future<void> _snoozeReminder(Reminder r) async {
    final minutes = r.snoozeDurationMinutes;
    await snoozeNotification(id: _notifId(r.id), title: r.title, minutes: minutes);
    final newTime = DateTime.now().add(Duration(minutes: minutes));
    await _col.doc(r.id).update({'dateTime': newTime.toIso8601String()});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم التأجيل $minutes دقيقة')),
    );
  }

  // ── الأوراق السفلية ────────────────────────────────────────────────────

  /// يفتح ورقة إضافة تذكير جديد.
  Future<void> _openAddSheet({
    String prefill = '',
    DateTime? prefillDate,
    String? prefillCategory,
  }) async {
    final reminder = await showModalBottomSheet<Reminder>(
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
        habitHelper: _habitHelper,
        personalLocs: _personalLocs,
      ),
    );
    if (reminder != null) {
      await _addReminder(reminder);
      if (prefill.isNotEmpty) {
        final when = reminder.dateTime != null
            ? ' at ${DateFormat('hh:mm a').format(reminder.dateTime!)}'
            : '';
        await _speak('Reminder saved: ${reminder.title}$when');
      }
    }
  }

  /// يفتح ورقة تعديل تذكير موجود.
  Future<void> _openEditSheet(Reminder r) async {
    final updated = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AddReminderSheet(
        prefill: r.title,
        prefillDate: r.dateTime,
        prefillCategory: r.category,
        prefillLocationType: r.locationType,
        existingId: r.id,
        speech: _speech,
        speechAvailable: _speechAvailable,
        habitHelper: _habitHelper,
        personalLocs: _personalLocs,
      ),
    );
    if (updated != null) await _updateReminder(updated);
  }

  /// يبدأ الإضافة السريعة بالصوت — يختار اللغة ثم يستمع.
  Future<void> _startVoiceQuickAdd() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available')),
      );
      return;
    }
    final lang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Language / اختر اللغة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('English'),
              leading: const Icon(Icons.language),
              onTap: () => Navigator.pop(ctx, 'en'),
            ),
            ListTile(
              title: const Text('العربية'),
              leading: const Icon(Icons.language),
              onTap: () => Navigator.pop(ctx, 'ar'),
            ),
          ],
        ),
      ),
    );
    if (lang == null || !mounted) return;

    final String locale = lang == 'ar' ? 'ar_SA' : 'en_US';
    if (!mounted) return;
    setState(() => _isListening = true);
    try {
      await _speech.listen(
        localeId: locale,
        onResult: (result) {
          if (result.finalResult) {
            if (mounted) setState(() => _isListening = false);
            _openAddSheet(prefill: result.recognizedWords);
          }
        },
      );
    } catch (e) {
      debugPrint('Speech listen error: $e');
      if (mounted) setState(() => _isListening = false);
    }
  }

  // ── فلترة القائمة ──────────────────────────────────────────────────────

  /// يُرجع التذكيرات بعد تطبيق جميع الفلاتر.
  List<Reminder> get _filtered {
    return _reminders.where((r) {
      if (_filter == 'Completed' && !r.isCompleted) return false;
      if (_filter == 'Active' && r.isCompleted) return false;
      if (_priorityFilter != 'All' && r.priority != _priorityFilter) return false;
      if (_categoryFilter != 'All' && r.category != _categoryFilter) return false;
      return true;
    }).toList();
  }

  bool get _filtersActive =>
      _priorityFilter != 'All' || _categoryFilter != 'All';

  /// يُجمّع التذكيرات حسب الفترة الزمنية (اليوم / غداً / قادم / متأخر).
  List<Reminder> _group(String groupName) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    return _filtered.where((r) {
      if (r.dateTime == null) return groupName == 'Uncompleted';
      final d = DateTime(r.dateTime!.year, r.dateTime!.month, r.dateTime!.day);
      return switch (groupName) {
        'Today'       => d == today,
        'Tomorrow'    => d == tomorrow,
        'Upcoming'    => d.isAfter(tomorrow),
        'Uncompleted' => d.isBefore(today) && !r.isCompleted,
        _             => false,
      };
    }).toList();
  }

  // ── بناء الواجهة ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('All Reminders'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.filter_list_rounded),
                if (_filtersActive)
                  Positioned(
                    right: -2, top: -2,
                    child: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _openFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterRow(),
          if (_filtersActive) _buildActiveFilterChips(),
          Expanded(child: _buildBody()),
          if (_isListening) _buildListeningBar(),
        ],
      ),
      floatingActionButton: _buildFABs(),
    );
  }

  /// يبني صف اختيار الفلتر (نشط / مكتمل).
  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: _filters.map((f) {
          final selected = f == _filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
              side: BorderSide(
                  color: selected ? AppColors.primary : const Color(0xFFE5E7EB)),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  /// يعرض شرائح الفلاتر النشطة مع زر إزالة.
  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];
    if (_priorityFilter != 'All') {
      chips.add(_filterChip(
        label: 'Priority: ${_capitalize(_priorityFilter)}',
        onClear: () => setState(() => _priorityFilter = 'All'),
      ));
    }
    if (_categoryFilter != 'All') {
      chips.add(_filterChip(
        label: 'Category: ${_capitalize(_categoryFilter)}',
        onClear: () => setState(() => _categoryFilter = 'All'),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  Widget _filterChip({required String label, required VoidCallback onClear}) {
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
          Text(label, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent,
          )),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }

  /// يفتح ورقة الفلاتر المتقدمة (أولوية + فئة).
  Future<void> _openFilterSheet() async {
    String tempPriority = _priorityFilter;
    String tempCategory = _categoryFilter;
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
              Row(children: [
                const Text('Filter Reminders', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary,
                )),
                const Spacer(),
                TextButton(
                  onPressed: () => setLocal(() { tempPriority = 'All'; tempCategory = 'All'; }),
                  child: const Text('Reset'),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('Priority', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
              )),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _priorityOptions.map((p) {
                return ChoiceChip(
                  label: Text(_capitalize(p)), selected: tempPriority == p,
                  onSelected: (_) => setLocal(() => tempPriority = p),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  showCheckmark: false,
                );
              }).toList()),
              const SizedBox(height: 16),
              const Text('Category', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
              )),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _categoryOptions.map((c) {
                return ChoiceChip(
                  label: Text(_capitalize(c)), selected: tempCategory == c,
                  onSelected: (_) => setLocal(() => tempCategory = c),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  showCheckmark: false,
                );
              }).toList()),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: () {
                  setState(() { _priorityFilter = tempPriority; _categoryFilter = tempCategory; });
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply'),
              )),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// يبني محتوى الجسم الرئيسي — رسالة فارغة أو قائمة التذكيرات.
  Widget _buildBody() {
    if (_filtered.isEmpty && _nearbyMatches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 64, color: AppColors.textSecondary.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(
              _filter == 'Completed'
                  ? 'No completed reminders yet.'
                  : 'No reminders yet.\nTap + to add one.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (_nearbyMatches.isNotEmpty)
          NearbyBannerList(
            nearbyPlaces: _nearbyPlaces, reminders: _nearbyMatches, onTap: _openEditSheet,
          ),
        _buildGroup('Today'),
        _buildGroup('Tomorrow'),
        _buildGroup('Upcoming'),
        _buildGroup('Uncompleted'),
        const SizedBox(height: 80),
      ],
    );
  }

  /// يعرض شريط "جارٍ الاستماع" أثناء التسجيل الصوتي.
  Widget _buildListeningBar() {
    return Container(
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_rounded, color: AppColors.accent),
          SizedBox(width: 8),
          Text('Listening...', style: TextStyle(
              color: AppColors.accent, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// يبني أزرار الإجراء العائمة (إضافة + ميكروفون).
  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_speechAvailable)
          FloatingActionButton(
            heroTag: 'mic', mini: true,
            backgroundColor: AppColors.accent, foregroundColor: Colors.white,
            onPressed: _startVoiceQuickAdd,
            child: const Icon(Icons.mic_rounded),
          ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'add',
          onPressed: () => _openAddSheet(),
          backgroundColor: AppColors.primary, foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Add Reminder'),
        ),
      ],
    );
  }

  /// يبني مجموعة تذكيرات بعنوان (اليوم / غداً / قادم / متأخر).
  Widget _buildGroup(String title) {
    final items = _group(title);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(width: 4, height: 16, decoration: BoxDecoration(
              color: AppColors.primary, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
        ),
        ...items.map((r) => ReminderCard(
              reminder: r,
              onToggle: () => _toggleComplete(r),
              onDelete: () => _delete(r),
              onSpeak: () => _speak(r.title),
              onEdit: () => _openEditSheet(r),
              onSnooze: () => _snoozeReminder(r),
            )),
      ],
    );
  }
}
