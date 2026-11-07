import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/local_storage.dart';
import '../../core/events/app_events.dart';
import '../../core/services/audio_player_handler.dart';
import '../../core/services/download_manager.dart';
import '../../core/services/feed_parser.dart';
import '../../models/podcast.dart';
import '../../models/episode.dart';
import '../../models/playlist.dart';
import '../episode_detail/episode_detail_page.dart';
import '../player/mini_player_bar.dart';

class PodcastDetailPage extends StatefulWidget {
  final Podcast podcast;
  final AudioPlayerHandler audioHandler;

  const PodcastDetailPage({
    super.key,
    required this.podcast,
    required this.audioHandler,
  });

  @override
  State<PodcastDetailPage> createState() => _PodcastDetailPageState();
}

class _PodcastDetailPageState extends State<PodcastDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _episodesScrollController = ScrollController();
  bool _showPodcastExtras = true;
  bool _isLoading = true;
  String? _errorMessage;
  List<Episode> _episodes = [];
  List<Episode> _filteredEpisodes = [];

  // Subscription state
  bool _isSubscribed = false;

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedEpisodeGuids = {};

  // Filter & Search
  String _filter = 'all'; // 'all', 'unplayed', 'downloaded'
  String _sortOrder = 'newest'; // 'newest', 'oldest'
  final TextEditingController _searchController = TextEditingController();

  late int _autoDownloadLimit;
  List<Podcast> _similarPodcasts = [];
  bool _isLoadingSimilar = false;

  String _podcastDescription = '';
  bool _isDescriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _podcastDescription = widget.podcast.description;
    _autoDownloadLimit = widget.podcast.autoDownloadCount;
    _checkSubscribed();
    _fetchEpisodes();
    _fetchSimilar();
    _searchController.addListener(_applyFilters);
    _episodesScrollController.addListener(_handleEpisodeScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _episodesScrollController.removeListener(_handleEpisodeScroll);
    _episodesScrollController.dispose();
    super.dispose();
  }

  void _handleEpisodeScroll() {
    final showExtras = _episodesScrollController.offset <= 15;
    if (showExtras != _showPodcastExtras && mounted) {
      setState(() => _showPodcastExtras = showExtras);
    }
  }

  Future<void> _scrollToTop() async {
    await _episodesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    if (mounted) setState(() => _showPodcastExtras = true);
  }

  Future<void> _checkSubscribed() async {
    final subs = await LocalStorage.instance.getSubscriptions();
    final idx = subs.indexWhere((s) => s.feedUrl == widget.podcast.feedUrl);
    if (mounted) {
      setState(() {
        _isSubscribed = idx != -1;
        if (idx != -1) {
          _autoDownloadLimit = subs[idx].autoDownloadCount;
        }
      });
    }
  }

  Future<void> _toggleSubscription() async {
    final subs = await LocalStorage.instance.getSubscriptions();
    final idx = subs.indexWhere((s) => s.feedUrl == widget.podcast.feedUrl);

    if (idx != -1) {
      subs.removeAt(idx);
      setState(() => _isSubscribed = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unsubscribed from ${widget.podcast.title}')),
        );
      }
    } else {
      subs.add(
        widget.podcast.copyWith(
          description: _podcastDescription.isNotEmpty
              ? _podcastDescription
              : widget.podcast.description,
          autoDownloadCount: _autoDownloadLimit,
        ),
      );
      setState(() => _isSubscribed = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscribed to ${widget.podcast.title}!')),
        );
      }
    }
    await LocalStorage.instance.saveSubscriptions(subs);
    AppEvents.notifySubscriptionsChanged();
  }

  Future<void> _fetchSimilar() async {
    setState(() => _isLoadingSimilar = true);
    try {
      final settings = await LocalStorage.instance.getSettings();
      final country = settings.countryCode;
      final query = widget.podcast.author.isNotEmpty
          ? widget.podcast.author
          : widget.podcast.title.split(' ').first;
      final dio = Dio();
      final url =
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=podcast&entity=podcast&country=$country&limit=15';
      final response = await dio.get(url);
      if (response.statusCode == 200) {
        final data = response.data is Map ? response.data : null;
        if (data != null && data['results'] != null) {
          final results = data['results'] as List<dynamic>;
          final list = <Podcast>[];
          for (final item in results) {
            final feed = item['feedUrl'];
            if (feed != null && feed != widget.podcast.feedUrl) {
              list.add(
                Podcast(
                  feedUrl: feed,
                  title: item['collectionName'] ?? 'Untitled',
                  author: item['artistName'] ?? '',
                  artworkUrl:
                      item['artworkUrl600'] ?? item['artworkUrl100'] ?? '',
                  subscribedAt: DateTime.now(),
                ),
              );
            }
          }
          if (mounted) setState(() => _similarPodcasts = list);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingSimilar = false);
    }
  }

  Future<void> _fetchEpisodes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = Dio();
      final response = await dio.get(widget.podcast.feedUrl);
      final (parsedPodcast, parsedEpisodes) = FeedParser.parseRss(
        response.data.toString(),
        widget.podcast.feedUrl,
      );
      if (parsedPodcast.description.isNotEmpty) {
        _podcastDescription = parsedPodcast.description;
      }

      final updatedList = <Episode>[];
      for (final ep in parsedEpisodes) {
        final downloadRecord = await LocalStorage.instance.getDownloadRecord(
          ep.guid,
        );
        final historyRecord = await LocalStorage.instance.getPlaybackHistory(
          ep.audioUrl,
        );
        final isPlayed =
            historyRecord != null && (historyRecord['completed'] == 1);

        updatedList.add(
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

      setState(() {
        _episodes = updatedList;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not load podcast feed: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      final list = _episodes.where((ep) {
        final matchesQuery =
            query.isEmpty ||
            ep.title.toLowerCase().contains(query) ||
            ep.description.toLowerCase().contains(query);

        bool matchesFilter = true;
        if (_filter == 'downloaded') {
          matchesFilter = ep.downloadStatus == DownloadStatus.downloaded;
        } else if (_filter == 'unplayed') {
          matchesFilter = !ep.isPlayed;
        }

        return matchesQuery && matchesFilter;
      }).toList();

      list.sort((a, b) {
        final dateA = a.publishedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = b.publishedDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return _sortOrder == 'newest'
            ? dateB.compareTo(dateA)
            : dateA.compareTo(dateB);
      });

      _filteredEpisodes = list;
    });
  }

  void _toggleSelection(String guid) {
    setState(() {
      if (_selectedEpisodeGuids.contains(guid)) {
        _selectedEpisodeGuids.remove(guid);
        if (_selectedEpisodeGuids.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedEpisodeGuids.add(guid);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedEpisodeGuids.addAll(_filteredEpisodes.map((e) => e.guid));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedEpisodeGuids.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _downloadSelected() async {
    final toDownload = _episodes
        .where((e) => _selectedEpisodeGuids.contains(e.guid))
        .toList();
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${toDownload.length} episodes...')),
    );
    await DownloadManager.instance.downloadBatch(toDownload);
    _fetchEpisodes();
  }

  Future<void> _addSelectedToQueue({bool playNext = false}) async {
    final toAdd = _episodes
        .where((e) => _selectedEpisodeGuids.contains(e.guid))
        .toList();
    for (final ep in (playNext ? toAdd.reversed : toAdd)) {
      if (playNext) {
        await widget.audioHandler.playNext(ep);
      } else {
        await widget.audioHandler.addToQueue(ep);
      }
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toAdd.length} episodes ${playNext ? "set to play next" : "added to queue"}',
          ),
        ),
      );
    }
  }

  Future<void> _markSelectedPlayedStatus(bool played) async {
    final toUpdate = _episodes
        .where((e) => _selectedEpisodeGuids.contains(e.guid))
        .toList();
    for (final ep in toUpdate) {
      if (played) {
        await LocalStorage.instance.recordPlayback(
          audioUrl: ep.audioUrl,
          feedUrl: ep.feedUrl,
          episodeTitle: ep.title,
          podcastTitle: ep.podcastTitle,
          positionSeconds: ep.durationSeconds,
          durationSeconds: ep.durationSeconds,
          completed: true,
        );
        // Smart auto-deletion on completion if enabled
        await DownloadManager.instance.onEpisodeFinished(ep);
      } else {
        await LocalStorage.instance.removePlaybackHistory(ep.audioUrl);
      }
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${toUpdate.length} episodes marked as ${played ? "listened" : "unplayed"}',
          ),
        ),
      );
    }
    _fetchEpisodes();
  }

  Future<void> _markSinglePlayedStatus(Episode ep, bool played) async {
    if (played) {
      await LocalStorage.instance.recordPlayback(
        audioUrl: ep.audioUrl,
        feedUrl: ep.feedUrl,
        episodeTitle: ep.title,
        podcastTitle: ep.podcastTitle,
        positionSeconds: ep.durationSeconds,
        durationSeconds: ep.durationSeconds,
        completed: true,
      );
      await DownloadManager.instance.onEpisodeFinished(ep);
    } else {
      await LocalStorage.instance.removePlaybackHistory(ep.audioUrl);
    }
    _fetchEpisodes();
  }

  Future<void> _addToListenLater() async {
    final playlists = await LocalStorage.instance.getPlaylists();
    final listenLater = playlists.firstWhere((p) => p.id == 'listen_later');
    final toAdd = _episodes
        .where((e) => _selectedEpisodeGuids.contains(e.guid))
        .toList();

    for (final ep in toAdd) {
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
      }
    }
    await LocalStorage.instance.savePlaylists(playlists);
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${toAdd.length} episodes to Listen Later'),
        ),
      );
    }
  }

  String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _sharePodcast() async {
    final title = widget.podcast.title;
    final feedUrl = widget.podcast.feedUrl;
    final shareText = 'Check out "$title" podcast: $feedUrl';

    // Copy to clipboard unconditionally for reliability across all desktop environments
    await Clipboard.setData(ClipboardData(text: shareText));

    try {
      await Share.share(shareText);
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Podcast link copied to clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedEpisodeGuids.length} Selected'
              : widget.podcast.title,
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: 'Select All',
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _clearSelection,
            ),
          ] else ...[
            IconButton(
              icon: Icon(
                _isSubscribed ? Icons.check_circle : Icons.add_circle_outline,
              ),
              color: _isSubscribed ? Colors.green : theme.colorScheme.primary,
              tooltip: _isSubscribed ? 'Subscribed' : 'Subscribe',
              onPressed: _toggleSubscription,
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share Podcast',
              onPressed: _sharePodcast,
            ),
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Multi-Select',
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
            ),
            PopupMenuButton<int>(
              tooltip: 'Auto-Download Options',
              icon: const Icon(Icons.settings_outlined),
              initialValue: _autoDownloadLimit,
              onSelected: (val) async {
                setState(() {
                  _autoDownloadLimit = val;
                });
                final subs = await LocalStorage.instance.getSubscriptions();
                final idx = subs.indexWhere(
                  (s) => s.feedUrl == widget.podcast.feedUrl,
                );
                if (idx != -1) {
                  subs[idx] = subs[idx].copyWith(autoDownloadCount: val);
                  await LocalStorage.instance.saveSubscriptions(subs);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  enabled: false,
                  child: Text(
                    'Auto-Download limit:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const PopupMenuItem(
                  value: 0,
                  child: Text('Off (Do not auto-download)'),
                ),
                const PopupMenuItem(
                  value: 1,
                  child: Text('Keep latest 1 episode'),
                ),
                const PopupMenuItem(
                  value: 2,
                  child: Text('Keep latest 2 episodes'),
                ),
                const PopupMenuItem(
                  value: 3,
                  child: Text('Keep latest 3 episodes'),
                ),
                const PopupMenuItem(
                  value: 5,
                  child: Text('Keep latest 5 episodes'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(child: Text(_errorMessage!))
          : Column(
              children: [
                // Header Card
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: widget.podcast.artworkUrl.isNotEmpty
                                ? Image.network(
                                    widget.podcast.artworkUrl,
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 80,
                                      height: 80,
                                      color: theme.dividerColor,
                                    ),
                                  )
                                : Container(
                                    width: 80,
                                    height: 80,
                                    color: theme.dividerColor,
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.podcast.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.podcast.author,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSubscribed
                                            ? theme.cardColor
                                            : theme.colorScheme.primary,
                                        foregroundColor: _isSubscribed
                                            ? Colors.green
                                            : Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          side: BorderSide(
                                            color: _isSubscribed
                                                ? Colors.green
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                      icon: Icon(
                                        _isSubscribed ? Icons.check : Icons.add,
                                        size: 16,
                                      ),
                                      label: Text(
                                        _isSubscribed
                                            ? 'Subscribed'
                                            : 'Subscribe',
                                      ),
                                      onPressed: _toggleSubscription,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${_episodes.length} Episodes',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurface
                                            .withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Podcast Description (Expandable)
                      if (_podcastDescription.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          alignment: Alignment.topCenter,
                          child: _showPodcastExtras
                              ? InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    setState(() {
                                      _isDescriptionExpanded =
                                          !_isDescriptionExpanded;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _cleanHtml(_podcastDescription),
                                          maxLines: _isDescriptionExpanded
                                              ? null
                                              : 3,
                                          overflow: _isDescriptionExpanded
                                              ? TextOverflow.visible
                                              : TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.45,
                                            color: theme.colorScheme.onSurface
                                                .withOpacity(0.75),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _isDescriptionExpanded
                                              ? 'Show less'
                                              : 'Read more...',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Two Tabs: Episodes & Similar Podcasts
                TabBar(
                  controller: _tabController,
                  indicatorColor: theme.colorScheme.primary,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(
                    0.6,
                  ),
                  tabs: [
                    Tab(text: 'Episodes (${_episodes.length})'),
                    Tab(text: 'You May Also Like (${_similarPodcasts.length})'),
                  ],
                ),

                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildEpisodesTab(theme),
                      _buildSimilarTab(theme),
                    ],
                  ),
                ),
              ],
            ),
      // Multi-Select Bottom Bar
      bottomNavigationBar: _isSelectionMode
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.cardColor,
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.playlist_play),
                      label: const Text('Play Next'),
                      onPressed: _selectedEpisodeGuids.isNotEmpty
                          ? () => _addSelectedToQueue(playNext: true)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.queue_music),
                      label: const Text('Add to Queue'),
                      onPressed: _selectedEpisodeGuids.isNotEmpty
                          ? () => _addSelectedToQueue(playNext: false)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Mark Listened'),
                      onPressed: _selectedEpisodeGuids.isNotEmpty
                          ? () => _markSelectedPlayedStatus(true)
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                      onPressed: _selectedEpisodeGuids.isNotEmpty
                          ? _downloadSelected
                          : null,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.watch_later_outlined),
                      label: const Text('Listen Later'),
                      onPressed: _selectedEpisodeGuids.isNotEmpty
                          ? _addToListenLater
                          : null,
                    ),
                  ],
                ),
              ),
            )
          : MiniPlayerBar(audioHandler: widget.audioHandler),
      floatingActionButton:
          !_showPodcastExtras &&
              !_isLoading &&
              _errorMessage == null &&
              _tabController.index == 0
          ? FloatingActionButton(
              mini: true,
              tooltip: 'Back to top',
              onPressed: _scrollToTop,
              child: const Icon(Icons.arrow_upward),
            )
          : null,
    );
  }

  Widget _buildEpisodesTab(ThemeData theme) {
    return Column(
      children: [
        // Search & Filter Row
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _showPodcastExtras
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search episodes...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: theme.cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // Filter & Sort Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all', theme),
                      const SizedBox(width: 8),
                      _buildFilterChip('Unplayed', 'unplayed', theme),
                      const SizedBox(width: 8),
                      _buildFilterChip('Downloaded', 'downloaded', theme),
                    ],
                  ),
                ),
              ),
              // Sort Button
              PopupMenuButton<String>(
                tooltip: 'Sort Order',
                icon: Icon(
                  _sortOrder == 'newest'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  size: 20,
                ),
                initialValue: _sortOrder,
                onSelected: (val) {
                  setState(() {
                    _sortOrder = val;
                  });
                  _applyFilters();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'newest',
                    child: Text('Newest first'),
                  ),
                  const PopupMenuItem(
                    value: 'oldest',
                    child: Text('Oldest first'),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 12),

        // Episode List
        Expanded(
          child: ListView.builder(
            controller: _episodesScrollController,
            itemCount: _filteredEpisodes.length,
            itemBuilder: (context, index) {
              final ep = _filteredEpisodes[index];
              final isSelected = _selectedEpisodeGuids.contains(ep.guid);

              return ListTile(
                onLongPress: () {
                  if (!_isSelectionMode) {
                    setState(() {
                      _isSelectionMode = true;
                    });
                  }
                  _toggleSelection(ep.guid);
                },
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(ep.guid);
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EpisodeDetailPage(
                          episode: ep,
                          audioHandler: widget.audioHandler,
                        ),
                      ),
                    ).then((_) => _fetchEpisodes());
                  }
                },
                leading: _isSelectionMode
                    ? Checkbox(
                        value: isSelected,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (_) => _toggleSelection(ep.guid),
                      )
                    : IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 36),
                        color: theme.colorScheme.primary,
                        onPressed: () => widget.audioHandler.playEpisode(ep),
                      ),
                title: Text(
                  ep.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${_formatDuration(ep.durationSeconds)} • ${ep.publishedDate != null ? ep.publishedDate!.toString().substring(0, 10) : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ep.downloadStatus == DownloadStatus.downloaded)
                      const Icon(
                        Icons.download_done,
                        color: Colors.green,
                        size: 22,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.download_outlined, size: 22),
                        onPressed: () => DownloadManager.instance
                            .downloadEpisode(ep, source: DownloadSource.manual),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, size: 22),
                      tooltip: 'Episode options',
                      onSelected: (choice) async {
                        if (choice == 'play_next') {
                          await widget.audioHandler.playNext(ep);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Playing next')),
                            );
                          }
                        } else if (choice == 'add_queue') {
                          await widget.audioHandler.addToQueue(ep);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to queue')),
                            );
                          }
                        } else if (choice == 'mark_played') {
                          await _markSinglePlayedStatus(ep, !ep.isPlayed);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ep.isPlayed
                                      ? 'Marked as unplayed'
                                      : 'Marked as listened',
                                ),
                              ),
                            );
                          }
                        } else if (choice == 'listen_later') {
                          final playlists = await LocalStorage.instance
                              .getPlaylists();
                          final listenLater = playlists.firstWhere(
                            (p) => p.id == 'listen_later',
                          );
                          if (!listenLater.items.any(
                            (item) => item.guid == ep.guid,
                          )) {
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
                            await LocalStorage.instance.savePlaylists(
                              playlists,
                            );
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Added to Listen Later'),
                              ),
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
                              Text(
                                ep.isPlayed
                                    ? 'Mark as Unplayed'
                                    : 'Mark as Listened',
                              ),
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSimilarTab(ThemeData theme) {
    if (_isLoadingSimilar) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_similarPodcasts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.podcasts,
              size: 54,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'No similar podcasts found',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Check back later or search via Discover.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final crossCount = screenWidth > 900 ? 5 : (screenWidth > 600 ? 4 : 3);

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.75,
      ),
      itemCount: _similarPodcasts.length,
      itemBuilder: (context, index) {
        final show = _similarPodcasts[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PodcastDetailPage(
                  podcast: show,
                  audioHandler: widget.audioHandler,
                ),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: show.artworkUrl.isNotEmpty
                      ? Image.network(show.artworkUrl, fit: BoxFit.cover)
                      : Container(color: theme.dividerColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                show.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                show.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String value, ThemeData theme) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: theme.colorScheme.primary.withOpacity(0.2),
      onSelected: (_) {
        setState(() {
          _filter = value;
        });
        _applyFilters();
      },
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0 min';
    final mins = (seconds / 60).round();
    return '$mins min';
  }
}
