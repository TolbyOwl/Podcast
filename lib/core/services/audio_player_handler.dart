import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:smtc_windows/smtc_windows.dart';

import '../../models/episode.dart';
import '../database/local_storage.dart';
import 'download_manager.dart';
import 'sync_service.dart';

class AudioPlayerHandler extends BaseAudioHandler with ChangeNotifier {
  late final Player _player;
  Episode? _currentEpisode;
  final List<Episode> _episodeQueue = [];

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  SMTCWindows? _smtc;
  StreamSubscription? _smtcButtonSub;
  DateTime _lastSyncTime = DateTime.fromMillisecondsSinceEpoch(0);

  Player get player => _player;
  Episode? get currentEpisode => _currentEpisode;
  List<Episode> get episodeQueue => List.unmodifiable(_episodeQueue);

  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;

  AudioPlayerHandler() {
    _player = Player();
    _initPlayer();
    _initSMTC();
  }

  void _initSMTC() {
    if (!kIsWeb && Platform.isWindows) {
      try {
        _smtc = SMTCWindows(
          config: const SMTCConfig(
            playEnabled: true,
            pauseEnabled: true,
            nextEnabled: true,
            prevEnabled: false,
            stopEnabled: false,
            fastForwardEnabled: true,
            rewindEnabled: true,
          ),
        );
        _smtcButtonSub = _smtc!.buttonPressStream.listen((event) {
          switch (event) {
            case PressedButton.play:
              play();
              break;
            case PressedButton.pause:
              pause();
              break;
            case PressedButton.next:
              skipToNext();
              break;
            case PressedButton.fastForward:
              fastForward();
              break;
            case PressedButton.rewind:
              rewind();
              break;
            case PressedButton.stop:
              stop();
              break;
            default:
              break;
          }
        });
      } catch (e) {
        debugPrint('SMTCWindows init error: $e');
      }
    }
  }

