import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../profile/profile_screen.dart';
import '../shared/constants.dart';

// شاشة التقويم: تعرض التذكيرات على شبكة شهرية مع تتبع سلسلة الإنجاز اليومية.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay;

  late final PageController _monthPageController;
  static const int _initialPage = 600;

  List<Map<String, dynamic>> _allReminders = [];
  StreamSubscription<QuerySnapshot>? _sub;

  static const Color _streakColor = Color(0xFF00316E);

  @override
  void initState() {
    super.initState();
    _monthPageController = PageController(
      initialPage: _initialPage,
      viewportFraction: 0.33,
    );
    _listen();
  }

  // الاشتراك بكل التذكيرات من Firestore لاستخدامها في رسم نقاط الأيام.
  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('reminders')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _allReminders = snap.docs.map((d) => d.data()).toList();
      });
    });
  }

  @override
  void dispose() {
    _monthPageController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  // إحصائيات الإنجاز لكل يوم مفهرسة بصيغة `yyyy-m-d`.
  Map<String, _DayStats> get _statsByDay {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in _allReminders) {
      final dtStr = r['dateTime'] as String?;
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) continue;
      final key = '${dt.year}-${dt.month}-${dt.day}';
      groups.putIfAbsent(key, () => []).add(r);
    }
    return {
      for (final e in groups.entries)
        e.key: _DayStats(
          total: e.value.length,
          completed: e.value
              .where((r) => r['isCompleted'] as bool? ?? false)
              .length,
        ),
    };
  }

  // عدد الأيام المتتالية المنتهية باليوم أو الأمس حيث أُنجزت كل المهام.
  // اليوم الحالي يُحسب فقط إذا كانت كل مهامه مكتملة، وإلا فالسلسلة قد تصل لليوم السابق.
  int get _currentStreak {
    final stats = _statsByDay;
    final today = DateTime.now();
    DateTime cursor = DateTime(today.year, today.month, today.day);

    final todayKey = '${cursor.year}-${cursor.month}-${cursor.day}';
    final todayStats = stats[todayKey];
    int count = 0;
    if (todayStats != null && todayStats.allDone) {
      count++;
    }
    cursor = cursor.subtract(const Duration(days: 1));

    while (true) {
      final key = '${cursor.year}-${cursor.month}-${cursor.day}';
      final s = stats[key];
      if (s == null || !s.allDone) break;
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  // إرجاع كل التذكيرات الخاصة بيوم محدد.
  List<Map<String, dynamic>> _remindersForDay(DateTime day) {
    return _allReminders.where((m) {
      final dtStr = m['dateTime'] as String?;
      if (dtStr == null) return false;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) return false;
      return dt.year == day.year && dt.month == day.month && dt.day == day.day;
    }).toList();
  }

  // إرجاع أول يوم في شبكة التقويم للشهر (الأحد الذي يسبق أو يساوي اليوم الأول).
  DateTime _firstGridDay(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    return first.subtract(Duration(days: first.weekday % 7));
  }

  // إنشاء قائمة الأيام (42 يوماً) التي تملأ شبكة الشهر الكاملة.
  List<DateTime> _daysInGrid(DateTime month) {
    final start = _firstGridDay(month);
    return List.generate(42, (i) => start.add(Duration(days: i)));
  }

  // الانتقال للشهر السابق.
  void _goToPrev() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  // الانتقال للشهر التالي.
  void _goToNext() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysInGrid(_focusedMonth);
    final stats = _statsByDay;
    final streak = _currentStreak;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _goToPrev,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Text(DateFormat('MMMM').format(_focusedMonth)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _goToNext,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _StreakBanner(streak: streak, streakColor: _streakColor),

          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 1),

          // Calendar grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 0.85,
              ),
              itemCount: days.length,
              itemBuilder: (context, i) {
                final day = days[i];
                final isCurrentMonth =
                    day.month == _focusedMonth.month;
                final isToday = _isSameDay(day, DateTime.now());
                final isSelected =
                    _selectedDay != null && _isSameDay(day, _selectedDay!);

                final dayKey = '${day.year}-${day.month}-${day.day}';
                final dayStats = isCurrentMonth ? stats[dayKey] : null;

                return _DayCell(
                  day: day,
                  isCurrentMonth: isCurrentMonth,
                  isToday: isToday,
                  isSelected: isSelected,
                  stats: dayStats,
                  streakColor: _streakColor,
                  onTap: () => setState(() => _selectedDay = day),
                );
              },
            ),
          ),

          if (_selectedDay != null)
            _buildDayPanel(_selectedDay!, stats[
                '${_selectedDay!.year}-${_selectedDay!.month}-${_selectedDay!.day}']),

          Container(
            height: 56,
            color: Colors.white,
            child: PageView.builder(
              controller: _monthPageController,
              itemBuilder: (context, page) {
                final offset = page - _initialPage;
                final month = DateTime(
                  DateTime.now().year,
                  DateTime.now().month + offset,
                );
                final isFocused = month.year == _focusedMonth.year &&
                    month.month == _focusedMonth.month;
                return GestureDetector(
                  onTap: () => setState(() => _focusedMonth = month),
                  child: Center(
                    child: Text(
                      DateFormat('MMMM').format(month),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isFocused
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isFocused
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // مقارنة سريعة لمعرفة هل التاريخان في نفس اليوم.
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // بناء لوحة تفاصيل اليوم المحدد التي تظهر أسفل التقويم.
  Widget _buildDayPanel(DateTime day, _DayStats? stats) {
    final items = _remindersForDay(day);

    final catColors = {
      'personal': Colors.pinkAccent,
      'work': AppColors.primary,
      'family': AppColors.success,
      'other': AppColors.accent,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('EEEE, MMM d').format(day),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (stats != null && stats.total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: stats.allDone
                        ? _streakColor.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        stats.allDone
                            ? Icons.local_fire_department_rounded
                            : Icons.timelapse_rounded,
                        size: 13,
                        color: stats.allDone
                            ? _streakColor
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${stats.completed}/${stats.total}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: stats.allDone
                              ? _streakColor
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (stats != null && stats.total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stats.progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation(
                  stats.allDone ? _streakColor : AppColors.accent,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No reminders on this day.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            )
          else
            ...items.map((m) {
              final title = m['title'] as String? ?? '';
              final cat = m['category'] as String? ?? 'other';
              final done = m['isCompleted'] as bool? ?? false;
              final color = catColors[cat] ?? AppColors.accent;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 13,
                          color: done
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (done)
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: _streakColor),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// إحصائيات يوم واحد: إجمالي المهام وعدد المنجز منها.
class _DayStats {
  final int total;
  final int completed;
  const _DayStats({required this.total, required this.completed});

  bool get allDone => total > 0 && completed >= total;
  double get progress => total == 0 ? 0 : (completed / total).clamp(0.0, 1.0);
}

// لافتة سلسلة الإنجاز اليومية في أعلى التقويم.
class _StreakBanner extends StatelessWidget {
  final int streak;
  final Color streakColor;

  const _StreakBanner({required this.streak, required this.streakColor});

  @override
  Widget build(BuildContext context) {
    final hasStreak = streak > 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: hasStreak
              ? [streakColor, streakColor.withValues(alpha: 0.78)]
              : [Colors.white, Colors.white],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasStreak ? Colors.transparent : const Color(0xFFE5E7EB),
        ),
        boxShadow: hasStreak
            ? [
                BoxShadow(
                  color: streakColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hasStreak
                  ? Colors.white.withValues(alpha: 0.18)
                  : streakColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_fire_department_rounded,
              color: hasStreak ? Colors.white : streakColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasStreak
                      ? '$streak day${streak == 1 ? '' : 's'} streak'
                      : 'Start a streak today',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: hasStreak ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasStreak
                      ? 'Keep finishing every task to extend it.'
                      : 'Finish every task today to begin.',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasStreak
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (hasStreak)
            Text(
              '$streak',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

// خلية يوم واحد في شبكة التقويم تعرض الرقم وحالة الإنجاز.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final _DayStats? stats;
  final Color streakColor;
  final VoidCallback onTap;

  const _DayCell({
    required this.day,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.stats,
    required this.streakColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasTasks = stats != null && stats!.total > 0;
    final allDone = hasTasks && stats!.allDone;
    final progress = hasTasks ? stats!.progress : 0.0;

    BoxDecoration? decoration;
    Color textColor;

    if (isSelected) {
      decoration = BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      );
      textColor = Colors.white;
    } else if (allDone) {
      decoration = BoxDecoration(
        color: streakColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: streakColor.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      );
      textColor = Colors.white;
    } else if (isToday) {
      decoration = BoxDecoration(
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      );
      textColor = AppColors.textPrimary;
    } else {
      textColor = isCurrentMonth
          ? AppColors.textPrimary
          : AppColors.textSecondary.withValues(alpha: 0.4);
    }

    final showRing =
        hasTasks && !allDone && !isSelected && stats!.completed > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: decoration,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showRing)
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.2,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.18),
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: (isToday || isSelected || allDone)
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: textColor,
                  ),
                ),
                if (hasTasks && !allDone && !showRing)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (allDone)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
