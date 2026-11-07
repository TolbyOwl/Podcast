class PlaylistItem {
  final String guid;
  final String audioUrl;
  final String feedUrl;
  final String title;
  final String podcastTitle;
  final String artworkUrl;
  final DateTime addedAt;

  PlaylistItem({
    required this.guid,
    required this.audioUrl,
    required this.feedUrl,
    required this.title,
    required this.podcastTitle,
    required this.artworkUrl,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'guid': guid,
    'audioUrl': audioUrl,
    'feedUrl': feedUrl,
    'title': title,
    'podcastTitle': podcastTitle,
    'artworkUrl': artworkUrl,
    'addedAt': addedAt.toIso8601String(),
  };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) {
    return PlaylistItem(
      guid: json['guid'] ?? json['audioUrl'] ?? '',
      audioUrl: json['audioUrl'] ?? '',
      feedUrl: json['feedUrl'] ?? '',
      title: json['title'] ?? 'Untitled Episode',
      podcastTitle: json['podcastTitle'] ?? '',
      artworkUrl: json['artworkUrl'] ?? '',
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final bool isSystem; // e.g. Listen Later
  final List<PlaylistItem> items;
  final DateTime createdAt;

  Playlist({
    required this.id,
    required this.name,
    this.isSystem = false,
    required this.items,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isSystem': isSystem,
    'items': items.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Playlist',
      isSystem: json['isSystem'] ?? false,
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => PlaylistItem.fromJson(item))
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static Playlist createListenLater() {
    return Playlist(
      id: 'listen_later',
      name: 'Listen Later',
      isSystem: true,
      items: [],
      createdAt: DateTime.now(),
    );
  }

  static Playlist createNewEpisodes() {
    return Playlist(
      id: 'new_episodes',
      name: 'New Episodes',
      isSystem: true,
      items: [],
      createdAt: DateTime.now(),
    );
  }
}
