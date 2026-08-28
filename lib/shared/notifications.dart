import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// كائن الإشعارات المحلية — يُهيَّأ مرة واحدة في main() ثم يُستخدم في أي مكان.
final FlutterLocalNotificationsPlugin flnp = FlutterLocalNotificationsPlugin();

const _snoozeActionId = 'snooze_action';

/// يبني تفاصيل إشعار أندرويد مع زر تأجيل اختياري.
AndroidNotificationDetails _androidDetails({bool withSnooze = false}) =>
    AndroidNotificationDetails(
      'nabbihni_reminders',
      'Reminders',
      channelDescription: 'Scheduled reminder alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      actions: withSnooze
          ? const [
              AndroidNotificationAction(
                _snoozeActionId,
                'تأجيل ١٥ دقيقة',
                showsUserInterface: false,
              ),
            ]
          : null,
    );

/// يعالج الضغط على زر التأجيل في الخلفية (يجب أن تكون دالة عليا).
@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == _snoozeActionId) {
    final id = response.id ?? 0;
    final snoozeTime = DateTime.now().add(const Duration(minutes: 15));
    flnp.zonedSchedule(
      id: id,
      title: response.payload ?? 'Reminder',
      body: 'Tap to open Nabbihni',
      payload: response.payload,
      scheduledDate: tz.TZDateTime.from(snoozeTime, tz.local),
      notificationDetails: NotificationDetails(
        android: _androidDetails(withSnooze: true),
      ),
      androidScheduleMode: AndroidScheduleMode.alarmClock,
    );
  }
}

/// يُهيئ نظام الإشعارات — يُستدعى مرة واحدة قبل runApp.
Future<void> initNotifications() async {
  await flnp.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
  );
  await flnp
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

/// يعالج الضغط على زر التأجيل في المقدمة.
void _onNotificationResponse(NotificationResponse response) {
  if (response.actionId == _snoozeActionId) {
    final id = response.id ?? 0;
    final snoozeTime = DateTime.now().add(const Duration(minutes: 15));
    scheduleNotification(
      id: id,
      title: response.payload ?? 'Reminder',
      scheduledDate: snoozeTime,
    );
  }
}

/// يجدول إشعاراً في وقت محدد. يتخطى بصمت إذا كان التاريخ في الماضي.
Future<void> scheduleNotification({
  required int id,
  required String title,
  required DateTime scheduledDate,
}) async {
  if (scheduledDate.isBefore(DateTime.now())) return;
  await flnp.zonedSchedule(
    id: id,
    title: title,
    body: 'Tap to open Nabbihni',
    payload: title,
    scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
    notificationDetails: NotificationDetails(
      android: _androidDetails(withSnooze: true),
    ),
    androidScheduleMode: AndroidScheduleMode.alarmClock,
  );
}

/// يلغي إشعاراً مجدولاً.
Future<void> cancelNotification(int id) async {
  await flnp.cancel(id: id);
}

/// يؤجّل إشعاراً بإعادة جدولته بعد عدد محدد من الدقائق.
Future<void> snoozeNotification({
  required int id,
  required String title,
  int minutes = 15,
}) async {
  await cancelNotification(id);
  final snoozeTime = DateTime.now().add(Duration(minutes: minutes));
  await scheduleNotification(id: id, title: title, scheduledDate: snoozeTime);
}

/// يُطلق إشعاراً فورياً (يُستخدم لمشغلات السياج الجغرافي).
Future<void> showInstantNotification({
  required int id,
  required String title,
  required String body,
}) async {
  await flnp.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: _androidDetails(withSnooze: false),
    ),
  );
}
