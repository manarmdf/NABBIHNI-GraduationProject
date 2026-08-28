import 'package:flutter/material.dart';
import '../../location/user_locations_service.dart';
import '../../shared/constants.dart';

/// منتقي نوع المكان — صف أفقي قابل للتمرير من شرائح أنواع الأماكن.
///
/// [personalLocs] — مواقع المستخدم الشخصية المحفوظة (بيت/نادي/عمل/مدرسة).
/// تُعرض أولاً كقسم "مواقعي" بأسماء مخصصة.
/// عند وجود [preferredFirst] ومطابقته لنوع معروف، تُنقل تلك الشريحة للمقدمة.
class PlaceTypePicker extends StatelessWidget {
  final String? selected;
  final String? preferredFirst;
  final ValueChanged<String?> onChanged;
  final Map<String, UserLocation> personalLocs;

  const PlaceTypePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.preferredFirst,
    this.personalLocs = const {},
  });

  // أيقونات المواقع الشخصية
  static const _personalIcons = <String, IconData>{
    'home':   Icons.home_rounded,
    'gym':    Icons.fitness_center_rounded,
    'work':   Icons.work_outline_rounded,
    'school': Icons.school_rounded,
  };

  // التسميات الافتراضية للمواقع الشخصية
  static const _personalLabels = <String, String>{
    'home':   'Home',
    'gym':    'Gym',
    'work':   'Work',
    'school': 'School',
  };

  // أنواع الأماكن العامة من OSM
  static const _genericTypes = <String, IconData>{
    'pharmacy':   Icons.local_pharmacy_rounded,
    'grocery':    Icons.shopping_cart_rounded,
    'hospital':   Icons.local_hospital_rounded,
    'bank':       Icons.account_balance_rounded,
    'store':      Icons.store_rounded,
    'restaurant': Icons.restaurant_rounded,
    'cafe':       Icons.local_cafe_rounded,
    'mosque':     Icons.mosque_rounded,
  };

  /// يُرتب الأنواع العامة مع وضع النوع المفضّل أولاً.
  List<MapEntry<String, IconData>> _orderedGeneric() {
    final entries = _genericTypes.entries.toList();
    final key = preferredFirst;
    if (key == null || !_genericTypes.containsKey(key)) return entries;
    entries.sort((a, b) {
      if (a.key == key) return -1;
      if (b.key == key) return 1;
      return 0;
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Place type',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary),
            ),
            if (selected != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(Icons.close,
                    size: 14,
                    color: AppColors.textSecondary.withValues(alpha: 0.5)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // قسم مواقعي الشخصية
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _personalIcons.entries.map((e) {
              final type = e.key;
              final loc = personalLocs[type];
              final isSaved = loc != null && loc.isSet;
              final active = selected == type;

              final displayName = (loc?.name != null &&
                      loc!.name!.isNotEmpty &&
                      loc.name != _personalLabels[type])
                  ? loc.name!
                  : _personalLabels[type]!;

              final tooltipMsg = isSaved
                  ? (loc.address ?? 'Saved location')
                  : 'Not set in My Locations';

              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: tooltipMsg,
                  child: GestureDetector(
                    onTap: isSaved ? () => onChanged(active ? null : type) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : isSaved
                                ? AppColors.cardBackground
                                : AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.primary
                              : isSaved
                                  ? AppColors.primary.withValues(alpha: 0.35)
                                  : AppColors.textSecondary
                                      .withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(e.value,
                              size: 14,
                              color: active
                                  ? AppColors.primary
                                  : isSaved
                                      ? AppColors.primary
                                      : AppColors.textSecondary
                                          .withValues(alpha: 0.4)),
                          const SizedBox(width: 4),
                          Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: active
                                  ? AppColors.primary
                                  : isSaved
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary
                                          .withValues(alpha: 0.4),
                            ),
                          ),
                          if (isSaved && !active) ...[
                            const SizedBox(width: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 6),
        Divider(height: 1, color: AppColors.textSecondary.withValues(alpha: 0.12)),
        const SizedBox(height: 6),

        // قسم أنواع الأماكن العامة من OSM
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _orderedGeneric().map((e) {
              final active = selected == e.key;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onChanged(active ? null : e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? AppColors.accent
                            : AppColors.textSecondary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(e.value,
                            size: 14,
                            color: active
                                ? AppColors.accent
                                : AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          _capitalize(e.key),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400,
                            color: active
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// يُكبّر أول حرف من النص.
  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
