import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import '../../models/podcast.dart';
import '../database/local_storage.dart';

class OpmlService {
  /// Exports current subscriptions to an OPML string and saves it
  static Future<bool> exportOpml() async {
    final subs = await LocalStorage.instance.getSubscriptions();
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      builder.element('head', nest: () {
        builder.element('title', nest: 'Podcast Subscriptions');
        builder.element('dateCreated', nest: DateTime.now().toUtc().toIso8601String());
      });
      builder.element('body', nest: () {
        for (final sub in subs) {
          builder.element('outline', attributes: {
            'text': sub.title,
            'title': sub.title,
            'type': 'rss',
            'xmlUrl': sub.feedUrl,
            'htmlUrl': '',
          });
        }
      });
    });

    final opmlXml = builder.buildDocument().toXmlString(pretty: true);

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export OPML Subscriptions',
      fileName: 'podcast_subscriptions.opml',
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsString(opmlXml);
      return true;
    }
    return false;
  }

  /// Imports subscriptions from an OPML file
  static Future<int> importOpml() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['opml', 'xml'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final document = XmlDocument.parse(content);
      final outlines = document.findAllElements('outline');

      final existingSubs = await LocalStorage.instance.getSubscriptions();
      final existingFeeds = existingSubs.map((s) => s.feedUrl).toSet();
      int addedCount = 0;

      for (final outline in outlines) {
        final xmlUrl = outline.getAttribute('xmlUrl');
        if (xmlUrl != null && xmlUrl.isNotEmpty && !existingFeeds.contains(xmlUrl)) {
          final title = outline.getAttribute('text') ??
              outline.getAttribute('title') ??
              'Imported Podcast';
          existingSubs.add(Podcast(
            feedUrl: xmlUrl,
            title: title,
            author: 'Unknown',
            artworkUrl: '',
            subscribedAt: DateTime.now(),
          ));
          existingFeeds.add(xmlUrl);
          addedCount++;
        }
      }

      if (addedCount > 0) {
        await LocalStorage.instance.saveSubscriptions(existingSubs);
      }
      return addedCount;
    }
    return 0;
  }
}
