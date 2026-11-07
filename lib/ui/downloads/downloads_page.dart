import 'package:flutter/material.dart';
import '../../core/database/local_storage.dart';
import '../../core/services/audio_player_handler.dart';
import '../../core/services/download_manager.dart';
import '../../models/episode.dart';

class DownloadsPage extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const DownloadsPage({super.key, required this.audioHandler});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<Map<String, dynamic>> _downloads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoading = true);
    final list = await LocalStorage.instance.getAllDownloads();
    setState(() {
      _downloads = list;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (_downloads.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear All Downloads',
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear all downloads?'),
                    content: const Text('This will delete all offline audio files from your device.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  for (final dl in _downloads) {
                    await DownloadManager.instance.deleteDownload(dl['guid']);
                  }
                  _loadDownloads();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _downloads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_for_offline_outlined,
                          size: 64, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                      const SizedBox(height: 16),
                      const Text('No Downloaded Episodes',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Downloaded episodes will appear here for offline playback.',
                          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _downloads.length,
                  itemBuilder: (context, index) {
                    final item = _downloads[index];
                    final isAuto = item['downloadSource'] == 'auto';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: IconButton(
                          icon: const Icon(Icons.play_circle_filled, size: 38),
                          color: theme.colorScheme.primary,
                          onPressed: () {
                            widget.audioHandler.playEpisode(Episode(
                              guid: item['guid'],
                              feedUrl: item['feedUrl'],
                              title: item['title'],
                              podcastTitle: item['podcastTitle'],
                              audioUrl: item['audioUrl'],
                              artworkUrl: item['artworkUrl'] ?? '',
                            ));
                          },
                        ),
                        title: Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Row(
                          children: [
                            Text(item['podcastTitle']),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isAuto
                                    ? Colors.blue.withOpacity(0.15)
                                    : Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isAuto ? 'AUTO' : 'MANUAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isAuto ? Colors.blue : Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await DownloadManager.instance.deleteDownload(item['guid']);
                            _loadDownloads();
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
