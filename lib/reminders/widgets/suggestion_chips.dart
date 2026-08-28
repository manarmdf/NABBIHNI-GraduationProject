import 'package:flutter/material.dart';
import '../../shared/constants.dart';
import '../../shared/habit_helper.dart';

/// شرائح اقتراحات الذكاء الاصطناعي — صف متحرك يظهر أثناء كتابة المستخدم
/// ويعرض توقعات الفئة من نموذج التعلّم الآلي.
class SuggestionChips extends StatelessWidget {
  final List<HabitSuggestion> suggestions;
  final TimeOfDay Function(String category) defaultTimeFor;
  final DateTime? pickedDate;
  final TimeOfDay? pickedTime;
  final void Function(HabitSuggestion) onPick;
  final VoidCallback onDismiss;

  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.defaultTimeFor,
    required this.onPick,
    required this.onDismiss,
    this.pickedDate,
    this.pickedTime,
  });

  // ألوان الفئات
  static const _catColor = <String, Color>{
    'personal': Colors.pinkAccent,
    'work':     AppColors.primary,
    'family':   AppColors.success,
    'other':    AppColors.textSecondary,
  };

  // أيقونات الفئات
  static const _catIcon = <String, IconData>{
    'personal': Icons.favorite_rounded,
    'work':     Icons.work_outline_rounded,
    'family':   Icons.group_outlined,
    'other':    Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس القسم
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 15,
                    color: AppColors.primary.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                const Text(
                  'AI Suggestions',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(Icons.close_rounded, size: 15,
                      color: AppColors.textSecondary.withValues(alpha: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // شرائح الاقتراحات
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestions.map((s) {
                final color = _catColor[s.category] ?? AppColors.primary;
                final icon  = _catIcon[s.category]  ?? Icons.lightbulb_outline;
                final pct   = (s.confidence * 100).toStringAsFixed(0);
                final time  = defaultTimeFor(s.category);

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onPick(s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: color),
                          const SizedBox(width: 5),
                          Text(
                            '${_capitalize(s.category)} · $pct%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.schedule_rounded, size: 11,
                              color: color.withValues(alpha: 0.6)),
                          const SizedBox(width: 2),
                          Text(
                            time.format(context),
                            style: TextStyle(
                              fontSize: 11,
                              color: color.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// يُكبّر أول حرف من النص.
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
