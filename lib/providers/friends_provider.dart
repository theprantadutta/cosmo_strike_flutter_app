import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/services/social_service.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';

/// State for friends/social data
class FriendsState {
  final List<UserProfile> friends;
  final List<FriendRequest> friendRequests;
  final List<UserProfile> searchResults;
  final bool isLoading;
  final bool isSearching;
  final String searchQuery;
  final String? error;
  /// Drift-cache freshness — null until the first successful refresh
  /// of each list. Surfaced to the screen so a stale offline view
  /// can be labelled rather than silently passed off as live.
  final DateTime? friendsLastRefreshedAt;
  final DateTime? requestsLastRefreshedAt;

  const FriendsState({
    this.friends = const [],
    this.friendRequests = const [],
    this.searchResults = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.searchQuery = '',
    this.error,
    this.friendsLastRefreshedAt,
    this.requestsLastRefreshedAt,
  });

  /// Get received friend requests
  List<FriendRequest> get receivedRequests => friendRequests
      .where((r) => r.type == FriendRequestType.received)
      .toList();

  /// Get sent friend requests
  List<FriendRequest> get sentRequests =>
      friendRequests.where((r) => r.type == FriendRequestType.sent).toList();

  /// Check if there are pending received requests
  bool get hasReceivedRequests => receivedRequests.isNotEmpty;

  FriendsState copyWith({
    List<UserProfile>? friends,
    List<FriendRequest>? friendRequests,
    List<UserProfile>? searchResults,
    bool? isLoading,
    bool? isSearching,
    String? searchQuery,
    String? error,
    DateTime? friendsLastRefreshedAt,
    DateTime? requestsLastRefreshedAt,
  }) {
    return FriendsState(
      friends: friends ?? this.friends,
      friendRequests: friendRequests ?? this.friendRequests,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      searchQuery: searchQuery ?? this.searchQuery,
      error: error,
      friendsLastRefreshedAt:
          friendsLastRefreshedAt ?? this.friendsLastRefreshedAt,
      requestsLastRefreshedAt:
          requestsLastRefreshedAt ?? this.requestsLastRefreshedAt,
    );
  }
}

/// Notifier for friends with TTL-based auto-refresh
class FriendsNotifier extends StateNotifier<FriendsState> {
  final Ref _ref;
  final SocialService _service;
  Timer? _ttlTimer;
  Timer? _searchDebounce;

  static const _ttl = Duration(minutes: 2);
  static const _searchDebounceDelay = Duration(milliseconds: 300);

  FriendsNotifier(this._ref)
    : _service = SocialService(),
      super(const FriendsState(isLoading: true)) {
    _initialize();
  }

