import 'package:flutter/material.dart';
import '../../core/services/audio_player_handler.dart';

class FullPlayerModal extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const FullPlayerModal({super.key, required this.audioHandler});

  @override
  State<FullPlayerModal> createState() => _FullPlayerModalState();
}

class _FullPlayerModalState extends State<FullPlayerModal> {
  final List<double> _speeds = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final episode = widget.audioHandler.currentEpisode;

    if (episode == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: widget.audioHandler,
      builder: (context, _) {
        final isPlaying = widget.audioHandler.isPlaying;
        final pos = widget.audioHandler.position;
        final total = widget.audioHandler.duration.inSeconds > 0
            ? widget.audioHandler.duration
            : Duration(seconds: episode.durationSeconds);
        final maxSec = total.inSeconds.toDouble();
        final curSec = pos.inSeconds.toDouble().clamp(0.0, maxSec > 0 ? maxSec : 1.0);

        return Container(
          height: MediaQuery.of(context).size.height * 0.92,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Top Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 48), // Spacer to balance
                ],
              ),
              const Spacer(),

              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: episode.artworkUrl.isNotEmpty
                    ? Image.network(
                        episode.artworkUrl,
                        width: 280,
                        height: 280,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _artworkFallback(theme),
                      )
                    : _artworkFallback(theme),
              ),
              const Spacer(),

              // Title & Podcast Name
              Text(
                episode.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                episode.podcastTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Scrubber Bar
              Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: curSec,
                      min: 0.0,
                      max: maxSec > 0 ? maxSec : 1.0,
                      activeColor: theme.colorScheme.primary,
                      inactiveColor: theme.dividerColor,
                      onChanged: (val) {
                        widget.audioHandler.seek(Duration(seconds: val.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(pos), style: const TextStyle(fontSize: 12)),
                        Text(_formatDuration(total), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),

              // Player Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Speed selector
                  PopupMenuButton<double>(
                    initialValue: widget.audioHandler.speed,
                    tooltip: 'Playback Speed',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Text(
                        '${widget.audioHandler.speed}x',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    onSelected: (speed) {
                      widget.audioHandler.setSpeed(speed);
                    },
                    itemBuilder: (context) => _speeds
                        .map((s) => PopupMenuItem(
                              value: s,
                              child: Text('${s}x'),
                            ))
                        .toList(),
                  ),

                  // Skip backward 10s
                  IconButton(
                    icon: const Icon(Icons.replay_10, size: 36),
                    onPressed: () => widget.audioHandler.rewind(),
                  ),

                  // Play / Pause Big Button
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                    child: IconButton(
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      iconSize: 42,
                      color: Colors.white,
                      onPressed: () {
                        if (isPlaying) {
                          widget.audioHandler.pause();
                        } else {
                          widget.audioHandler.play();
                        }
                      },
                    ),
                  ),

                  // Skip forward 30s
                  IconButton(
                    icon: const Icon(Icons.forward_30, size: 36),
                    onPressed: () => widget.audioHandler.fastForward(),
                  ),

                  // Sleep Timer Icon
                  IconButton(
                    icon: const Icon(Icons.snooze, size: 26),
                    onPressed: () => _showSleepTimerDialog(context, theme),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _artworkFallback(ThemeData theme) {
    return Container(
      width: 280,
      height: 280,
      color: theme.colorScheme.primary.withValues(alpha: 0.1),
      child: Icon(Icons.podcasts, size: 80, color: theme.colorScheme.primary),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showSleepTimerDialog(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Sleep Timer',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('15 Minutes'),
              onTap: () {
                _setSleepTimer(const Duration(minutes: 15));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('30 Minutes'),
              onTap: () {
                _setSleepTimer(const Duration(minutes: 30));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('End of Episode'),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Turn Off Timer'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(Duration duration) {
    Future.delayed(duration, () {
      widget.audioHandler.pause();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sleep timer set for ${duration.inMinutes} minutes')),
    );
  }
}
