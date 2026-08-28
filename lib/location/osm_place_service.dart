import 'dart:async';
import 'dart:convert';
import 'dart:math' show cos, sin, asin, sqrt, pi;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// مكان قريب أعادته خدمة Overpass: النوع والاسم والإحداثيات والمسافة.
class NearbyPlace {
  final String type;
  final String? name;
  final double lat;
  final double lng;
  final double distanceMeters;

  const NearbyPlace({
    required this.type,
    required this.name,
    required this.lat,
    required this.lng,
    this.distanceMeters = 0,
  });

  @override
  String toString() =>
      'NearbyPlace($type, ${name ?? "?"}, ${distanceMeters.toStringAsFixed(0)}m)';
}

// خدمة كشف فئات الأماكن القريبة عبر Overpass من OpenStreetMap (مجاناً وبدون مفتاح).
class OsmPlaceService {
  static const _maxRadius = 10000;

  // ربط وسم OSM بنوع المكان داخل التطبيق ليتطابق مع كلمات المستخدم.
  static const _amenityToType = <String, String>{
    'pharmacy':           'pharmacy',
    'hospital':           'hospital',
    'clinic':             'hospital',
    'doctors':            'hospital',
    'dentist':            'hospital',
    'bank':               'bank',
    'atm':                'bank',
    'gym':                'gym',
    'fitness_centre':     'gym',
    'sports_centre':      'gym',
    'restaurant':         'restaurant',
    'fast_food':          'restaurant',
    'cafe':               'cafe',
    'school':             'school',
    'university':         'school',
    'college':            'school',
    'kindergarten':       'school',
  };

  static const _shopToType = <String, String>{
    'supermarket':        'grocery',
    'convenience':        'grocery',
    'greengrocer':        'grocery',
    'bakery':             'grocery',
    'butcher':            'grocery',
    'pharmacy':           'pharmacy',
    'chemist':            'pharmacy',
    'mall':               'store',
    'department_store':   'store',
    'general':            'store',
    'variety_store':      'store',
    'clothes':            'store',
    'shoes':              'store',
    'electronics':        'store',
    'mobile_phone':       'store',
    'jewelry':            'store',
  };

  static bool _busy = false;

  // البحث عن المرافق والمحلات القريبة ضمن نصف القطر المحدد.
  // النصف القطر محدود بـ _maxRadius لتفادي مهلة Overpass.
  // النتائج مرتبة من الأقرب للأبعد ومحررة من التكرار.
  static Future<List<NearbyPlace>> getNearbyPlaces(
    double lat,
    double lng, {
    int radiusMeters = 3000,
  }) async {
    if (_busy) {
      debugPrint('[OSM] skipping — already in progress');
      return [];
    }
    _busy = true;
    try {
      return await _fetchPlaces(lat, lng, radiusMeters);
    } finally {
      _busy = false;
    }
  }

  // الاستعلام الفعلي من Overpass: يشمل way وrelation لتغطية المباني الكبيرة
  // كالمستشفيات والأسواق، وout center لإرجاع نقطة مركزية لكل عنصر.
  static Future<List<NearbyPlace>> _fetchPlaces(
      double lat, double lng, int radiusMeters) async {
    final r = radiusMeters.clamp(100, _maxRadius);
    debugPrint('[OSM] getNearbyPlaces radius=${r}m at ($lat, $lng)');

    final query =
        '[out:json][timeout:25];'
        '('
        'node["amenity"](around:$r,$lat,$lng);'
        'way["amenity"](around:$r,$lat,$lng);'
        'node["shop"](around:$r,$lat,$lng);'
        'way["shop"](around:$r,$lat,$lng);'
        ');'
        'out center tags;';

    final uri = Uri.https('overpass-api.de', '/api/interpreter', {'data': query});
    final http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Nabbihni/1.0',
        },
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      debugPrint('[OSM] HTTP request timed out after 30s');
      return [];
    } catch (e) {
      debugPrint('[OSM] HTTP error: $e');
      return [];
    }

    debugPrint('[OSM] HTTP ${response.statusCode} — ${response.body.length} bytes');
    if (response.statusCode != 200) {
      debugPrint('[OSM] ERROR body: ${response.body.substring(0, response.body.length.clamp(0, 500))}');
      return [];
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final elements = data['elements'] as List? ?? [];
    debugPrint('[OSM] ${elements.length} raw elements from Overpass');

    final places = <NearbyPlace>[];
    for (final el in elements) {
      final tags = el['tags'] as Map<String, dynamic>? ?? {};

      double? elLat = (el['lat'] as num?)?.toDouble();
      double? elLng = (el['lon'] as num?)?.toDouble();
      if (elLat == null || elLng == null) {
        final c = el['center'] as Map<String, dynamic>?;
        elLat = (c?['lat'] as num?)?.toDouble();
        elLng = (c?['lon'] as num?)?.toDouble();
      }
      if (elLat == null || elLng == null) continue;

      final name = tags['name'] as String?;

      String? type;
      final amenity = tags['amenity'] as String?;
      if (amenity != null && _amenityToType.containsKey(amenity)) {
        type = _amenityToType[amenity];
      }
      if (type == null) {
        final shop = tags['shop'] as String?;
        if (shop != null && _shopToType.containsKey(shop)) {
          type = _shopToType[shop];
        }
      }
      if (type == null) continue;

      final dist = _haversineMeters(lat, lng, elLat, elLng);
      places.add(NearbyPlace(
        type: type,
        name: name,
        lat: elLat,
        lng: elLng,
        distanceMeters: dist,
      ));
    }

    // إزالة التكرار بالاحتفاظ بالأقرب لكل (نوع، اسم).
    final seen = <String, NearbyPlace>{};
    for (final p in places) {
      final key = '${p.type}|${p.name ?? "_${p.lat},${p.lng}"}';
      final existing = seen[key];
      if (existing == null || p.distanceMeters < existing.distanceMeters) {
        seen[key] = p;
      }
    }
    final result = seen.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    final typeSet = result.map((p) => p.type).toSet();
    debugPrint('[OSM] ✓ ${result.length} matched places (deduped), types=$typeSet');
    return result;
  }

  // حساب المسافة بالأمتار بين إحداثيتين باستخدام صيغة Haversine.
  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLng = (lng2 - lng1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }
}
