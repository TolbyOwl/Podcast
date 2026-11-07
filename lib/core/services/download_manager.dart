import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../models/episode.dart';
import '../database/local_storage.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager instance = DownloadManager._internal();
  DownloadManager._internal();

  final Dio _dio = Dio();
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, double> _progressMap = {};

  double getProgress(String guid) => _progressMap[guid] ?? 0.0;
  bool isDownloading(String guid) => _cancelTokens.containsKey(guid);

  Future<String> _getStorageDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(appDir.path, 'podcast_downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  /// Downloads an episode and records whether it was manually triggered or automated
  Future<void> downloadEpisode(Episode episode, {required DownloadSource source}) async {
    if (isDownloading(episode.guid)) return;

    final dirPath = await _getStorageDir();
    // Sanitize file name
    final safeFileName = '${episode.guid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.mp3';
    final savePath = p.join(dirPath, safeFileName);

    final cancelToken = CancelToken();
    _cancelTokens[episode.guid] = cancelToken;
    _progressMap[episode.guid] = 0.0;
    notifyListeners();

    try {
      await _dio.download(
        episode.audioUrl,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _progressMap[episode.guid] = received / total;
            notifyListeners();
          }
        },
      );

      // Successfully downloaded: register in SQLite
      await LocalStorage.instance.recordDownload(
        episode: episode,
        localPath: savePath,
        source: source,
      );

      // If it was an auto-download, enforce the retention quota for this show
      if (source == DownloadSource.auto) {
        await _enforceRetentionQuota(episode.feedUrl);
      }
    } catch (e) {
      if (!cancelToken.isCancelled) {
        debugPrint('Download error for ${episode.title}: $e');
      }
      // Clean up partial file
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
    } finally {
      _cancelTokens.remove(episode.guid);
      _progressMap.remove(episode.guid);
      notifyListeners();
    }
  }

  /// Downloads multiple episodes in batch (manually selected)
  Future<void> downloadBatch(List<Episode> episodes) async {
    for (final episode in episodes) {
      // Fire downloads sequentially or concurrent pool
      await downloadEpisode(episode, source: DownloadSource.manual);
    }
  }

  /// Cancel an ongoing download
  void cancelDownload(String guid) {
    if (_cancelTokens.containsKey(guid)) {
      _cancelTokens[guid]!.cancel();
      _cancelTokens.remove(guid);
      _progressMap.remove(guid);
      notifyListeners();
    }
  }

  /// Delete a local download file and remove from database
  Future<void> deleteDownload(String guid) async {
    final record = await LocalStorage.instance.getDownloadRecord(guid);
    if (record != null) {
      final path = record['localFilePath'] as String;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      await LocalStorage.instance.removeDownloadRecord(guid);
      notifyListeners();
    }
  }

  /// Autodeletion on completion (called when an episode finishes playing)
  Future<void> onEpisodeFinished(Episode episode) async {
    final settings = await LocalStorage.instance.getSettings();
    if (settings.autoDeleteOnCompletion) {
      // If toggled on, deletes completed file whether auto or manual
      await deleteDownload(episode.guid);
    }
  }

  /// Quota management: keeps only the last X auto-downloaded episodes per show
  Future<void> _enforceRetentionQuota(String feedUrl) async {
    final subs = await LocalStorage.instance.getSubscriptions();
    final podcast = subs.where((s) => s.feedUrl == feedUrl).firstOrNull;
    final maxKeep = podcast?.autoDownloadCount ?? 2;

    if (maxKeep <= 0) return; // unlimited or disabled

    // Get ONLY auto-downloaded episodes for this feed (ordered oldest first)
    final autoDownloads = await LocalStorage.instance.getAutoDownloadsForFeed(feedUrl);

    if (autoDownloads.length > maxKeep) {
      final excessCount = autoDownloads.length - maxKeep;
      // Remove oldest excess items
      for (int i = 0; i < excessCount; i++) {
        final item = autoDownloads[i];
        final guid = item['guid'] as String;
        final path = item['localFilePath'] as String;

        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        await LocalStorage.instance.removeDownloadRecord(guid);
      }
    }
  }
}
