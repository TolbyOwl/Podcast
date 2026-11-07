class Podcast {
  final String feedUrl;
  final String title;
  final String author;
  final String description;
  final String artworkUrl;
  final DateTime subscribedAt;
  final int autoDownloadCount; // 0 = disabled, or 1, 2, 3, 5...

  Podcast({
    required this.feedUrl,
    required this.title,
    required this.author,
    this.description = '',
    required this.artworkUrl,
    required this.subscribedAt,
    this.autoDownloadCount = 2,
  });

  Map<String, dynamic> toJson() => {
    'feedUrl': feedUrl,
    'title': title,
    'author': author,
    'description': description,
    'artworkUrl': artworkUrl,
    'subscribedAt': subscribedAt.toIso8601String(),
    'autoDownloadCount': autoDownloadCount,
  };

  factory Podcast.fromJson(Map<String, dynamic> json) {
    return Podcast(
      feedUrl: json['feedUrl'] ?? '',
      title: json['title'] ?? 'Untitled Podcast',
      author: json['author'] ?? 'Unknown Author',
      description: json['description'] ?? '',
      artworkUrl: json['artworkUrl'] ?? '',
      subscribedAt: json['subscribedAt'] != null
          ? DateTime.tryParse(json['subscribedAt']) ?? DateTime.now()
          : DateTime.now(),
      autoDownloadCount: json['autoDownloadCount'] ?? 2,
    );
  }

  Podcast copyWith({
    String? title,
    String? author,
    String? description,
    String? artworkUrl,
    int? autoDownloadCount,
  }) {
    return Podcast(
      feedUrl: feedUrl,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      subscribedAt: subscribedAt,
      autoDownloadCount: autoDownloadCount ?? this.autoDownloadCount,
    );
  }
}
