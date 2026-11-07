class AppConstants {
  static const String appName = 'Podcast';

  // JoyPlay / Music & Podcast Supabase Configuration
  static const String defaultSupabaseUrl = 'https://okezhxgmoqrcblmzyzvq.supabase.co';
  static const String defaultSupabasePublishableKey = 'sb_publishable_PPAJ03Bi4eJPAngIYe-v9Q_IywEaGtv';

  static const String podcastSyncTable = 'podcast_sync';

  // WorkManager Task Names
  static const String syncTaskName = 'com.podcast.background_sync_task';
  static const String syncTaskTag = 'podcast_sync_tag';
}
