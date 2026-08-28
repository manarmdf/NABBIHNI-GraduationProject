import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../location/osm_place_service.dart' show NearbyPlace;
import '../reminder_model.dart';
import '../../shared/constants.dart';

/// قائمة بطاقات الأماكن القريبة — تعرض بطاقة لكل نوع مكان لديه تذكيرات مطابقة.
class NearbyBannerList extends StatelessWidget {
  final List<NearbyPlace> nearbyPlaces;
  final List<Reminder> reminders;
  final void Function(Reminder) onTap;

  const NearbyBannerList({
    super.key,
    required this.nearbyPlaces,
    required this.reminders,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // تجميع التذكيرات حسب نوع الموقع
    final grouped = <String, List<Reminder>>{};
    for (final r in reminders) {
      final t = r.locationType;
      if (t == null) continue;
      grouped.putIfAbsent(t, () => []).add(r);
    }

    // ترتيب الأنواع حسب أقرب مكان مطابق
    final types = grouped.keys.toList();
    double minDist(String t) {
      final ps = nearbyPlaces.where((p) => p.type == t).toList();
      if (ps.isEmpty) return double.infinity;
      ps.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      return ps.first.distanceMeters;
    }
    types.sort((a, b) => minDist(a).compareTo(minDist(b)));

    return Column(
      children: types
          .map((type) => _NearbyTypeCard(
                type: type,
                places: nearbyPlaces.where((p) => p.type == type).toList()
                  ..sort((a, b) =>
                      a.distanceMeters.compareTo(b.distanceMeters)),
                reminders: grouped[type]!,
                onTap: onTap,
              ))
          .toList(),
    );
  }
}

/// بطاقة نوع مكان واحد — مثلاً بطاقة "صيدلية" أو "بنك".
class _NearbyTypeCard extends StatelessWidget {
  final String type;
  final List<NearbyPlace> places;
  final List<Reminder> reminders;
  final void Function(Reminder) onTap;

  const _NearbyTypeCard({
    required this.type,
    required this.places,
    required this.reminders,
    required this.onTap,
  });

  static const _typeIcons = <String, IconData>{
    'pharmacy':   Icons.local_pharmacy_rounded,
    'grocery':    Icons.local_grocery_store_rounded,
    'hospital':   Icons.local_hospital_rounded,
    'bank':       Icons.account_balance_rounded,
    'gym':        Icons.fitness_center_rounded,
    'store':      Icons.storefront_rounded,
    'restaurant': Icons.restaurant_rounded,
    'cafe':       Icons.local_cafe_rounded,
    'school':     Icons.school_rounded,
    'mosque':     Icons.mosque_rounded,
    'work':       Icons.work_rounded,
    'home':       Icons.home_rounded,
  };

  String get _typeLabel => type[0].toUpperCase() + type.substring(1);

  /// يُرجع أقرب مكان يحمل اسماً (مفضّل للعنوان)، أو أقرب مكان بدون اسم.
  NearbyPlace? get _closestPlace {
    if (places.isEmpty) return null;
    final named = places.where((p) => p.name != null && p.name!.isNotEmpty);
    if (named.isNotEmpty) return named.first;
    return places.first;
  }

  /// يُنسّق المسافة بالأمتار أو الكيلومترات.
  static String _formatDistance(double m) {
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';
  }

  /// يفتح خرائط جوجل في تطبيق خارجي لعرض المكان.
  Future<void> _openMaps(NearbyPlace place) async {
    final name = place.name;
    final Uri uri;
    if (name != null && name.isNotEmpty) {
      final encoded = Uri.encodeComponent(name);
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encoded&ll=${place.lat},${place.lng}',
      );
    } else {
      uri = Uri.parse(
          'geo:${place.lat},${place.lng}?q=${place.lat},${place.lng}');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[type] ?? Icons.place_rounded;
    final closest = _closestPlace;
    final headerName = closest?.name ?? _typeLabel;
    final headerSuffix = closest != null
        ? ' · ${_formatDistance(closest.distanceMeters)}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان البطاقة: "أنت بالقرب من: اسم المكان · ٣٢٠ م"
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "You're near: $headerName$headerSuffix",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // شرائح الأماكن (أقرب الأماكن المسمّاة أولاً)
          if (places.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _topNamedPlaces().map((place) {
                return GestureDetector(
                  onTap: () => _openMaps(place),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 12, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '${place.name ?? _typeLabel} · ${_formatDistance(place.distanceMeters)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.open_in_new_rounded,
                            size: 10, color: AppColors.accent),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),

          // صفوف التذكيرات المطابقة
          ...reminders.map((r) {
            return InkWell(
              onTap: () => onTap(r),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        softWrap: true,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.textSecondary),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// يُرجع أقرب ٣ أماكن مسمّاة غير مكررة. يعود للأماكن بدون اسم إذا لم يوجد أي مسمّى.
  List<NearbyPlace> _topNamedPlaces() {
    final named = places
        .where((p) => p.name != null && p.name!.isNotEmpty)
        .toList();
    if (named.isNotEmpty) {
      final seen = <String>{};
      final result = <NearbyPlace>[];
      for (final p in named) {
        if (seen.add(p.name!)) result.add(p);
        if (result.length >= 3) break;
      }
      return result;
    }
    return places.take(2).toList();
  }
}
