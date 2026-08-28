import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// نتيجة مكان من خدمة Nominatim لخرائط OpenStreetMap.
class NominatimPlace {
  final String displayName;
  final double lat;
  final double lng;
  final String? type;

  NominatimPlace({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.type,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    return NominatimPlace(
      displayName: json['display_name'] as String? ?? '',
      lat: double.tryParse(json['lat']?.toString() ?? '') ?? 0.0,
      lng: double.tryParse(json['lon']?.toString() ?? '') ?? 0.0,
      type: json['type'] as String?,
    );
  }
}

// خدمة مجانية لتحويل النص إلى إحداثيات وبالعكس عبر OpenStreetMap.
// لا تحتاج مفتاح، لكنها تتطلب إرسال User-Agent وإلا ترفض الطلب.
class NominatimService {
  static const _baseUrl = 'https://nominatim.openstreetmap.org';
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent': 'NabbihniApp/1.0',
  };

  // البحث عن أماكن بالاسم وإرجاع قائمة بالنتائج المطابقة وإحداثياتها.
  static Future<List<NominatimPlace>> search(
    String query, {
    int limit = 5,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/search').replace(
      queryParameters: {
        'q': query.trim(),
        'format': 'json',
        'limit': limit.toString(),
        'addressdetails': '1',
      },
    );

    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        debugPrint('Nominatim search error ${response.statusCode}: ${response.body}');
        return [];
      }

      final List data = json.decode(response.body) as List;
      debugPrint('Nominatim search found ${data.length} results for "$query"');
      return data
          .map((e) => NominatimPlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Nominatim search exception: $e');
      return [];
    }
  }

  // عكس الترميز الجغرافي: إرجاع العنوان النصي من إحداثيات (خط العرض والطول).
  static Future<NominatimPlace?> reverse(double lat, double lng) async {
    final uri = Uri.parse('$_baseUrl/reverse').replace(
      queryParameters: {
        'lat': lat.toString(),
        'lon': lng.toString(),
        'format': 'json',
        'addressdetails': '1',
      },
    );

    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        debugPrint('Nominatim reverse error ${response.statusCode}: ${response.body}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>?;
      if (data == null || data['error'] != null) return null;

      return NominatimPlace.fromJson(data);
    } catch (e) {
      debugPrint('Nominatim reverse exception: $e');
      return null;
    }
  }
}
