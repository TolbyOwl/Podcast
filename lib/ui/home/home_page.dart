import 'package:flutter/material.dart';
import '../../core/database/local_storage.dart';
import '../../core/events/app_events.dart';
import '../../core/services/audio_player_handler.dart';
import '../../core/services/sync_service.dart';
import '../../models/podcast.dart';
import '../podcast_detail/podcast_detail_page.dart';

class HomePage extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const HomePage({super.key, required this.audioHandler});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<Podcast> _subscriptions = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  late AnimationController _syncAnimController;

  @override
  void initState() {
    super.initState();
    _syncAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _loadSubscriptions();
    AppEvents.subscriptionsChanged.addListener(_loadSubscriptions);
    // Auto-sync library on app startup if authenticated
    if (SyncService.instance.isAuthenticated) {
      _performSync();
    }
  }

  @override
  void dispose() {
    AppEvents.subscriptionsChanged.removeListener(_loadSubscriptions);
    _syncAnimController.dispose();
    super.dispose();
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);
    _syncAnimController.repeat();
    try {
      if (SyncService.instance.isAuthenticated) {
        await SyncService.instance.pullFromCloud();
      }
      await _loadSubscriptions();
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
        _syncAnimController.stop();
        _syncAnimController.reset();
      }
    }
  }

  Future<void> _loadSubscriptions() async {
    setState(() => _isLoading = true);
    final subs = await LocalStorage.instance.getSubscriptions();
    setState(() {
      _subscriptions = subs;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    await _performSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = 3;
    if (screenWidth > 1200) {
      crossAxisCount = 6;
    } else if (screenWidth > 900) {
      crossAxisCount = 5;
    } else if (screenWidth > 600) {
      crossAxisCount = 4;
    } else if (screenWidth < 400) {
      crossAxisCount = 2;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          IconButton(
            tooltip: _isSyncing ? 'Syncing...' : 'Sync with Cloud',
            icon: RotationTransition(
              turns: _syncAnimController,
              child: const Icon(Icons.sync),
            ),
            onPressed: _isSyncing ? null : _performSync,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subscriptions.isEmpty
              ? _buildEmptyState(theme)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: _subscriptions.length,
                    itemBuilder: (context, index) {
                      final podcast = _subscriptions[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PodcastDetailPage(
                                podcast: podcast,
                                audioHandler: widget.audioHandler,
                              ),
                            ),
                          ).then((_) => _loadSubscriptions());
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: podcast.artworkUrl.isNotEmpty
                                    ? Image.network(
                                        podcast.artworkUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _artworkFallback(theme),
                                      )
                                    : _artworkFallback(theme),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              podcast.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.podcasts, size: 64, color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'No Subscriptions Yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Search for podcasts or sync from your JoyPlay account.',
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
        ],
      ),
    );
  }

  Widget _artworkFallback(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary.withOpacity(0.1),
      child: Icon(Icons.podcasts, color: theme.colorScheme.primary),
    );
  }
}
