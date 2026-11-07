import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:workmanager/workmanager.dart';
import '../constants/app_constants.dart';
import '../database/local_storage.dart';
import 'feed_parser.dart';
import 'notification_service.dart';
import 'download_manager.dart';
import '../../models/episode.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    LocalStorage.initializeDatabase();
    await NotificationService.instance.init();

    try {
      final dio = Dio();
      final subs = await LocalStorage.instance.getSubscriptions();
      final settings = await LocalStorage.instance.getSettings();

      int notificationId = 100;
      int newEpisodesCount = 0;

      for (final sub in subs) {
        try {
          final response = await dio
              .get(sub.feedUrl)
              .timeout(const Duration(seconds: 20));
          if (response.statusCode == 200) {
            final (_, episodes) =
                FeedParser.parseRss(response.data.toString(), sub.feedUrl);

            if (episodes.isNotEmpty) {
              final latest = episodes.first;
              final history =
                  await LocalStorage.instance.getPlaybackHistory(latest.audioUrl);
              final existingDownload =
                  await LocalStorage.instance.getDownloadRecord(latest.guid);

              // Notify user of latest release if it's very recent (e.g. past 24 hours) and unplayed
              if (latest.publishedDate != null &&
                  DateTime.now().difference(latest.publishedDate!).inHours < 24 &&
                  history == null) {
                newEpisodesCount++;
                await NotificationService.instance.showNewEpisodeNotification(
                  id: notificationId++,
                  podcastTitle: sub.title,
                  episodeTitle: latest.title,
                  badgeCount: newEpisodesCount,
                );
              }

              // Auto-download if enabled and not already saved
              if (settings.autoDownloadGlobal &&
                  sub.autoDownloadCount > 0 &&
                  existingDownload == null) {
                await DownloadManager.instance.downloadEpisode(
                  latest,
                  source: DownloadSource.auto,
                );
              }
            }
          }
        } catch (_) {
          // Continue with remaining feeds even if one fails
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  });
}

class BackgroundWorker {
  static void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static void schedulePeriodicCheck({int intervalHours = 3}) {
    Workmanager().registerPeriodicTask(
      AppConstants.syncTaskName,
      AppConstants.syncTaskName,
      tag: AppConstants.syncTaskTag,
      frequency: Duration(hours: intervalHours),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}
