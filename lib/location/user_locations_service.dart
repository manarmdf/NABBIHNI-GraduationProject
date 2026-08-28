import 'dart:math' show cos, sqrt, asin, sin;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// موقع شخصي يحفظه المستخدم (المنزل، النادي، العمل، المدرسة).
class UserLocation {
  final String type;
  final String? name;
  final double? lat;
  final double? lng;
  final String? address;
  final DateTime? updatedAt;

  UserLocation({
    required this.type,
    this.name,
    this.lat,
    this.lng,
    this.address,
    this.updatedAt,
  });

  bool get isSet => lat != null && lng != null;

  Map<String, dynamic> toMap() => {
        'name': name,
        'lat': lat,
        'lng': lng,
        'address': address,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory UserLocation.fromMap(String type, Map<String, dynamic> m) {
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    final updatedAt = m['updatedAt'] != null
        ? DateTime.tryParse(m['updatedAt'] as String)
        : null;
    return UserLocation(
      type: type,
      name: m['name'] as String?,
      lat: lat,
      lng: lng,
      address: m['address'] as String?,
      updatedAt: updatedAt,
    );
  }
}

// مساعدات Firestore لإدارة المواقع الشخصية للمستخدم.
class UserLocationsService {
  static const _types = ['home', 'gym', 'work', 'school'];

  // إرجاع مرجع وثيقة المستخدم الحالي في Firestore.
  static DocumentReference<Map<String, dynamic>> _userDoc() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  // قراءة جميع المواقع الشخصية المحفوظة مرة واحدة.
  static Future<Map<String, UserLocation>> getLocations() async {
    final snap = await _userDoc().get();
    final data = snap.data()?['personalLocations'] as Map<String, dynamic>? ?? {};
    final result = <String, UserLocation>{};
    for (final t in _types) {
      final m = data[t] as Map<String, dynamic>?;
      if (m != null && m['lat'] != null && m['lng'] != null) {
        result[t] = UserLocation.fromMap(t, m);
      }
    }
    return result;
  }

  // تدفق مباشر للمواقع الشخصية ينبه المستمعين عند أي تغيير.
  static Stream<Map<String, UserLocation>> locationsStream() {
    return _userDoc().snapshots().map((snap) {
      final data =
          snap.data()?['personalLocations'] as Map<String, dynamic>? ?? {};
      final result = <String, UserLocation>{};
      for (final t in _types) {
        final m = data[t] as Map<String, dynamic>?;
        if (m != null && m['lat'] != null && m['lng'] != null) {
          result[t] = UserLocation.fromMap(t, m);
        }
      }
      return result;
    });
  }

  // حفظ أو تحديث موقع شخصي واحد بنوع محدد.
  static Future<void> saveLocation(
    String type, {
    String? name,
    double? lat,
    double? lng,
    String? address,
  }) async {
    await _userDoc().set({
      'personalLocations': {
        type: {
          'name': name ?? '',
          'lat': lat,
          'lng': lng,
          'address': address,
          'updatedAt': DateTime.now().toIso8601String(),
        }
      }
    }, SetOptions(merge: true));
  }

  // إرجاع true إن كان للمستخدم موقع واحد على الأقل محفوظ.
  static Future<bool> hasAnyLocation() async {
    final locs = await getLocations();
    return locs.isNotEmpty;
  }

  // حساب المسافة بالأمتار بين إحداثيتين باستخدام صيغة Haversine.
  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(_toRad(lat1)) *
            cos(_toRad(lat2)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final c = 2 * asin(sqrt(a));
    return r * c;
  }

  // تحويل الدرجات إلى راديان.
  static double _toRad(double deg) => deg * (3.141592653589793 / 180.0);
}
