import 'package:flutter/material.dart';
import '../../core/services/audio_player_handler.dart';
import 'full_player_modal.dart';

class MiniPlayerBar extends StatelessWidget {
  final AudioPlayerHandler audioHandler;

  const MiniPlayerBar({super.key, required this.audioHandler});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: audioHandler,
      builder: (context, _) {
        final episode = audioHandler.currentEpisode;
        if (episode == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final isPlaying = audioHandler.isPlaying;

        return GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => FullPlayerModal(audioHandler: audioHandler),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: episode.artworkUrl.isNotEmpty
                        ? Image.network(
                            episode.artworkUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultArtwork(theme),
                          )
                        : _defaultArtwork(theme),
                  ),
                  title: Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    episode.podcastTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                        iconSize: 38,
                        color: theme.colorScheme.primary,
                        onPressed: () {
                          if (isPlaying) {
                            audioHandler.pause();
                          } else {
                            audioHandler.play();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        onPressed: () => audioHandler.skipToNext(),
                      ),
                    ],
                  ),
                ),
                // Progress Bar
                Builder(
                  builder: (_) {
                    final pos = audioHandler.position.inMilliseconds;
                    final total = audioHandler.duration.inMilliseconds;
                    final progress = (total > 0 ? (pos / total) : 0.0).clamp(0.0, 1.0);

                    return LinearProgressIndicator(
                      value: progress,
                      minHeight: 2.5,
                      backgroundColor: theme.dividerColor,
                      valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _defaultArtwork(ThemeData theme) {
    return Container(
      width: 48,
      height: 48,
      color: theme.colorScheme.primary.withValues(alpha: 0.1),
      child: Icon(Icons.podcasts, color: theme.colorScheme.primary),
    );
  }
}
