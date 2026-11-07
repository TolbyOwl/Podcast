import 'package:dio/dio.dart';

import '../../models/episode.dart';
import '../../models/podcast.dart';
import '../database/local_storage.dart';
import '../services/feed_parser.dart';

class NewEpisodesService {
  static final NewEpisodesService instance = NewEpisodesService._internal();
  NewEpisodesService._internal();

  /// Fetches RSS feeds for all subscriptions concurrently and returns the 50
  /// newest episodes sorted by publication date descending.
  Future<List<Episode>> fetchNewEpisodes({int limit = 50}) async {
    final subscriptions = await LocalStorage.instance.getSubscriptions();
    if (subscriptions.isEmpty) return [];

    final dio = Dio();
    final futures = subscriptions
        .map((podcast) => _fetchFeed(dio, podcast))
        .toList();

    // Gather results, ignore individual failures
    final results = await Future.wait(futures, eagerError: false);

    final allEpisodes = <Episode>[];
    for (final episodeList in results) {
      allEpisodes.addAll(episodeList);
    }

    // Sort newest first and take the top [limit]
    allEpisodes.sort((a, b) {
      final dateA = a.publishedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.publishedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });

    final top = allEpisodes.take(limit).toList();

    // Enrich with download / playback status
    final enriched = <Episode>[];
    for (final ep in top) {
      final downloadRecord = await LocalStorage.instance.getDownloadRecord(
        ep.guid,
      );
      final historyRecord = await LocalStorage.instance.getPlaybackHistory(
        ep.audioUrl,
      );
      final isPlayed =
          historyRecord != null && (historyRecord['completed'] == 1);
      enriched.add(
        ep.copyWith(
          downloadStatus: downloadRecord != null
              ? DownloadStatus.downloaded
              : DownloadStatus.notDownloaded,
          localFilePath: downloadRecord?['localFilePath'],
          isPlayed: isPlayed,
          positionSeconds: historyRecord?['positionSeconds'] ?? 0,
        ),
      );
    }

    return enriched;
  }

  Future<List<Episode>> _fetchFeed(Dio dio, Podcast podcast) async {
    try {
      final response = await dio
          .get(podcast.feedUrl)
          .timeout(const Duration(seconds: 15));
      final (_, episodes) = FeedParser.parseRss(
        response.data.toString(),
        podcast.feedUrl,
      );
      return episodes;
    } catch (_) {
      return [];
    }
  }
}
