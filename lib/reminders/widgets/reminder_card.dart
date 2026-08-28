import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../reminder_model.dart';
import '../../shared/constants.dart';

/// بطاقة التذكير — تعرض تذكيراً واحداً مع أزرار (إكمال / تأجيل / نطق / حذف).
/// يمكن سحبها لليسار لحذفها.
class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onSpeak;
  final VoidCallback onEdit;
  final VoidCallback? onSnooze;

  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onToggle,
    required this.onDelete,
    required this.onSpeak,
    required this.onEdit,
    this.onSnooze,
  });

  // ألوان الفئات
  static const _catColor = <String, Color>{
    'personal': Colors.pinkAccent,
    'work':     AppColors.primary,
    'family':   AppColors.success,
    'other':    AppColors.textSecondary,
  };

  // أيقونات أنواع المواقع
  static const _locTypeIcons = <String, IconData>{
    'pharmacy':   Icons.local_pharmacy_rounded,
    'grocery':    Icons.shopping_cart_rounded,
    'work':       Icons.work_outline_rounded,
    'home':       Icons.home_rounded,
    'gym':        Icons.fitness_center_rounded,
    'hospital':   Icons.local_hospital_rounded,
    'bank':       Icons.account_balance_rounded,
    'store':      Icons.store_rounded,
    'restaurant': Icons.restaurant_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _catColor[reminder.category] ?? AppColors.primary;

    return Dismissible(
      key: Key(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // شريط لون الفئة
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                // دائرة الإكمال
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: reminder.isCompleted
                            ? AppColors.success
                            : const Color(0xFFD1D5DB),
                        width: 2,
                      ),
                      color: reminder.isCompleted
                          ? AppColors.success
                          : Colors.transparent,
                    ),
                    child: reminder.isCompleted
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // العنوان والتاريخ
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: reminder.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: reminder.isCompleted
                              ? AppColors.textSecondary
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (reminder.dateTime != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          DateFormat('EEE, MMM d · hh:mm a').format(reminder.dateTime!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _capitalize(reminder.category),
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
                            ),
                          ),
                          if (reminder.locationType != null)
                            Icon(
                              _locTypeIcons[reminder.locationType] ?? Icons.place_rounded,
                              size: 15,
                              color: AppColors.accent.withValues(alpha: 0.8),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // زر التأجيل
                if (onSnooze != null && !reminder.isCompleted && reminder.dateTime != null)
                  IconButton(
                    icon: const Icon(Icons.snooze_rounded, size: 18),
                    color: AppColors.accent,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    tooltip: 'تأجيل ١٥ دقيقة',
                    onPressed: onSnooze,
                  ),
                // زر النطق
                IconButton(
                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: onSpeak,
                ),
                // زر الحذف
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppColors.error,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// يُكبّر أول حرف من النص.
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
