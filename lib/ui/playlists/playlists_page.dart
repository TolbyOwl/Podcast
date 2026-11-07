import 'package:flutter/material.dart';

import '../../core/database/local_storage.dart';
import '../../core/events/app_events.dart';
import '../../core/services/audio_player_handler.dart';
import '../../core/services/download_manager.dart';
import '../../core/services/new_episodes_service.dart';
import '../../models/episode.dart';
import '../../models/playlist.dart';
import '../player/mini_player_bar.dart';

class PlaylistsPage extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const PlaylistsPage({super.key, required this.audioHandler});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  // New Episodes state (inside New Episodes playlist)
  List<Episode> _newEpisodes = [];
  bool _isLoadingNew = true;
  String? _newEpisodesError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlaylists();
    _loadNewEpisodes();
    AppEvents.subscriptionsChanged.addListener(_onSubscriptionsChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    AppEvents.subscriptionsChanged.removeListener(_onSubscriptionsChanged);
    super.dispose();
  }

  void _onSubscriptionsChanged() {
    _loadNewEpisodes();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final list = await LocalStorage.instance.getPlaylists();
    if (mounted) {
      setState(() {
        _playlists = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadNewEpisodes() async {
    if (mounted) {
      setState(() {
        _isLoadingNew = true;
        _newEpisodesError = null;
      });
    }
    try {
      final episodes = await NewEpisodesService.instance.fetchNewEpisodes(
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _newEpisodes = episodes;
          _isLoadingNew = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _newEpisodesError = 'Could not load episodes: $e';
          _isLoadingNew = false;
        });
      }
    }
  }

  Future<void> _createPlaylistDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newPl = Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        items: [],
        createdAt: DateTime.now(),
      );
      final updated = [..._playlists, newPl];
      await LocalStorage.instance.savePlaylists(updated);
      _loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists & Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Playlist',
            onPressed: _createPlaylistDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.6),
          tabs: const [
            Tab(text: 'Playlists'),
            Tab(text: 'Up Next'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPlaylistsTab(theme),
                _buildQueueTab(theme),
              ],
            ),
    );
  }

  // ─── Playlists Tab ──────────────────────────────────────────────────────────

  Widget _buildPlaylistsTab(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final isNewEpisodes = playlist.id == 'new_episodes';
        final isListenLater = playlist.id == 'listen_later';

        IconData iconData = Icons.playlist_play;
        String subtitleText = '${playlist.items.length} episodes';

        if (isNewEpisodes) {
          iconData = Icons.new_releases_outlined;
          subtitleText = _isLoadingNew
              ? 'Checking latest releases...'
              : '${_newEpisodes.length} new episodes';
        } else if (isListenLater) {
          iconData = Icons.watch_later_outlined;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
              child: Icon(
                iconData,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(
              playlist.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(subtitleText),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (isNewEpisodes) {
                _openNewEpisodesPlaylist();
              } else {
                _showPlaylistItems(playlist);
              }
            },
          ),
        );
      },
    );
  }

  void _openNewEpisodesPlaylist() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('New Episodes'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _loadNewEpisodes,
              ),
            ],
          ),
          body: _buildNewEpisodesBody(Theme.of(ctx)),
          bottomNavigationBar: MiniPlayerBar(audioHandler: widget.audioHandler),
        ),
      ),
    );
  }

  Widget _buildNewEpisodesBody(ThemeData theme) {
    if (_isLoadingNew) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_newEpisodesError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _newEpisodesError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _loadNewEpisodes,
            ),
          ],
        ),
      );
    }
    if (_newEpisodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.new_releases_outlined,
              size: 60,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 14),
            const Text(
              'No New Episodes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Subscribe to podcasts to see their latest episodes here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNewEpisodes,
      child: ListView.builder(
        itemCount: _newEpisodes.length,
        itemBuilder: (context, index) {
          final ep = _newEpisodes[index];
          return _NewEpisodeTile(
            episode: ep,
            audioHandler: widget.audioHandler,
            onRefresh: _loadNewEpisodes,
          );
        },
      ),
    );
  }

  // ─── Queue Tab ──────────────────────────────────────────────────────────────

  Widget _buildQueueTab(ThemeData theme) {
    return ListenableBuilder(
      listenable: widget.audioHandler,
      builder: (context, _) {
        final queue = widget.audioHandler.episodeQueue;

        if (queue.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.queue_music,
                  size: 54,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your queue is empty',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Episodes you add to play next will appear here.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: queue.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              widget.audioHandler.reorderQueue(oldIndex, newIndex);
            });
          },
          itemBuilder: (context, index) {
            final ep = queue[index];
            return ListTile(
              key: ValueKey(ep.guid),
              leading: IconButton(
                icon: const Icon(Icons.play_circle_outline, size: 28),
                color: theme.colorScheme.primary,
                tooltip: 'Play now',
                onPressed: () {
                  widget.audioHandler.removeFromQueue(index);
                  widget.audioHandler.playEpisode(ep);
                },
              ),
              title: Text(ep.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(ep.podcastTitle, maxLines: 1),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove from queue',
                    onPressed: () {
                      setState(() {
                        widget.audioHandler.removeFromQueue(index);
                      });
                    },
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Playlist Detail Sheet ──────────────────────────────────────────────────

  void _showPlaylistItems(Playlist playlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    playlist.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: playlist.items.isEmpty
                      ? const Center(
                          child: Text('No episodes in this playlist yet.'),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: playlist.items.length,
                          itemBuilder: (context, i) {
                            final item = playlist.items[i];
                            return ListTile(
                              leading: IconButton(
                                icon: const Icon(Icons.play_circle_filled),
                                color: Theme.of(context).colorScheme.primary,
                                onPressed: () {
                                  widget.audioHandler.playEpisode(
                                    Episode(
                                      guid: item.guid,
                                      feedUrl: item.feedUrl,
                                      title: item.title,
                                      podcastTitle: item.podcastTitle,
                                      audioUrl: item.audioUrl,
                                      artworkUrl: item.artworkUrl,
                                    ),
                                  );
                                },
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(item.podcastTitle, maxLines: 1),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─── New Episode Tile ─────────────────────────────────────────────────────────

class _NewEpisodeTile extends StatelessWidget {
  final Episode episode;
  final AudioPlayerHandler audioHandler;
  final VoidCallback onRefresh;

  const _NewEpisodeTile({
    required this.episode,
    required this.audioHandler,
    required this.onRefresh,
  });

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return dt.toString().substring(0, 10);
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final mins = (seconds / 60).round();
    return '$mins min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ep = episode;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ep.artworkUrl.isNotEmpty
            ? Image.network(
                ep.artworkUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _artFallback(theme),
              )
            : _artFallback(theme),
      ),
      title: Text(
        ep.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: ep.isPlayed
              ? theme.colorScheme.onSurface.withOpacity(0.45)
              : null,
        ),
      ),
      subtitle: Text(
        '${ep.podcastTitle}  •  ${_formatDate(ep.publishedDate)}  ${_formatDuration(ep.durationSeconds)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ep.downloadStatus == DownloadStatus.downloaded)
            const Icon(Icons.download_done, color: Colors.green, size: 20)
          else
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Download',
              onPressed: () => DownloadManager.instance.downloadEpisode(
                ep,
                source: DownloadSource.manual,
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'Episode options',
            onSelected: (choice) async {
              if (choice == 'play_next') {
                await audioHandler.playNext(ep);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Playing next')));
                }
              } else if (choice == 'add_queue') {
                await audioHandler.addToQueue(ep);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to queue')),
                  );
                }
              } else if (choice == 'mark_played') {
                if (ep.isPlayed) {
                  await LocalStorage.instance.removePlaybackHistory(
                    ep.audioUrl,
                  );
                } else {
                  await LocalStorage.instance.recordPlayback(
                    audioUrl: ep.audioUrl,
                    feedUrl: ep.feedUrl,
                    episodeTitle: ep.title,
                    podcastTitle: ep.podcastTitle,
                    positionSeconds: ep.durationSeconds,
                    durationSeconds: ep.durationSeconds,
                    completed: true,
                  );
                }
                onRefresh();
              } else if (choice == 'listen_later') {
                final playlists = await LocalStorage.instance.getPlaylists();
                final listenLater = playlists.firstWhere(
                  (p) => p.id == 'listen_later',
                );
                if (!listenLater.items.any((item) => item.guid == ep.guid)) {
                  listenLater.items.add(
                    PlaylistItem(
                      guid: ep.guid,
                      audioUrl: ep.audioUrl,
                      feedUrl: ep.feedUrl,
                      title: ep.title,
                      podcastTitle: ep.podcastTitle,
                      artworkUrl: ep.artworkUrl,
                      addedAt: DateTime.now(),
                    ),
                  );
                  await LocalStorage.instance.savePlaylists(playlists);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to Listen Later')),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'play_next',
                child: Row(
                  children: [
                    Icon(Icons.playlist_play, size: 20),
                    SizedBox(width: 8),
                    Text('Play Next'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add_queue',
                child: Row(
                  children: [
                    Icon(Icons.queue_music, size: 20),
                    SizedBox(width: 8),
                    Text('Add to Queue'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'mark_played',
                child: Row(
                  children: [
                    Icon(
                      ep.isPlayed
                          ? Icons.radio_button_unchecked
                          : Icons.check_circle_outline,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(ep.isPlayed ? 'Mark as Unplayed' : 'Mark as Listened'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'listen_later',
                child: Row(
                  children: [
                    Icon(Icons.watch_later_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Listen Later'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      onTap: () => audioHandler.playEpisode(ep),
    );
  }

  Widget _artFallback(ThemeData theme) {
    return Container(
      width: 48,
      height: 48,
      color: theme.colorScheme.primary.withOpacity(0.1),
      child: Icon(
        Icons.podcasts,
        size: 24,
        color: theme.colorScheme.primary.withOpacity(0.5),
      ),
    );
  }
}
