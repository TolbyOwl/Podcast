import 'dart:io';

import 'package:xml/xml.dart';

import '../../models/podcast.dart';
import '../../models/episode.dart';

class FeedParser {
  static (Podcast podcast, List<Episode> episodes) parseRss(
    String xmlString,
    String feedUrl,
  ) {
    final document = XmlDocument.parse(xmlString);
    final channel = document.findAllElements('channel').firstOrNull;

    if (channel == null) {
      throw Exception('Invalid RSS Feed: No <channel> element found');
    }

    final title = _getElementText(channel, 'title') ?? 'Untitled Podcast';
    final description = _getElementText(channel, 'description') ?? '';
    final author =
        _getElementText(channel, 'itunes:author') ??
        _getElementText(channel, 'author') ??
        'Unknown Author';

    String artworkUrl = '';
    final itunesImage = channel.findElements('itunes:image').firstOrNull;
    if (itunesImage != null) {
      artworkUrl = itunesImage.getAttribute('href') ?? '';
    }
    if (artworkUrl.isEmpty) {
      final imageElement = channel.findElements('image').firstOrNull;
      if (imageElement != null) {
        artworkUrl = _getElementText(imageElement, 'url') ?? '';
      }
    }

    final podcast = Podcast(
      feedUrl: feedUrl,
      title: title.trim(),
      author: author.trim(),
      description: description.trim(),
      artworkUrl: artworkUrl.trim(),
      subscribedAt: DateTime.now(),
    );

    final episodes = <Episode>[];
    final items = channel.findElements('item');

    for (final item in items) {
      final epTitle = _getElementText(item, 'title') ?? 'Untitled Episode';
      final epDesc =
          _getElementText(item, 'description') ??
          _getElementText(item, 'itunes:summary') ??
          '';

      // Guid
      final guidElement = item.findElements('guid').firstOrNull;
      final guid = guidElement?.innerText.trim().isNotEmpty == true
          ? guidElement!.innerText.trim()
          : '';

      // Enclosure (audio URL)
      final enclosure = item.findElements('enclosure').firstOrNull;
      final audioUrl = enclosure?.getAttribute('url') ?? '';
      if (audioUrl.isEmpty) continue; // skip non-audio items

      // Artwork
      String epArtwork = artworkUrl;
      final epItunesImage = item.findElements('itunes:image').firstOrNull;
      if (epItunesImage != null) {
        final href = epItunesImage.getAttribute('href');
        if (href != null && href.isNotEmpty) {
          epArtwork = href;
        }
      }

      // Published Date
      DateTime? publishedDate;
      final pubDateStr = _getElementText(item, 'pubDate');
      if (pubDateStr != null) {
        try {
          publishedDate = _parsePublishedDate(pubDateStr.trim());
        } catch (_) {}
      }

      // Duration (can be seconds or HH:MM:SS)
      int durationSeconds = 0;
      final durationStr = _getElementText(item, 'itunes:duration');
      if (durationStr != null) {
        durationSeconds = _parseDuration(durationStr);
      }

      episodes.add(
        Episode(
          guid: guid.isNotEmpty ? guid : audioUrl,
          feedUrl: feedUrl,
          title: epTitle.trim(),
          podcastTitle: title.trim(),
          description: epDesc.trim(),
          audioUrl: audioUrl.trim(),
          artworkUrl: epArtwork.trim(),
          publishedDate: publishedDate,
          durationSeconds: durationSeconds,
        ),
      );
    }

    return (podcast, episodes);
  }

  static DateTime? _parsePublishedDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;

    final rfcDate = RegExp(
      r'^(?:[A-Za-z]+,\s*)?(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
      r'(\d{1,2}):(\d{2})(?::(\d{2}))?\s+(GMT|UTC|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).firstMatch(value);
    if (rfcDate != null) {
      const months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };
      final month = months[rfcDate.group(2)!.toLowerCase()];
      if (month != null) {
        final utcDate = DateTime.utc(
          int.parse(rfcDate.group(3)!),
          month,
          int.parse(rfcDate.group(1)!),
          int.parse(rfcDate.group(4)!),
          int.parse(rfcDate.group(5)!),
          int.tryParse(rfcDate.group(6) ?? '') ?? 0,
        );
        final zone = rfcDate.group(7)!;
        if (zone.toUpperCase() == 'GMT' || zone.toUpperCase() == 'UTC') {
          return utcDate;
        }
        final sign = zone.startsWith('-') ? -1 : 1;
        final digits = zone.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 4) {
          final offsetMinutes =
              int.parse(digits.substring(0, 2)) * 60 +
              int.parse(digits.substring(2));
          return utcDate.subtract(Duration(minutes: sign * offsetMinutes));
        }
      }
    }

    try {
      return HttpDate.parse(value);
    } catch (_) {
      return null;
    }
  }

  static String? _getElementText(XmlElement parent, String tagName) {
    final elements = parent.findElements(tagName);
    if (elements.isEmpty) return null;
    return elements.first.innerText;
  }

  static int _parseDuration(String durationStr) {
    if (durationStr.contains(':')) {
      final parts = durationStr
          .split(':')
          .map((p) => int.tryParse(p) ?? 0)
          .toList();
      if (parts.length == 3) {
        return parts[0] * 3600 + parts[1] * 60 + parts[2];
      } else if (parts.length == 2) {
        return parts[0] * 60 + parts[1];
      }
    }
    return int.tryParse(durationStr) ?? 0;
  }
}
