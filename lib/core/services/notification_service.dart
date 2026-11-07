import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);
  }

  Future<bool?> requestPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.requestNotificationsPermission();
    }
    return true;
  }

  Future<void> showNewEpisodeNotification({
    required int id,
    required String podcastTitle,
    required String episodeTitle,
    int? badgeCount,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'podcast_channel',
      'New Episodes',
      channelDescription: 'Notifications for newly released podcast episodes',
      importance: Importance.high,
      priority: Priority.high,
      channelShowBadge: true,
      number: badgeCount,
    );

    await _notificationsPlugin.show(
      id,
      podcastTitle,
      'New episode: $episodeTitle',
      NotificationDetails(android: androidDetails),
    );
  }
}