  void _initialize() {
    // Drift-first paint: hydrate from the local cache immediately,
    // then kick a background refresh that re-hydrates when it lands.
    _loadData();

    // Set up TTL-based refresh
    _startTtlTimer();

    // Listen for connectivity changes - refresh when coming online
    _ref.listen<AsyncValue<bool>>(isOnlineProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final isNowOnline = next.value == true;
      if (wasOffline && isNowOnline) {
        // Stagger connectivity-restore refreshes to avoid API stampede
        Future.delayed(const Duration(seconds: 2), () => refresh());
      }
    });
  }

  void _startTtlTimer() {
    _ttlTimer?.cancel();
    _ttlTimer = Timer.periodic(_ttl, (_) {
      final isOnline = _ref.read(isOnlineSyncProvider);
      if (isOnline) {
        refresh();
      }
    });
  }

  Future<void> _loadData() async {
    // Cache-first paint: pull whatever's in Drift right now. Only show
    // the spinner if the cache is genuinely empty (brand-new install
    // or post-signOut wipe).
    await _hydrateFromCache(isLoading: false);
    final hadCache =
        state.friends.isNotEmpty || state.friendRequests.isNotEmpty;
    state = state.copyWith(isLoading: !hadCache, error: null);

    try {
      await Future.wait([
        _service.refreshFriends(),
        _service.refreshFriendRequests(),
      ]);
      await _hydrateFromCache(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: hadCache ? null : 'Failed to load friends',
      );
    }
  }

  /// Refresh friends data from the server. Keeps the cached entries
  /// on screen while the network round-trip is in flight.
  Future<void> refresh() async {
    final hadCache =
        state.friends.isNotEmpty || state.friendRequests.isNotEmpty;
    state = state.copyWith(isLoading: !hadCache, error: null);

    try {
      await Future.wait([
        _service.refreshFriends(),
        _service.refreshFriendRequests(),
      ]);
      await _hydrateFromCache(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: hadCache ? null : 'Failed to refresh friends',
      );
    }
  }

  /// Read whatever's in the Drift cache into state. Called on init
  /// (for cache-first paint), after every refresh, and after every
  /// successful mutation so the screen reflects the latest local
  /// truth without waiting for the next TTL tick.
  Future<void> _hydrateFromCache({bool? isLoading}) async {
    final friends = await _service.getFriends();
    final requests = await _service.getFriendRequests();
    state = state.copyWith(
      friends: friends,
      friendRequests: requests,
      isLoading: isLoading,
      friendsLastRefreshedAt:
          await _service.getLastRefreshedAt('friends'),
      requestsLastRefreshedAt:
          await _service.getLastRefreshedAt('requests'),
    );
  }

  /// Search for users (debounced)
  void searchUsers(String query) {
    state = state.copyWith(searchQuery: query);

    if (query.length < 2) {
      state = state.copyWith(searchResults: [], isSearching: false);
      return;
    }

    state = state.copyWith(isSearching: true);

    // Debounce search
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () async {
      try {
        final results = await _service.searchUsers(query);
        state = state.copyWith(searchResults: results, isSearching: false);
      } catch (e) {
        state = state.copyWith(isSearching: false, error: 'Search failed');
      }
    });
  }

  /// Clear search results
  void clearSearch() {
    _searchDebounce?.cancel();
    state = state.copyWith(
      searchQuery: '',
      searchResults: [],
      isSearching: false,
    );
  }

  /// Send friend request. Service drops the request into the
  /// outbound queue (live API) and refreshes the cache on success;
  /// we just need to re-read the cache to surface the update.
  Future<bool> sendFriendRequest(String userId) async {
    final success = await _service.sendFriendRequest(userId);
    if (success) await _hydrateFromCache();
    return success;
  }

  /// Accept friend request (resolved by sender userId — see
  /// SocialService.acceptFriendRequest).
  Future<bool> acceptFriendRequest(String fromUserId) async {
    final success = await _service.acceptFriendRequest(fromUserId);
    if (success) await _hydrateFromCache();
    return success;
  }

  Future<bool> rejectFriendRequest(String fromUserId) async {
    final success = await _service.rejectFriendRequest(fromUserId);
    if (success) await _hydrateFromCache();
    return success;
  }

  Future<bool> removeFriend(String friendUserId) async {
    final success = await _service.removeFriend(friendUserId);
    if (success) await _hydrateFromCache();
    return success;
  }

  /// Get user profile
  Future<UserProfile?> getUserProfile(String userId) async {
    return await _service.getUserProfile(userId);
  }

  /// Check if a user is already a friend
  bool isFriend(String userId) {
    return state.friends.any((f) => f.uid == userId);
  }

  /// Check if a friend request has been sent to a user
  bool hasSentRequestTo(String userId) {
    return state.sentRequests.any((r) => r.toUserId == userId);
  }

  /// Check if a friend request has been received from a user
  bool hasReceivedRequestFrom(String userId) {
    return state.receivedRequests.any((r) => r.fromUserId == userId);
  }

  @override
  void dispose() {
    _ttlTimer?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}

/// Provider for friends state
final friendsProvider = StateNotifierProvider<FriendsNotifier, FriendsState>((
  ref,
) {
  return FriendsNotifier(ref);
});

/// Convenience provider for friends list
final friendsListProvider = Provider<List<UserProfile>>((ref) {
  return ref.watch(friendsProvider).friends;
});

/// Convenience provider for friend requests
final friendRequestsProvider = Provider<List<FriendRequest>>((ref) {
  return ref.watch(friendsProvider).friendRequests;
});

/// Convenience provider for received friend requests
final receivedRequestsProvider = Provider<List<FriendRequest>>((ref) {
  return ref.watch(friendsProvider).receivedRequests;
});

/// Convenience provider for sent friend requests
final sentRequestsProvider = Provider<List<FriendRequest>>((ref) {
  return ref.watch(friendsProvider).sentRequests;
});

/// Convenience provider for search results
final friendSearchResultsProvider = Provider<List<UserProfile>>((ref) {
  return ref.watch(friendsProvider).searchResults;
});

/// Convenience provider for loading state
final friendsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(friendsProvider).isLoading;
});

/// Convenience provider for searching state
final friendsSearchingProvider = Provider<bool>((ref) {
  return ref.watch(friendsProvider).isSearching;
});

/// Convenience provider for pending requests count
final pendingRequestsCountProvider = Provider<int>((ref) {
  return ref.watch(friendsProvider).receivedRequests.length;
});
