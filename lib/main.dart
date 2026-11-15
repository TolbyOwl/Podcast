import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;
import 'core/constants/app_constants.dart';
import 'core/database/local_storage.dart';
import 'core/services/audio_player_handler.dart';
import 'core/services/background_worker.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'models/app_settings.dart';
import 'ui/home/home_page.dart';
import 'ui/search/search_page.dart';
import 'ui/playlists/playlists_page.dart';
import 'ui/downloads/downloads_page.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'ui/settings/settings_page.dart';
import 'ui/player/mini_player_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  LocalStorage.initializeDatabase();

  // Initialize Supabase with JoyPlay / Music & Podcast credentials
  await Supabase.initialize(
    url: AppConstants.defaultSupabaseUrl,
    publishableKey: AppConstants.defaultSupabasePublishableKey,
  );

  // Initialize Notifications & Background Tasks
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await NotificationService.instance.init();
      await NotificationService.instance.requestPermission();
    } catch (e) {
      debugPrint('Notification permission error: $e');
    }
  }

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    BackgroundWorker.initialize();
    BackgroundWorker.schedulePeriodicCheck(intervalHours: 3);
  }

  // Pre-initialize the database to ensure sqflite plugin is ready
  await LocalStorage.instance.database;

  // Initialize Windows SMTC bridge if on Windows
  if (!kIsWeb && Platform.isWindows) {
    try {
      await SMTCWindows.initialize();
    } catch (e) {
      debugPrint('SMTCWindows.initialize() error: $e');
    }
  }

  // Initialize media_kit player on the main isolate
  final player = Player();

  // Initialize Audio Handler with background service support on mobile
  AudioPlayerHandler audioHandler;
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    try {
      audioHandler = await AudioService.init<AudioPlayerHandler>(
        builder: () {
          debugPrint('AUDIO_SERVICE_BUILDER: Creating AudioPlayerHandler...');
          return AudioPlayerHandler(player: player);
        },
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.podcast.channel.audio.v2',
          androidNotificationChannelName: 'Podcast Playback',
          androidNotificationChannelDescription: 'Active podcast playback controls and progress',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidStopForegroundOnPause: true,
          androidNotificationOngoing: true,
        ),
      );
      debugPrint('AUDIO_SERVICE_INIT: Success! Session token created.');
    } catch (e, stackTrace) {
      debugPrint('AUDIO_SERVICE_INIT_ERROR: $e\n$stackTrace');
      rethrow;
    }
  } else {
    audioHandler = AudioPlayerHandler(player: player);
    audioHandler.initSMTC();
  }

  // Pull cloud data if authenticated and restore persistent playback
  if (SyncService.instance.isAuthenticated) {
    try {
      await SyncService.instance.pullFromCloud();
    } catch (e) {
      debugPrint('Initial pullFromCloud error: $e');
    }
  }
  await audioHandler.restoreLastPlayback();

  runApp(PodcastApp(audioHandler: audioHandler));
}

class PodcastApp extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const PodcastApp({super.key, required this.audioHandler});

  @override
  State<PodcastApp> createState() => _PodcastAppState();
}

class _PodcastAppState extends State<PodcastApp> with WidgetsBindingObserver {
  AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (SyncService.instance.isAuthenticated) {
        SyncService.instance.pushToCloud();
      }
    }
  }

  Future<void> _loadSettings() async {
    final settings = await LocalStorage.instance.getSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppThemeMode themeMode = AppThemeMode.amoled;
    if (_settings.themeMode == 'light') themeMode = AppThemeMode.light;
    if (_settings.themeMode == 'dark') themeMode = AppThemeMode.dark;

    final accentPreset = AppTheme.accentPresets.firstWhere(
      (p) => p.hex.toUpperCase() == _settings.accentColorHex.toUpperCase(),
      orElse: () => AppTheme.accentPresets.first,
    );

    return MaterialApp(
      title: 'Podcast',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(
        mode: themeMode,
        accentColor: accentPreset.color,
      ),
      home: MainNavigation(
        audioHandler: widget.audioHandler,
        onThemeChanged: _loadSettings,
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final AudioPlayerHandler audioHandler;
  final VoidCallback onThemeChanged;

  const MainNavigation({
    super.key,
    required this.audioHandler,
    required this.onThemeChanged,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 768;

    final List<Widget> pages = [
      HomePage(audioHandler: widget.audioHandler),
      DiscoverPage(audioHandler: widget.audioHandler),
      PlaylistsPage(audioHandler: widget.audioHandler),
      DownloadsPage(audioHandler: widget.audioHandler),
      SettingsPage(onThemeChanged: widget.onThemeChanged),
    ];

    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (index) => setState(() => _currentIndex = index),
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Icon(
                        Icons.podcasts,
                        size: 32,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.podcasts),
                        label: Text('Subs'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.explore_outlined),
                        selectedIcon: Icon(Icons.explore),
                        label: Text('Discover'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.playlist_play),
                        label: Text('Playlists'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.download),
                        label: Text('Downloads'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings),
                        label: Text('Settings'),
                      ),
                    ],
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: pages,
                    ),
                  ),
                ],
              ),
            ),
            MiniPlayerBar(audioHandler: widget.audioHandler),
          ],
        ),
      );
    }

    // Mobile layout: Column ensures MiniPlayerBar shrinks body so no text/cards get covered
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: pages,
            ),
          ),
          MiniPlayerBar(audioHandler: widget.audioHandler),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.podcasts),
            label: 'Subs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.playlist_play),
            label: 'Playlists',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download),
            label: 'Downloads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
