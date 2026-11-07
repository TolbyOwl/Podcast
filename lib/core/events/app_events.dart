import 'package:flutter/foundation.dart';

/// A simple app-wide event bus using ValueNotifiers.
/// Any page can listen to these and refresh when needed.
class AppEvents {
  AppEvents._();

  /// Incremented whenever settings that affect Discover content change
  /// (e.g., country/region). Listeners rebuild and reload their content.
  static final discoverRefresh = ValueNotifier<int>(0);

  /// Incremented whenever the user subscribes / unsubscribes from a podcast.
  /// Home page listens to this to auto-reload its grid.
  static final subscriptionsChanged = ValueNotifier<int>(0);

  static void notifyDiscoverRefresh() {
    discoverRefresh.value++;
  }

  static void notifySubscriptionsChanged() {
    subscriptionsChanged.value++;
  }
}
