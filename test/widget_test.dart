import 'package:flutter_test/flutter_test.dart';
import 'package:podcast/models/app_settings.dart';
import 'package:podcast/models/podcast.dart';
import 'package:podcast/models/episode.dart';
import 'package:podcast/core/services/feed_parser.dart';

void main() {
  test('Podcast serialization and defaults', () {
    final podcast = Podcast(
      feedUrl: 'https://example.com/feed.xml',
      title: 'Sample Show',
      author: 'Creator',
      artworkUrl: 'https://example.com/art.jpg',
      subscribedAt: DateTime.now(),
      autoDownloadCount: 3,
    );

    final json = podcast.toJson();
    final restored = Podcast.fromJson(json);

    expect(restored.feedUrl, 'https://example.com/feed.xml');
    expect(restored.title, 'Sample Show');
    expect(restored.autoDownloadCount, 3);
  });

  test('AppSettings default theme and download rules', () {
    final settings = AppSettings();
    expect(settings.themeMode, 'amoled');
    expect(settings.accentColorHex, '#7C4DFF');
    expect(settings.autoDeleteOnCompletion, true);
    expect(settings.autoDownloadEpisodesPerSub, 2);
  });

  test('Episode manual vs auto download source serialization', () {
    final manualEp = Episode(
      guid: 'ep-001',
      feedUrl: 'https://example.com/feed.xml',
      title: 'Ep 1',
      podcastTitle: 'Show',
      audioUrl: 'https://example.com/ep1.mp3',
      downloadSource: DownloadSource.manual,
      downloadStatus: DownloadStatus.downloaded,
    );

    final autoEp = Episode(
      guid: 'ep-002',
      feedUrl: 'https://example.com/feed.xml',
      title: 'Ep 2',
      podcastTitle: 'Show',
      audioUrl: 'https://example.com/ep2.mp3',
      downloadSource: DownloadSource.auto,
      downloadStatus: DownloadStatus.downloaded,
    );

    expect(
      Episode.fromJson(manualEp.toJson()).downloadSource,
      DownloadSource.manual,
    );
    expect(
      Episode.fromJson(autoEp.toJson()).downloadSource,
      DownloadSource.auto,
    );
  });

  test('Feed parser reads RFC 822 release dates', () {
    const rss = '''
      <rss version="2.0">
        <channel>
          <title>O Assunto</title>
          <item>
            <title>Latest episode</title>
            <guid>episode-1</guid>
            <pubDate>Thu, 05 Nov 2026 03:17:25 +0000</pubDate>
            <enclosure url="https://example.com/episode.mp3"/>
          </item>
        </channel>
      </rss>
    ''';

    final (_, episodes) = FeedParser.parseRss(
      rss,
      'https://example.com/feed.xml',
    );

    expect(episodes, hasLength(1));
    expect(episodes.single.publishedDate, DateTime.utc(2026, 11, 5, 3, 17, 25));
  });
}
