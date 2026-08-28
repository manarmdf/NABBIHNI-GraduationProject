import 'package:cloud_firestore/cloud_firestore.dart';

/// نموذج التذكير — يمثل تذكيراً واحداً محفوظاً في Firestore.
class Reminder {
  final String id;
  String title;
  DateTime? dateTime;
  String category;
  String? locationType;
  bool isCompleted;
  int snoozeDurationMinutes;
  double? lat;
  double? lng;
  String? address;
  String priority;

  Reminder({
    required this.id,
    required this.title,
    this.dateTime,
    this.category = 'personal',
    this.locationType,
    this.isCompleted = false,
    this.snoozeDurationMinutes = 15,
    this.lat,
    this.lng,
    this.address,
    this.priority = 'medium',
  });

  /// يحوّل التذكير إلى خريطة لحفظها في Firestore.
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'dateTime': dateTime?.toIso8601String(),
        'category': category,
        'locationType': locationType,
        'isCompleted': isCompleted,
        'snoozeDurationMinutes': snoozeDurationMinutes,
        'lat': lat,
        'lng': lng,
        'address': address,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// ينشئ كائن Reminder من خريطة Firestore.
  factory Reminder.fromMap(Map<String, dynamic> m) => Reminder(
        id: m['id'] as String,
        title: m['title'] as String,
        dateTime: m['dateTime'] != null
            ? DateTime.parse(m['dateTime'] as String)
            : null,
        category: m['category'] as String? ?? 'personal',
        locationType: m['locationType'] as String?,
        isCompleted: m['isCompleted'] as bool? ?? false,
        snoozeDurationMinutes: m['snoozeDurationMinutes'] as int? ?? 15,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        address: m['address'] as String?,
        priority: m['priority'] as String? ?? 'medium',
      );
}
