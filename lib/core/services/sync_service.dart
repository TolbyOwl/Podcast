import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;
import '../constants/app_constants.dart';
import '../database/local_storage.dart';
import '../../models/podcast.dart';
import '../../models/playlist.dart';
import '../../models/app_settings.dart';
import '../../models/episode.dart';

class SyncService {
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  bool get isAuthenticated => _client.auth.currentUser != null;
  String? get userEmail => _client.auth.currentUser?.email;

  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    // After login, automatically perform a pull to bring in user library
    await pullFromCloud();
  }

  Future<void> signUp(String email, String password) async {
    await _client.auth.signUp(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Pushes local state (subscriptions, history, playlists, settings) to Supabase podcast_sync table
  Future<void> pushToCloud() async {
    if (!isAuthenticated) return;
    final userId = _client.auth.currentUser!.id;

    final subscriptions = await LocalStorage.instance.getSubscriptions();
    final playlists = await LocalStorage.instance.getPlaylists();
    final settings = await LocalStorage.instance.getSettings();
    final history = await LocalStorage.instance.getAllHistory();
    final lastPlayback = await LocalStorage.instance.getLastPlaybackState();

    await _client.from(AppConstants.podcastSyncTable).upsert({
      'user_id': userId,
      'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
      'history': history,
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'settings': settings.toJson(),
      'last_playback': lastPlayback,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Pulls remote state and gracefully merges with local storage
  Future<void> pullFromCloud() async {
    if (!isAuthenticated) return;
    final userId = _client.auth.currentUser!.id;

    final response = await _client
        .from(AppConstants.podcastSyncTable)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      // First time user on this table: push our local data up
      await pushToCloud();
      return;
    }

    // 1. Merge Subscriptions (deduplicate by feedUrl)
    final remoteSubs = (response['subscriptions'] as List<dynamic>?)
            ?.map((e) => Podcast.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final localSubs = await LocalStorage.instance.getSubscriptions();
    final mergedSubsMap = <String, Podcast>{};
    for (final sub in localSubs) {
      mergedSubsMap[sub.feedUrl] = sub;
    }
    for (final sub in remoteSubs) {
      mergedSubsMap[sub.feedUrl] = sub; // remote takes priority or updates info
    }
    await LocalStorage.instance.saveSubscriptions(mergedSubsMap.values.toList());

    // 2. Merge Playlists
    if (response['playlists'] != null) {
      final remotePlaylists = (response['playlists'] as List<dynamic>)
          .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
          .toList();
      await LocalStorage.instance.savePlaylists(remotePlaylists);
    }

    // 3. Merge History
    if (response['history'] != null) {
      final remoteHistory = response['history'] as List<dynamic>;
      await LocalStorage.instance.saveRawHistory(remoteHistory);
    }

    // 4. Merge Settings
    if (response['settings'] != null && (response['settings'] as Map).isNotEmpty) {
      final remoteSettings = AppSettings.fromJson(response['settings'] as Map<String, dynamic>);
      await LocalStorage.instance.saveSettings(remoteSettings);
    }

    // 5. Restore Last Playback if remote is newer or local is empty
    if (response['last_playback'] != null && (response['last_playback'] as Map).isNotEmpty) {
      final remoteLast = response['last_playback'] as Map<String, dynamic>;
      final localLast = await LocalStorage.instance.getLastPlaybackState();

      bool useRemote = true;
      if (localLast != null && localLast['savedAt'] != null && remoteLast['savedAt'] != null) {
        final localDate = DateTime.tryParse(localLast['savedAt']);
        final remoteDate = DateTime.tryParse(remoteLast['savedAt']);
        if (localDate != null && remoteDate != null && localDate.isAfter(remoteDate)) {
          useRemote = false;
        }
      }

      if (useRemote && remoteLast['episode'] != null) {
        final ep = Episode.fromJson(remoteLast['episode'] as Map<String, dynamic>);
        await LocalStorage.instance.saveLastPlaybackState(
          episode: ep,
          positionSeconds: remoteLast['positionSeconds'] ?? 0,
          durationSeconds: remoteLast['durationSeconds'] ?? ep.durationSeconds,
        );
      }
    }
  }
}
