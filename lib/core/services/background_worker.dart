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
              final alreadyNotified = await LocalStorage.instance.isEpisodeNotified(latest.guid);

              // Notify user of new episode if not already notified and not played
              if (!alreadyNotified && history == null) {
                await NotificationService.instance.showEpisodeNotification(latest);
                await LocalStorage.instance.recordNotifiedEpisode(
                  guid: latest.guid,
                  feedUrl: latest.feedUrl,
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
    Workmanager().initialize(callbackDispatcher);
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
