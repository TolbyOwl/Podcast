import 'package:flutter/material.dart';

import '../../core/database/local_storage.dart';
import '../../core/services/audio_player_handler.dart';
import '../../core/services/download_manager.dart';
import '../../models/episode.dart';
import '../../models/playlist.dart';

class EpisodeDetailPage extends StatefulWidget {
  final Episode episode;
  final AudioPlayerHandler audioHandler;

  const EpisodeDetailPage({
    super.key,
    required this.episode,
    required this.audioHandler,
  });

  @override
  State<EpisodeDetailPage> createState() => _EpisodeDetailPageState();
}

class _EpisodeDetailPageState extends State<EpisodeDetailPage> {
  late Episode _episode;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _episode = widget.episode;
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final record = await LocalStorage.instance.getDownloadRecord(_episode.guid);
    if (record != null && mounted) {
      setState(() {
        _episode = _episode.copyWith(
          downloadStatus: DownloadStatus.downloaded,
          localFilePath: record['localFilePath'],
        );
      });
    }
  }

  Future<void> _toggleDownload() async {
    if (_episode.downloadStatus == DownloadStatus.downloaded) {
      await DownloadManager.instance.deleteDownload(_episode.guid);
      setState(() {
        _episode = _episode.copyWith(
          downloadStatus: DownloadStatus.notDownloaded,
          localFilePath: null,
        );
      });
    } else {
      setState(() => _isDownloading = true);
      await DownloadManager.instance.downloadEpisode(
        _episode,
        source: DownloadSource.manual,
      );
      await _checkStatus();
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _addToListenLater() async {
    final playlists = await LocalStorage.instance.getPlaylists();
    final listenLater = playlists.firstWhere((p) => p.id == 'listen_later');

    if (!listenLater.items.any((item) => item.guid == _episode.guid)) {
      listenLater.items.add(
        PlaylistItem(
          guid: _episode.guid,
          audioUrl: _episode.audioUrl,
          feedUrl: _episode.feedUrl,
          title: _episode.title,
          podcastTitle: _episode.podcastTitle,
          artworkUrl: _episode.artworkUrl,
          addedAt: DateTime.now(),
        ),
      );
      await LocalStorage.instance.savePlaylists(playlists);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to Listen Later')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already in Listen Later')),
        );
      }
    }
  }

  Future<void> _addToQueue() async {
    await widget.audioHandler.addToQueue(_episode);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Added to Up Next queue')));
    }
  }

  String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'Unknown duration';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloaded = _episode.downloadStatus == DownloadStatus.downloaded;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _episode.podcastTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add),
            tooltip: 'Add to Up Next',
            onPressed: _addToQueue,
          ),
          IconButton(
            icon: const Icon(Icons.watch_later_outlined),
            tooltip: 'Listen Later',
            onPressed: _addToListenLater,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Header Card
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _episode.artworkUrl.isNotEmpty
                        ? Image.network(
                            _episode.artworkUrl,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _artworkFallback(theme),
                          )
                        : _artworkFallback(theme),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _episode.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _episode.podcastTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: theme.colorScheme.onSurface.withOpacity(
                                0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(_episode.durationSeconds),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                            ),
                            if (_episode.publishedDate != null) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.calendar_today,
                                size: 13,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Released ${_episode.publishedDate!.year}-${_episode.publishedDate!.month.toString().padLeft(2, '0')}-${_episode.publishedDate!.day.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text(
                        'Play Episode',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        widget.audioHandler.playEpisode(_episode);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isDownloaded
                                ? Icons.download_done
                                : Icons.download_outlined,
                            color: isDownloaded ? Colors.green : null,
                          ),
                    label: Text(isDownloaded ? 'Downloaded' : 'Download'),
                    onPressed: _isDownloading ? null : _toggleDownload,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Show Notes / Description Section
              const Text(
                'Show Notes & Description',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: SelectableText(
                  _episode.description.isNotEmpty
                      ? _cleanHtml(_episode.description)
                      : 'No description provided for this episode.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: theme.colorScheme.onSurface.withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artworkFallback(ThemeData theme) {
    return Container(
      width: 110,
      height: 110,
      color: theme.colorScheme.primary.withOpacity(0.1),
      child: Icon(Icons.podcasts, size: 48, color: theme.colorScheme.primary),
    );
  }
}
