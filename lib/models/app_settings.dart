class AppSettings {
  final String themeMode; // light, dark, amoled
  final String accentColorHex;
  final double playbackSpeed;
  final bool trimSilence;
  final bool volumeBoost;
  final bool autoDownloadGlobal;
  final int autoDownloadEpisodesPerSub;
  final bool autoDeleteOnCompletion;
  final bool downloadOnlyOnWifi;
  final String countryCode; // e.g. 'us', 'br', 'gb', 'ca', etc.
  final int backgroundRefreshIntervalHours;
  final int skipForwardSeconds;
  final int skipBackwardSeconds;

  AppSettings({
    this.themeMode = 'amoled',
    this.accentColorHex = '#7C4DFF',
    this.playbackSpeed = 1.0,
    this.trimSilence = false,
    this.volumeBoost = false,
    this.autoDownloadGlobal = true,
    this.autoDownloadEpisodesPerSub = 2,
    this.autoDeleteOnCompletion = true,
    this.downloadOnlyOnWifi = true,
    this.countryCode = 'us',
    this.backgroundRefreshIntervalHours = 3,
    this.skipForwardSeconds = 30,
    this.skipBackwardSeconds = 10,
  });

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'accentColorHex': accentColorHex,
    'playbackSpeed': playbackSpeed,
    'trimSilence': trimSilence,
    'volumeBoost': volumeBoost,
    'autoDownloadGlobal': autoDownloadGlobal,
    'autoDownloadEpisodesPerSub': autoDownloadEpisodesPerSub,
    'autoDeleteOnCompletion': autoDeleteOnCompletion,
    'downloadOnlyOnWifi': downloadOnlyOnWifi,
    'countryCode': countryCode,
    'backgroundRefreshIntervalHours': backgroundRefreshIntervalHours,
    'skipForwardSeconds': skipForwardSeconds,
    'skipBackwardSeconds': skipBackwardSeconds,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeMode: json['themeMode'] ?? 'amoled',
      accentColorHex: json['accentColorHex'] ?? '#7C4DFF',
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      trimSilence: json['trimSilence'] ?? false,
      volumeBoost: json['volumeBoost'] ?? false,
      autoDownloadGlobal: json['autoDownloadGlobal'] ?? true,
      autoDownloadEpisodesPerSub: json['autoDownloadEpisodesPerSub'] ?? 2,
      autoDeleteOnCompletion: json['autoDeleteOnCompletion'] ?? true,
      downloadOnlyOnWifi: json['downloadOnlyOnWifi'] ?? true,
      countryCode: json['countryCode'] ?? 'us',
      backgroundRefreshIntervalHours: json['backgroundRefreshIntervalHours'] ?? 3,
      skipForwardSeconds: json['skipForwardSeconds'] ?? 30,
      skipBackwardSeconds: json['skipBackwardSeconds'] ?? 10,
    );
  }

  AppSettings copyWith({
    String? themeMode,
    String? accentColorHex,
    double? playbackSpeed,
    bool? trimSilence,
    bool? volumeBoost,
    bool? autoDownloadGlobal,
    int? autoDownloadEpisodesPerSub,
    bool? autoDeleteOnCompletion,
    bool? downloadOnlyOnWifi,
    String? countryCode,
    int? backgroundRefreshIntervalHours,
    int? skipForwardSeconds,
    int? skipBackwardSeconds,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      trimSilence: trimSilence ?? this.trimSilence,
      volumeBoost: volumeBoost ?? this.volumeBoost,
      autoDownloadGlobal: autoDownloadGlobal ?? this.autoDownloadGlobal,
      autoDownloadEpisodesPerSub:
          autoDownloadEpisodesPerSub ?? this.autoDownloadEpisodesPerSub,
      autoDeleteOnCompletion:
          autoDeleteOnCompletion ?? this.autoDeleteOnCompletion,
      downloadOnlyOnWifi: downloadOnlyOnWifi ?? this.downloadOnlyOnWifi,
      countryCode: countryCode ?? this.countryCode,
      backgroundRefreshIntervalHours:
          backgroundRefreshIntervalHours ?? this.backgroundRefreshIntervalHours,
      skipForwardSeconds: skipForwardSeconds ?? this.skipForwardSeconds,
      skipBackwardSeconds: skipBackwardSeconds ?? this.skipBackwardSeconds,
    );
  }
}
