import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nabbihni/shared/constants.dart';
import '../authentication/auth_service.dart';
import '../profile/profile_screen.dart';

// شاشة النشاط: تعرض إحصائيات التذكيرات وقائمة مفصلة حسب التصنيف.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String _selectedCategory = 'all';

  int _completed = 0;
  int _inProgress = 0;
  int _uncompleted = 0;

  List<Map<String, dynamic>> _reminders = [];
  StreamSubscription<QuerySnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  // الاشتراك في تذكيرات المستخدم من Firestore وحساب أعداد كل حالة.
  void _listen() {
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
          final all = snap.docs.map((d) => d.data()).toList();
          final now = DateTime.now();

          int comp = 0, prog = 0, uncomp = 0;
          for (final m in all) {
            final done = m['isCompleted'] as bool? ?? false;
            if (done) {
              comp++;
            } else {
              final dtStr = m['dateTime'] as String?;
              final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
              if (dt != null && dt.isBefore(now)) {
                uncomp++;
              } else {
                prog++;
              }
            }
          }

          setState(() {
            _completed = comp;
            _inProgress = prog;
            _uncompleted = uncomp;
            if (_selectedCategory == 'all') {
              _reminders = all;
            } else {
              _reminders = all
                  .where((m) => m['category'] == _selectedCategory)
                  .toList();
            }
          });
        });
  }

  // إلغاء الاشتراك بالـStream عند إغلاق الشاشة.
  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // تحديث التصنيف المختار وإعادة الاشتراك لتطبيق الفلتر.
  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat);
    _sub?.cancel();
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final name = user?.displayName?.split(' ').first ?? 'Raghad';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,

        title: const Text(
          'Activity',
          style: TextStyle(color: AppColors.background, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.background,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        children: [
          Text(
            '${DateTime.now().hour < 12
                ? 'Good morning'
                : DateTime.now().hour < 17
                ? 'Good afternoon'
                : 'Good evening'}, $name',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // Activity Card
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: CustomPaint(
                        painter: _ActivityDonutPainter(
                          completed: _completed,
                          inProgress: _inProgress,
                          uncompleted: _uncompleted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LegendItem(
                          color: AppColors.primary,
                          label: 'Completed',
                          count: _completed,
                        ),
                        const SizedBox(height: 14),
                        _LegendItem(
                          color: const Color(
                            0xFFFDE0B4,
                          ), // Exact matching soft yellow from UI
                          label: 'In Progress',
                          count: _inProgress,
                        ),
                        const SizedBox(height: 14),
                        _LegendItem(
                          color: AppColors.accent,
                          label: 'Uncompleted',
                          count: _uncompleted,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Categories Title
          const Text(
            'Categories',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none, // Allows soft shadow to be visible
            child: Row(
              children: [
                _CategoryChip(
                  icon: Icons.all_inclusive_rounded,
                  color: AppColors.primary,
                  label: 'All',
                  selected: _selectedCategory == 'all',
                  onTap: () => _selectCategory('all'),
                ),
                const SizedBox(width: 12),
                _CategoryChip(
                  icon: Icons.favorite_rounded,
                  color: AppColors.accent,
                  label: 'Personal',
                  selected: _selectedCategory == 'personal',
                  onTap: () => _selectCategory('personal'),
                ),
                const SizedBox(width: 12),
                _CategoryChip(
                  icon: Icons.work_outline_rounded,
                  color: AppColors.primary,
                  label: 'Work',
                  selected: _selectedCategory == 'work',
                  onTap: () => _selectCategory('work'),
                ),
                const SizedBox(width: 12),
                _CategoryChip(
                  icon: Icons.group_outlined,
                  color: AppColors.primary,
                  label: 'Family',
                  selected: _selectedCategory == 'family',
                  onTap: () => _selectCategory('family'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          if (_reminders.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      size: 56,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedCategory == 'all'
                          ? 'No reminders yet.'
                          : 'No $_selectedCategory tasks yet.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._reminders.map((m) {
              final title = m['title'] as String? ?? '';
              final done = m['isCompleted'] as bool? ?? false;
              final cat = m['category'] as String? ?? 'other';
              final dtStr = m['dateTime'] as String?;
              final dt = dtStr != null ? DateTime.tryParse(dtStr) : null;
              final now = DateTime.now();
              final isOverdue = dt != null && dt.isBefore(now) && !done;

              // Left bar color logic matching visual design
              final Color barColor;
              if (done) {
                barColor = AppColors.primary;
              } else if (isOverdue) {
                barColor = AppColors.accent;
              } else {
                barColor = AppColors.primary;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.textSecondary.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      cat.toLowerCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.primary, // Blue subtitle from UI
                      ),
                    ),
                  ),
                  trailing: Icon(
                    Icons.circle_outlined,
                    color: AppColors.primary.withValues(alpha: 0.8),
                    size: 26,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// شريحة تصنيف قابلة للضغط مع تأثير تحديد بصري.
class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : AppColors.background,
            width: 1.5,
          ),
          boxShadow: !selected
              ? [
                  BoxShadow(
                    color: AppColors.textSecondary.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// عنصر مفتاح للرسم البياني يعرض اللون والاسم والعدد.
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// رسّام مخصص يرسم رسماً بيانياً دائرياً مجوّفاً لتوزيع التذكيرات.
class _ActivityDonutPainter extends CustomPainter {
  final int completed;
  final int inProgress;
  final int uncompleted;

  _ActivityDonutPainter({
    required this.completed,
    required this.inProgress,
    required this.uncompleted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = completed + inProgress + uncompleted;
    // Default placeholder chart if empty to match aesthetic
    final safeTotal = total == 0 ? 1 : total;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 18.0;
    final rect = Rect.fromCircle(
      center: center,
      radius: radius - strokeWidth / 2,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;

    void drawArc(int count, Color color) {
      if (count == 0 && total != 0) return;
      // If total is 0, we draw a full placeholder circle
      final sweep = total == 0 ? 2 * math.pi : 2 * math.pi * count / safeTotal;
      paint.color = color;
      // Add gap only if there are multiple segments
      final gap = total > 0 ? 0.15 : 0.0;
      canvas.drawArc(rect, startAngle, sweep - gap, false, paint);
      startAngle += sweep;
    }

    // Colors mapping exactly to screenshot
    if (total == 0) {
      drawArc(1, AppColors.background); // Empty state visualization
    } else {
      drawArc(completed, AppColors.primary); // Blue
      drawArc(inProgress, const Color(0xFFFDE0B4)); // Soft yellow from UI
      drawArc(uncompleted, AppColors.accent); // Pink
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$total',
        style: const TextStyle(
          fontSize: 32, // Larger to match screenshot
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_ActivityDonutPainter old) =>
      old.completed != completed ||
      old.inProgress != inProgress ||
      old.uncompleted != uncompleted;
}
