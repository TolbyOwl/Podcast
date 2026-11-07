enum DownloadSource {
  auto,
  manual,
}

enum DownloadStatus {
  notDownloaded,
  enqueued,
  downloading,
  downloaded,
  failed,
}

class Episode {
  final String guid;
  final String feedUrl;
  final String title;
  final String podcastTitle;
  final String description;
  final String audioUrl;
  final String? localFilePath;
  final String artworkUrl;
  final DateTime? publishedDate;
  final int durationSeconds;
  final int positionSeconds;
  final bool isPlayed;
  final DownloadStatus downloadStatus;
  final DownloadSource? downloadSource; // auto or manual
  final double downloadProgress; // 0.0 - 1.0

  Episode({
    required this.guid,
    required this.feedUrl,
    required this.title,
    required this.podcastTitle,
    this.description = '',
    required this.audioUrl,
    this.localFilePath,
    this.artworkUrl = '',
    this.publishedDate,
    this.durationSeconds = 0,
    this.positionSeconds = 0,
    this.isPlayed = false,
    this.downloadStatus = DownloadStatus.notDownloaded,
    this.downloadSource,
    this.downloadProgress = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'guid': guid,
    'feedUrl': feedUrl,
    'title': title,
    'podcastTitle': podcastTitle,
    'description': description,
    'audioUrl': audioUrl,
    'localFilePath': localFilePath,
    'artworkUrl': artworkUrl,
    'publishedDate': publishedDate?.toIso8601String(),
    'durationSeconds': durationSeconds,
    'positionSeconds': positionSeconds,
    'isPlayed': isPlayed,
    'downloadStatus': downloadStatus.name,
    'downloadSource': downloadSource?.name,
  };

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      guid: json['guid'] ?? json['audioUrl'] ?? '',
      feedUrl: json['feedUrl'] ?? '',
      title: json['title'] ?? 'Untitled Episode',
      podcastTitle: json['podcastTitle'] ?? '',
      description: json['description'] ?? '',
      audioUrl: json['audioUrl'] ?? '',
      localFilePath: json['localFilePath'],
      artworkUrl: json['artworkUrl'] ?? '',
      publishedDate: json['publishedDate'] != null
          ? DateTime.tryParse(json['publishedDate'])
          : null,
      durationSeconds: json['durationSeconds'] ?? 0,
      positionSeconds: json['positionSeconds'] ?? 0,
      isPlayed: json['isPlayed'] ?? false,
      downloadStatus: DownloadStatus.values.firstWhere(
        (e) => e.name == json['downloadStatus'],
        orElse: () => DownloadStatus.notDownloaded,
      ),
      downloadSource: json['downloadSource'] != null
          ? DownloadSource.values.firstWhere(
              (e) => e.name == json['downloadSource'],
              orElse: () => DownloadSource.manual,
            )
          : null,
    );
  }

  Episode copyWith({
    String? localFilePath,
    int? positionSeconds,
    bool? isPlayed,
    DownloadStatus? downloadStatus,
    DownloadSource? downloadSource,
    double? downloadProgress,
  }) {
    return Episode(
      guid: guid,
      feedUrl: feedUrl,
      title: title,
      podcastTitle: podcastTitle,
      description: description,
      audioUrl: audioUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      artworkUrl: artworkUrl,
      publishedDate: publishedDate,
      durationSeconds: durationSeconds,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      isPlayed: isPlayed ?? this.isPlayed,
      downloadStatus: downloadStatus ?? this.downloadStatus,
      downloadSource: downloadSource ?? this.downloadSource,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
}
