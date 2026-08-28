import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// لوحة ألوان التطبيق — الألوان المستخدمة في جميع الشاشات.
class AppColors {
  static const Color primary = Color(0xFF8BB2CD);
  static const Color accent = Color(0xFFF28C84);
  static const Color background = Color(0xFFE1ECF4);
  static const Color textPrimary = Color(0xFF000000);
  static const Color textSecondary = Color(0xFF6B7B85);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF6C61);
  static const Color cardBackground = Color(0xFFFFFFFF);
}

/// نصوص ثابتة للتطبيق.
class AppStrings {
  static const String appName = 'Nabbihni';
  static const String tagline = 'Smart reminders, smarter life.';
}

/// إعدادات التطبيق — نصف القطر للكشف عن الأماكن القريبة.
/// قابل للتعديل من شاشة الملف الشخصي ويُحفظ في SharedPreferences.
class AppConfig {
  static const String _kRadiusKey = 'nearby_radius_meters';
  static const int minRadiusMeters = 300;
  static const int maxRadiusMeters = 10000;
  static const int defaultRadiusMeters = 5000;

  static int _radius = defaultRadiusMeters;

  /// نصف القطر الحالي بالأمتار (قراءة من الذاكرة المؤقتة).
  static int get nearbyRadiusMeters => _radius;

  /// يقرأ نصف القطر المحفوظ عند بدء التطبيق.
  static Future<int> loadRadius() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kRadiusKey);
    if (stored != null) {
      _radius = stored.clamp(minRadiusMeters, maxRadiusMeters);
    }
    return _radius;
  }

  /// يحفظ نصف قطر جديد ويحدّث الذاكرة المؤقتة.
  static Future<void> setRadius(int meters) async {
    final clamped = meters.clamp(minRadiusMeters, maxRadiusMeters);
    _radius = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kRadiusKey, clamped);
  }
}
