import 'package:flutter/material.dart';
import '../../shared/constants.dart';

/// شريحة التاريخ/الوقت — زر مدمج لاختيار التاريخ أو الوقت مع زر مسح اختياري.
class DateTimeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const DateTimeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? AppColors.primary : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 14, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
