import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import '../../models/podcast.dart';
import '../../models/episode.dart';
import '../../models/playlist.dart';
import '../../models/app_settings.dart';

class LocalStorage {
  static final LocalStorage instance = LocalStorage._init();
  static Database? _database;

  LocalStorage._init();

  static void initializeDatabase() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB('podcast_vault.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE downloaded_episodes (
        guid TEXT PRIMARY KEY,
        feedUrl TEXT NOT NULL,
        title TEXT NOT NULL,
        podcastTitle TEXT NOT NULL,
        audioUrl TEXT NOT NULL,
        localFilePath TEXT NOT NULL,
        artworkUrl TEXT,
        publishedDate TEXT,
        durationSeconds INTEGER,
        downloadSource TEXT NOT NULL,
        downloadedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE playback_history (
        audioUrl TEXT PRIMARY KEY,
        feedUrl TEXT NOT NULL,
        episodeTitle TEXT NOT NULL,
        podcastTitle TEXT NOT NULL,
        positionSeconds INTEGER NOT NULL,
        durationSeconds INTEGER NOT NULL,
        completed INTEGER NOT NULL,
        lastPlayedAt TEXT NOT NULL
      )
    ''');
  }

  // --- Subscriptions in SharedPreferences ---
  Future<List<Podcast>> getSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('subscriptions') ?? '[]';
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => Podcast.fromJson(e)).toList();
  }

  Future<void> saveSubscriptions(List<Podcast> podcasts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(podcasts.map((e) => e.toJson()).toList());
    await prefs.setString('subscriptions', jsonStr);
  }

  // --- Playlists in SharedPreferences ---
  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('playlists');
    if (jsonStr == null || jsonStr.isEmpty) {
      final initial = [
        Playlist.createNewEpisodes(),
        Playlist.createListenLater(),
      ];
      await savePlaylists(initial);
      return initial;
    }
    final List<dynamic> list = jsonDecode(jsonStr);
    final playlists = list.map((e) => Playlist.fromJson(e)).toList();
    if (!playlists.any((p) => p.id == 'listen_later')) {
      playlists.insert(0, Playlist.createListenLater());
      await savePlaylists(playlists);
    }
    if (!playlists.any((p) => p.id == 'new_episodes')) {
      playlists.insert(0, Playlist.createNewEpisodes());
      await savePlaylists(playlists);
    }
    return playlists;
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(playlists.map((e) => e.toJson()).toList());
    await prefs.setString('playlists', jsonStr);
  }

  // --- Settings in SharedPreferences ---
  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('settings');
    if (jsonStr == null) return AppSettings();
    return AppSettings.fromJson(jsonDecode(jsonStr));
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(settings.toJson()));
  }

  // --- Download Tracking in SQLite ---
  Future<void> recordDownload({
    required Episode episode,
    required String localPath,
    required DownloadSource source,
  }) async {
    final db = await database;
    await db.insert('downloaded_episodes', {
      'guid': episode.guid,
      'feedUrl': episode.feedUrl,
      'title': episode.title,
      'podcastTitle': episode.podcastTitle,
      'audioUrl': episode.audioUrl,
      'localFilePath': localPath,
      'artworkUrl': episode.artworkUrl,
      'publishedDate': episode.publishedDate?.toIso8601String(),
      'durationSeconds': episode.durationSeconds,
      'downloadSource': source.name,
      'downloadedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeDownloadRecord(String guid) async {
    final db = await database;
    await db.delete(
      'downloaded_episodes',
      where: 'guid = ?',
      whereArgs: [guid],
    );
  }

  Future<Map<String, dynamic>?> getDownloadRecord(String guid) async {
    final db = await database;
    final res = await db.query(
      'downloaded_episodes',
      where: 'guid = ?',
      whereArgs: [guid],
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllDownloads() async {
    final db = await database;
    return await db.query('downloaded_episodes', orderBy: 'downloadedAt DESC');
  }

  Future<List<Map<String, dynamic>>> getAutoDownloadsForFeed(
    String feedUrl,
  ) async {
    final db = await database;
    return await db.query(
      'downloaded_episodes',
      where: 'feedUrl = ? AND downloadSource = ?',
      whereArgs: [feedUrl, 'auto'],
      orderBy: 'downloadedAt ASC', // oldest first for quota deletion
    );
  }

  // --- Playback History ---
  Future<void> recordPlayback({
    required String audioUrl,
    required String feedUrl,
    required String episodeTitle,
    required String podcastTitle,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  }) async {
    final db = await database;
    await db.insert('playback_history', {
      'audioUrl': audioUrl,
      'feedUrl': feedUrl,
      'episodeTitle': episodeTitle,
      'podcastTitle': podcastTitle,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'completed': completed ? 1 : 0,
      'lastPlayedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getPlaybackHistory(String audioUrl) async {
    final db = await database;
    final res = await db.query(
      'playback_history',
      where: 'audioUrl = ?',
      whereArgs: [audioUrl],
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> removePlaybackHistory(String audioUrl) async {
    final db = await database;
    await db.delete(
      'playback_history',
      where: 'audioUrl = ?',
      whereArgs: [audioUrl],
    );
  }

  Future<List<Map<String, dynamic>>> getAllHistory() async {
    final db = await database;
    return await db.query('playback_history', orderBy: 'lastPlayedAt DESC');
  }

  Future<void> saveRawHistory(List<dynamic> history) async {
    final db = await database;
    final batch = db.batch();
    for (final item in history) {
      if (item is Map<String, dynamic>) {
        batch.insert('playback_history', {
          'audioUrl': item['audioUrl'] ?? '',
          'feedUrl': item['feedUrl'] ?? '',
          'episodeTitle': item['episodeTitle'] ?? '',
          'podcastTitle': item['podcastTitle'] ?? '',
          'positionSeconds': item['positionSeconds'] ?? 0,
          'durationSeconds': item['durationSeconds'] ?? 0,
          'completed': (item['completed'] == true) ? 1 : 0,
          'lastPlayedAt':
              item['lastPlayedAt'] ?? DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    await batch.commit(noResult: true);
  }

  // --- Last Playback State (for cross-restart & cross-device persistence) ---
  Future<void> saveLastPlaybackState({
    required Episode episode,
    required int positionSeconds,
    required int durationSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'episode': episode.toJson(),
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await prefs.setString('last_playback_session', jsonEncode(data));
  }

  Future<Map<String, dynamic>?> getLastPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('last_playback_session');
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
