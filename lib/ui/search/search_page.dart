import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/database/local_storage.dart';
import '../../core/events/app_events.dart';
import '../../core/services/audio_player_handler.dart';
import '../../models/podcast.dart';
import '../podcast_detail/podcast_detail_page.dart';

class CategoryItem {
  final String title;
  final String searchTerm;
  final IconData icon;
  final Color color;

  const CategoryItem({
    required this.title,
    required this.searchTerm,
    required this.icon,
    required this.color,
  });
}

class DiscoverPage extends StatefulWidget {
  final AudioPlayerHandler audioHandler;

  const DiscoverPage({super.key, required this.audioHandler});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Podcast> _searchResults = [];
  bool _isSearching = false;
  String? _error;
  Set<String> _subscribedFeedUrls = {};

  // Featured & Trending sections
  List<Podcast> _trendingPodcasts = [];
  List<Podcast> _techPodcasts = [];
  List<Podcast> _newsPodcasts = [];
  bool _isLoadingFeatured = true;

  String? _selectedCategory;

  static const List<CategoryItem> categories = [
    CategoryItem(
      title: 'Technology',
      searchTerm: 'Technology podcast',
      icon: Icons.laptop_mac,
      color: Color(0xFF00B0FF),
    ),
    CategoryItem(
      title: 'News & Politics',
      searchTerm: 'Daily News',
      icon: Icons.newspaper,
      color: Color(0xFFFF6D00),
    ),
    CategoryItem(
      title: 'True Crime',
      searchTerm: 'True Crime podcast',
      icon: Icons.fingerprint,
      color: Color(0xFFE53935),
    ),
    CategoryItem(
      title: 'Comedy',
      searchTerm: 'Comedy podcast',
      icon: Icons.sentiment_very_satisfied,
      color: Color(0xFFFFB300),
    ),
    CategoryItem(
      title: 'Business & Finance',
      searchTerm: 'Business podcast',
      icon: Icons.trending_up,
      color: Color(0xFF00C853),
    ),
    CategoryItem(
      title: 'Science',
      searchTerm: 'Science podcast',
      icon: Icons.science,
      color: Color(0xFF7C4DFF),
    ),
    CategoryItem(
      title: 'Health & Fitness',
      searchTerm: 'Health fitness podcast',
      icon: Icons.fitness_center,
      color: Color(0xFFEC4899),
    ),
    CategoryItem(
      title: 'History',
      searchTerm: 'History podcast',
      icon: Icons.menu_book,
      color: Color(0xFF8D6E63),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
    _loadFeaturedContent();
    AppEvents.discoverRefresh.addListener(_onDiscoverRefresh);
    AppEvents.subscriptionsChanged.addListener(_onDiscoverRefresh);
  }

  void _onDiscoverRefresh() {
    _loadFeaturedContent();
    _loadSubscriptions();
  }

  @override
  void dispose() {
    AppEvents.discoverRefresh.removeListener(_onDiscoverRefresh);
    AppEvents.subscriptionsChanged.removeListener(_onDiscoverRefresh);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubscriptions() async {
    final subs = await LocalStorage.instance.getSubscriptions();
    if (mounted) {
      setState(() {
        _subscribedFeedUrls = subs.map((s) => s.feedUrl).toSet();
      });
    }
  }

  Future<void> _loadFeaturedContent() async {
    setState(() => _isLoadingFeatured = true);
    final settings = await LocalStorage.instance.getSettings();
    final country = settings.countryCode;
    final dio = Dio();
    try {
      // Fetch trending/top shows for user's selected country
      final resTrending = await dio.get(
        'https://itunes.apple.com/search?term=podcast&media=podcast&entity=podcast&country=$country&limit=10',
      );
      final resTech = await dio.get(
        'https://itunes.apple.com/search?term=technology&media=podcast&entity=podcast&country=$country&limit=10',
      );
      final resNews = await dio.get(
        'https://itunes.apple.com/search?term=news&media=podcast&entity=podcast&country=$country&limit=10',
      );

      if (mounted) {
        setState(() {
          _trendingPodcasts = _parseItunesResults(resTrending.data);
          _techPodcasts = _parseItunesResults(resTech.data);
          _newsPodcasts = _parseItunesResults(resNews.data);
          _isLoadingFeatured = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingFeatured = false);
      }
    }
  }

  List<Podcast> _parseItunesResults(dynamic responseData) {
    final data = responseData is String
        ? jsonDecode(responseData)
        : responseData;
    final results = (data['results'] as List<dynamic>?) ?? [];
    final list = <Podcast>[];
    for (final item in results) {
      final feed = item['feedUrl'];
      if (feed != null && feed.toString().isNotEmpty) {
        list.add(
          Podcast(
            feedUrl: feed,
            title: item['collectionName'] ?? 'Untitled',
            author: item['artistName'] ?? 'Unknown Author',
            artworkUrl: item['artworkUrl600'] ?? item['artworkUrl100'] ?? '',
            subscribedAt: DateTime.now(),
          ),
        );
      }
    }
    return list;
  }

  Future<void> _searchPodcasts(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults.clear();
        _isSearching = false;
        _selectedCategory = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final settings = await LocalStorage.instance.getSettings();
      final country = settings.countryCode;
      final dio = Dio();
      final url =
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=podcast&entity=podcast&country=$country&limit=30';
      final response = await dio.get(url);

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _searchResults = _parseItunesResults(response.data);
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to find podcasts: $e';
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _toggleSubscribe(Podcast podcast) async {
    final subs = await LocalStorage.instance.getSubscriptions();
    final isSubbed = subs.any((s) => s.feedUrl == podcast.feedUrl);

    if (isSubbed) {
      subs.removeWhere((s) => s.feedUrl == podcast.feedUrl);
    } else {
      subs.add(podcast);
    }
    await LocalStorage.instance.saveSubscriptions(subs);
    AppEvents.notifySubscriptionsChanged();
    setState(() {
      if (isSubbed) {
        _subscribedFeedUrls.remove(podcast.feedUrl);
      } else {
        _subscribedFeedUrls.add(podcast.feedUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isShowingSearch =
        _searchResults.isNotEmpty || _isSearching || _error != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          if (isShowingSearch)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear Search',
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults.clear();
                  _error = null;
                  _isSearching = false;
                  _selectedCategory = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 10.0,
            ),
            child: TextField(
              controller: _searchController,
              onSubmitted: _searchPodcasts,
              decoration: InputDecoration(
                hintText: 'Search millions of podcasts, topics, creators...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _searchPodcasts(_searchController.text),
                ),
                filled: true,
                fillColor: theme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
            ),
          ),

          // Main View: Either Search Results OR Rich Discover Hub
          Expanded(
            child: isShowingSearch
                ? _buildSearchResults(theme)
                : _buildDiscoverHub(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          'No podcasts found for "${_searchController.text}".',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final podcast = _searchResults[index];
        final isSubbed = _subscribedFeedUrls.contains(podcast.feedUrl);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PodcastDetailPage(
                    podcast: podcast,
                    audioHandler: widget.audioHandler,
                  ),
                ),
              ).then((_) => _loadSubscriptions());
            },
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: podcast.artworkUrl.isNotEmpty
                  ? Image.network(
                      podcast.artworkUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _artworkFallback(theme),
                    )
                  : _artworkFallback(theme),
            ),
            title: Text(
              podcast.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              podcast.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: Icon(
                isSubbed ? Icons.check_circle : Icons.add_circle_outline,
              ),
              color: isSubbed ? Colors.green : theme.colorScheme.primary,
              tooltip: isSubbed ? 'Subscribed' : 'Subscribe',
              onPressed: () => _toggleSubscribe(podcast),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDiscoverHub(ThemeData theme) {
    if (_isLoadingFeatured) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final categoryCrossAxis = screenWidth > 900
        ? 4
        : (screenWidth > 600 ? 3 : 2);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        // 1. Browse by Categories Grid
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Browse Categories',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_selectedCategory != null)
                TextButton(
                  onPressed: () {
                    setState(() => _selectedCategory = null);
                  },
                  child: const Text('Show All'),
                ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: categoryCrossAxis,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.5,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final cat = categories[index];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _searchController.text = cat.title;
                _searchPodcasts(cat.searchTerm);
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cat.color.withOpacity(0.85),
                      cat.color.withOpacity(0.55),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(cat.icon, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // 2. Trending Podcasts Carousel
        if (_trendingPodcasts.isNotEmpty)
          _buildPodcastCarousel(
            title: '🔥 Trending & Popular',
            podcasts: _trendingPodcasts,
            theme: theme,
          ),

        const SizedBox(height: 16),

        // 3. Technology Podcasts Carousel
        if (_techPodcasts.isNotEmpty)
          _buildPodcastCarousel(
            title: '💻 Technology & Innovation',
            podcasts: _techPodcasts,
            theme: theme,
          ),

        const SizedBox(height: 16),

        // 4. Daily News Podcasts Carousel
        if (_newsPodcasts.isNotEmpty)
          _buildPodcastCarousel(
            title: '📰 Daily News & Insight',
            podcasts: _newsPodcasts,
            theme: theme,
          ),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildPodcastCarousel({
    required String title,
    required List<Podcast> podcasts,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: podcasts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final podcast = podcasts[index];
              final isSubbed = _subscribedFeedUrls.contains(podcast.feedUrl);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PodcastDetailPage(
                        podcast: podcast,
                        audioHandler: widget.audioHandler,
                      ),
                    ),
                  ).then((_) => _loadSubscriptions());
                },
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: podcast.artworkUrl.isNotEmpty
                                  ? Image.network(
                                      podcast.artworkUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _artworkFallback(theme),
                                    )
                                  : _artworkFallback(theme),
                            ),
                          ),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.black.withOpacity(0.65),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  isSubbed ? Icons.check : Icons.add,
                                  size: 18,
                                  color: isSubbed
                                      ? Colors.greenAccent
                                      : Colors.white,
                                ),
                                onPressed: () => _toggleSubscribe(podcast),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        podcast.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        podcast.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _artworkFallback(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary.withOpacity(0.1),
      child: Icon(Icons.podcasts, color: theme.colorScheme.primary),
    );
  }
}