  void _initPlayer() {
    _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      _updateAudioServiceState();
      _updateSMTCState();
      notifyListeners();
    });

    _player.stream.position.listen((pos) {
      _position = pos;
      _updateAudioServiceState();
      _updateSMTCState();
      notifyListeners();
      if (_currentEpisode != null && _isPlaying) {
        _savePlaybackPosition(pos.inSeconds);
      }
    });

    _player.stream.duration.listen((dur) {
      _duration = dur;
      _updateAudioServiceState();
      _updateSMTCState();
      notifyListeners();
    });

    _player.stream.completed.listen((completed) {
      if (completed) {
        _handleEpisodeFinished();
      }
    });

    _player.stream.error.listen((err) {
      debugPrint('MediaKit Audio Error: $err');
    });
  }

  void _updateAudioServiceState() {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          _isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.stop,
          MediaAction.fastForward,
          MediaAction.rewind,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: _currentEpisode == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: _isPlaying,
        updatePosition: _position,
        bufferedPosition: _position,
        speed: _speed,
      ),
    );
  }

  void _updateSMTCState() {
    if (_smtc == null) return;
    try {
      _smtc!.setPlaybackStatus(
        _isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
      if (_duration.inMilliseconds > 0) {
        final posMs =
            _position.inMilliseconds.clamp(0, _duration.inMilliseconds);
        _smtc!.updateTimeline(PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: _duration.inMilliseconds,
          positionMs: posMs,
        ));
      }
    } catch (e) {
      debugPrint('SMTC update state error: $e');
    }
  }

  void _updateSMTCMetadata(Episode episode) {
    if (_smtc == null) return;
    try {
      _smtc!.updateMetadata(MusicMetadata(
        title: episode.title,
        artist: episode.podcastTitle,
        album: episode.podcastTitle,
        thumbnail: episode.artworkUrl.isNotEmpty ? episode.artworkUrl : null,
      ));
    } catch (e) {
      debugPrint('SMTC metadata error: $e');
    }
  }

  Future<void> restoreLastPlayback() async {
    try {
      final lastState = await LocalStorage.instance.getLastPlaybackState();
      if (lastState != null && lastState['episode'] != null) {
        final ep = Episode.fromJson(lastState['episode'] as Map<String, dynamic>);
        final posSec = lastState['positionSeconds'] as int? ?? 0;
        final durSec = lastState['durationSeconds'] as int? ?? ep.durationSeconds;

        _currentEpisode = ep.copyWith(positionSeconds: posSec);
        _position = Duration(seconds: posSec);
        _duration = Duration(seconds: durSec);
        _isPlaying = false;

        mediaItem.add(MediaItem(
          id: ep.guid,
          album: ep.podcastTitle,
          title: ep.title,
          artUri: Uri.tryParse(ep.artworkUrl),
          duration: _duration,
        ));

        _updateSMTCMetadata(ep);
        _updateAudioServiceState();
        _updateSMTCState();

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error restoring last playback: $e');
    }
  }

  Future<void> playEpisode(Episode episode, {bool startPlaying = true}) async {
    unawaited(_player.stop());
    _currentEpisode = episode;
    _position = Duration.zero;
    _duration = Duration(seconds: episode.durationSeconds);
    _isPlaying = startPlaying;

    mediaItem.add(MediaItem(
      id: episode.guid,
      album: episode.podcastTitle,
      title: episode.title,
      artUri: Uri.tryParse(episode.artworkUrl),
      duration: _duration,
    ));

    _updateSMTCMetadata(episode);
    _updateAudioServiceState();
    _updateSMTCState();
    notifyListeners();

    // Check if we have an offline local file
    final downloadRecord = await LocalStorage.instance.getDownloadRecord(
      episode.guid,
    );
    String? localPath = downloadRecord?['localFilePath'];

    try {
      if (localPath != null && await File(localPath).exists()) {
        await _player.open(Media(localPath), play: startPlaying);
      } else {
        await _player.open(Media(episode.audioUrl), play: startPlaying);
      }

      await _player.setRate(_speed);

      // Resume position if stored
      final seekSec = episode.positionSeconds;
      if (seekSec > 0 && seekSec < (episode.durationSeconds - 10)) {
        await _player.seek(Duration(seconds: seekSec));
      }
    } catch (e) {
      debugPrint('Error playing audio via media_kit: $e');
    }
  }

  Future<void> addToQueue(Episode episode) async {
    _episodeQueue.add(episode);
    notifyListeners();
  }

  Future<void> playNext(Episode episode) async {
    _episodeQueue.insert(0, episode);
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _episodeQueue.length) {
      _episodeQueue.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _episodeQueue.removeAt(oldIndex);
    _episodeQueue.insert(newIndex, item);
    notifyListeners();
  }

  @override
  Future<void> play() async {
    if (_currentEpisode != null && _player.state.playlist.medias.isEmpty) {
      await playEpisode(_currentEpisode!, startPlaying: true);
    } else {
      await _player.play();
    }
    _isPlaying = true;
    _updateAudioServiceState();
    _updateSMTCState();
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
    _updateAudioServiceState();
    _updateSMTCState();
    notifyListeners();

    if (_currentEpisode != null) {
      await _savePlaybackState();
      if (SyncService.instance.isAuthenticated) {
        unawaited(SyncService.instance.pushToCloud());
      }
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _updateAudioServiceState();
    _updateSMTCState();
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
    _updateAudioServiceState();
    _updateSMTCState();
    notifyListeners();
    if (_currentEpisode != null) {
      _savePlaybackPosition(position.inSeconds);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _player.setRate(speed);
    _updateAudioServiceState();
    notifyListeners();
  }

  @override
  Future<void> fastForward() async {
    final target = _position + const Duration(seconds: 30);
    await seek(target > _duration ? _duration : target);
  }

  @override
  Future<void> rewind() async {
    final target = _position - const Duration(seconds: 10);
    await seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> skipToNext() async {
    if (_episodeQueue.isNotEmpty) {
      final next = _episodeQueue.removeAt(0);
      notifyListeners();
      await playEpisode(next);
    } else {
      await stop();
    }
  }

  Future<void> _handleEpisodeFinished() async {
    if (_currentEpisode != null) {
      await LocalStorage.instance.recordPlayback(
        audioUrl: _currentEpisode!.audioUrl,
        feedUrl: _currentEpisode!.feedUrl,
        episodeTitle: _currentEpisode!.title,
        podcastTitle: _currentEpisode!.podcastTitle,
        positionSeconds: _currentEpisode!.durationSeconds,
        durationSeconds: _currentEpisode!.durationSeconds,
        completed: true,
      );

      await DownloadManager.instance.onEpisodeFinished(_currentEpisode!);
    }
    await skipToNext();
  }

  Future<void> _savePlaybackPosition(int seconds) async {
    if (_currentEpisode == null) return;
    await LocalStorage.instance.recordPlayback(
      audioUrl: _currentEpisode!.audioUrl,
      feedUrl: _currentEpisode!.feedUrl,
      episodeTitle: _currentEpisode!.title,
      podcastTitle: _currentEpisode!.podcastTitle,
      positionSeconds: seconds,
      durationSeconds: _duration.inSeconds > 0
          ? _duration.inSeconds
          : _currentEpisode!.durationSeconds,
      completed: false,
    );

    await _savePlaybackState();

    // Throttle cloud sync during playback (every 30 seconds if authenticated)
    final now = DateTime.now();
    if (SyncService.instance.isAuthenticated &&
        now.difference(_lastSyncTime).inSeconds > 30) {
      _lastSyncTime = now;
      unawaited(SyncService.instance.pushToCloud());
    }
  }

  Future<void> _savePlaybackState() async {
    if (_currentEpisode == null) return;
    await LocalStorage.instance.saveLastPlaybackState(
      episode: _currentEpisode!,
      positionSeconds: _position.inSeconds,
      durationSeconds: _duration.inSeconds > 0
          ? _duration.inSeconds
          : _currentEpisode!.durationSeconds,
    );
  }

  @override
  void dispose() {
    _smtcButtonSub?.cancel();
    _smtc?.dispose();
    _player.dispose();
    super.dispose();
  }
}
