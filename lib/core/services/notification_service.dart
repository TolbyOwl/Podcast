import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../models/episode.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'podcast_updates_channel';
  static const String _channelName = 'New Episode Alerts';
  static const String _channelDescription = 'Notifications for newly released podcast episodes';

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(initSettings);
    
    // Create notification channel explicitly
    await _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
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
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      channelShowBadge: true,
      number: badgeCount,
    );

    await _notificationsPlugin.show(
      id,
      'New Episode Available',
      episodeTitle,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> showEpisodeNotification(Episode episode) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      channelShowBadge: true,
    );

    await _notificationsPlugin.show(
      episode.guid.hashCode,
      'New Episode Available',
      episode.title,
      NotificationDetails(android: androidDetails),
    );
  }
}
