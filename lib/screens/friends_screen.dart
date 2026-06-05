import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/providers/friends_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/widgets/themed_loading.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await ref.read(friendsProvider.notifier).refresh();
  }

  void _searchUsers(String query) {
    ref.read(friendsProvider.notifier).searchUsers(query);
  }

  @override
  Widget build(BuildContext context) {
    // Watch the friends state from Riverpod
    final friendsState = ref.watch(friendsProvider);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return CommandScaffold(
          theme: theme,
          title: 'Friends',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          actions: [
            IconButton(
              onPressed: _loadData,
              icon: Icon(
                Icons.refresh,
                color: theme.accentColor.withValues(alpha: 0.7),
                size: 24,
              ),
            ),
          ],
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT — search field on top (fixed: a TextField must not
                // live inside a FittedBox or focus/keyboard sizing breaks),
                // then the section rail + cache-freshness chip, scaled to
                // fit so the panel itself never scrolls.
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildSearchBar(theme, friendsState),
                      Expanded(
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: 230,
                              child: _buildNavRail(theme, friendsState),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // RIGHT — the selected section's content (swipeable).
                Expanded(
                  flex: 7,
                  child: friendsState.isLoading
                      ? _buildLoadingIndicator(theme)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildFriendsList(theme, friendsState),
                            _buildFriendRequestsList(theme, friendsState),
                            _buildSearchResults(theme, friendsState),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(GameTheme theme, FriendsState friendsState) {
    // Functional input — a faint borderless fill is allowed here as the
    // affordance; everything else on this screen stays fully transparent.
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by name or email...',
          hintStyle: TextStyle(color: theme.textMuted),
          prefixIcon: Icon(
            Icons.search,
            color: theme.textMuted,
          ),
          suffixIcon: friendsState.searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    ref.read(friendsProvider.notifier).clearSearch();
                    _tabController.animateTo(0);
                  },
                  icon: Icon(
                    Icons.clear,
                    color: theme.textMuted,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: TextStyle(color: theme.textPrimary),
        onChanged: (value) {
          _searchUsers(value);
          if (value.isNotEmpty) {
            _tabController.animateTo(2);
          }
        },
      ),
    );
  }

  /// Vertical, borderless section rail for the left region. Driven by
  /// the existing [_tabController] so taps and TabBarView swipes stay
  /// in sync; the cache-freshness chip lives at the bottom of the rail.
  Widget _buildNavRail(GameTheme theme, FriendsState friendsState) {
    final friends = friendsState.friends;
    final friendRequests = friendsState.friendRequests;

    final items = [
      (Icons.people, 'Friends', friends.length),
      (Icons.person_add, 'Requests', friendRequests.length),
      (Icons.search, 'Search', null),
    ];

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _buildNavItem(theme, i, items[i].$1, items[i].$2, items[i].$3),
            const SizedBox(height: 8),
            // "Updated X ago" chip — surfaces Drift cache freshness
            // for the currently-active tab so the user can tell if
            // they're looking at stale offline data.
            _buildStalenessChip(theme, friendsState),
          ],
        );
      },
    );
  }

  Widget _buildNavItem(
    GameTheme theme,
    int i,
    IconData icon,
    String label,
    int? count,
  ) {
    final selected = _tabController.index == i;
    // The Requests badge stays SOLID red — it's a functional notification
    // badge, not decoration.
    final isRequestsBadge = i == 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabController.animateTo(i),
      // No background at all — selection reads purely through the neon icon,
      // brighter text, and a small glowing indicator dot.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (count != null && count > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isRequestsBadge
                      ? Colors.red
                      : theme.accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isRequestsBadge ? Colors.white : theme.textMuted,
                  ),
                ),
              ),
            if (selected) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Inline chip surfacing Drift cache freshness for the active tab.
  /// Tap → forced refresh. Hidden when the cache has never been
  /// populated AND there's no data — avoids a "Never updated" label
  /// on a first-launch offline session.
  Widget _buildStalenessChip(GameTheme theme, FriendsState state) {
    final tabIndex = _tabController.index;
    DateTime? ts;
    bool hasData;
    switch (tabIndex) {
      case 1:
        ts = state.requestsLastRefreshedAt;
        hasData = state.friendRequests.isNotEmpty;
        break;
      case 2:
        // Search tab — no cache. Suppress the chip entirely; the
        // search box itself is the freshness signal there.
        return const SizedBox.shrink();
      case 0:
      default:
        ts = state.friendsLastRefreshedAt;
        hasData = state.friends.isNotEmpty;
    }
    if (ts == null && !hasData) return const SizedBox.shrink();
    final label = ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(friendsProvider.notifier).refresh(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.refresh_rounded,
                color: theme.accentColor.withValues(alpha: 0.7),
                size: 12,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.75),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeAge(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildLoadingIndicator(GameTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading friends...',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList(GameTheme theme, FriendsState friendsState) {
    final friends = friendsState.friends;

    if (friends.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'No Friends Yet',
        subtitle: 'Search for users to add as friends!',
        theme: theme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _buildUserCard(
          user: friend,
          theme: theme,
          trailing: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view_profile',
                child: Row(
                  children: [
                    Icon(Icons.person, color: theme.accentColor),
                    const SizedBox(width: 8),
                    const Text('View Profile'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'remove_friend',
                child: Row(
                  children: [
                    const Icon(Icons.person_remove, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text('Remove Friend'),
                  ],
                ),
              ),
            ],
            onSelected: (value) => _handleFriendAction(value, friend),
          ),
        ).gameListItem(index);
      },
    );
  }

  Widget _buildFriendRequestsList(GameTheme theme, FriendsState friendsState) {
    final receivedRequests = friendsState.receivedRequests;
    final sentRequests = friendsState.sentRequests;

    if (receivedRequests.isEmpty && sentRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.mail_outline,
        title: 'No Friend Requests',
        subtitle: 'Friend requests will appear here',
        theme: theme,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (receivedRequests.isNotEmpty) ...[
          Text(
            'RECEIVED (${receivedRequests.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 12),
          ...receivedRequests.indexed.map(
            (entry) =>
                _buildFriendRequestCard(entry.$2, theme).gameListItem(entry.$1),
          ),
          const SizedBox(height: 20),
        ],
        if (sentRequests.isNotEmpty) ...[
          Text(
            'SENT (${sentRequests.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 12),
          ...sentRequests.indexed.map(
            (entry) => _buildSentRequestCard(entry.$2, theme)
                .gameListItem(entry.$1 + receivedRequests.length),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchResults(GameTheme theme, FriendsState friendsState) {
    final searchQuery = friendsState.searchQuery;
    final isSearching = friendsState.isSearching;
    final searchResults = friendsState.searchResults;

    if (searchQuery.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search,
        title: 'Search for Friends',
        subtitle: 'Enter a name or email to find friends',
        theme: theme,
      );
    }

    if (isSearching) {
      return ThemedLoading(theme: theme, label: 'Searching...');
    }

    if (searchResults.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: 'No Users Found',
        subtitle: 'Try searching with a different name or email',
        theme: theme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final user = searchResults[index];
        return _buildUserCard(
          user: user,
          theme: theme,
          trailing: _buildSearchUserActions(user, theme, friendsState),
        ).gameListItem(index);
      },
    );
  }

  Widget _buildUserCard({
    required UserProfile user,
    required GameTheme theme,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.accentColor.withValues(alpha: 0.14),
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  onBackgroundImageError:
                      user.photoUrl != null ? (e, s) {} : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.publicLabel.isNotEmpty
                              ? user.publicLabel[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: theme.accentColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              user.publicLabel,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            user.status.emoji,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user.status.displayName,
                            style: TextStyle(
                              fontSize: 12,
                              color: _getStatusColor(user.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.emoji_events,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${user.highScore}',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.games,
                            size: 14,
                            color: theme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${user.totalGamesPlayed} games',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (user.statusMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          user.statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendRequestCard(FriendRequest request, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.accentColor.withValues(alpha: 0.14),
                  backgroundImage: request.fromUserPhotoUrl != null
                      ? NetworkImage(request.fromUserPhotoUrl!)
                      : null,
                  onBackgroundImageError:
                      request.fromUserPhotoUrl != null ? (e, s) {} : null,
                  child: request.fromUserPhotoUrl == null
                      ? Text(
                          request.fromUserName.isNotEmpty
                              ? request.fromUserName[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: theme.accentColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.fromUserName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textPrimary,
                        ),
                      ),
                      Text(
                        'Sent ${request.formattedDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeonButton(
                      onPressed: () => _rejectFriendRequest(request.fromUserId),
                      label: 'Reject',
                      theme: theme,
                      variant: NeonButtonVariant.ghost,
                    ),
                    const SizedBox(width: 8),
                    NeonButton(
                      onPressed: () => _acceptFriendRequest(request.fromUserId),
                      label: 'Accept',
                      theme: theme,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSentRequestCard(FriendRequest request, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.accentColor.withValues(alpha: 0.14),
                  child: Text(
                    request.toUserName.isNotEmpty
                        ? request.toUserName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      color: theme.accentColor.withValues(alpha: 0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.toUserName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.textPrimary,
                        ),
                      ),
                      Text(
                        'Sent ${request.formattedDate}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pending',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchUserActions(UserProfile user, GameTheme theme, FriendsState friendsState) {
    // Check if already friends or have pending request using provider helper methods
    final notifier = ref.read(friendsProvider.notifier);
    final isFriend = notifier.isFriend(user.uid);
    final hasSentRequest = notifier.hasSentRequestTo(user.uid);
    final hasReceivedRequest = notifier.hasReceivedRequestFrom(user.uid);

    if (isFriend) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '✓ Friends',
          style: TextStyle(
            fontSize: 12,
            color: Colors.green,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (hasSentRequest) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Pending',
          style: TextStyle(
            fontSize: 12,
            color: Colors.orange,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (hasReceivedRequest) {
      return NeonButton(
        onPressed: () => _acceptFriendRequest(user.uid),
        label: 'Accept',
        theme: theme,
      );
    }

    return NeonButton(
      onPressed: () => _sendFriendRequest(user.uid),
      label: 'Add Friend',
      icon: Icons.person_add,
      theme: theme,
      variant: NeonButtonVariant.outline,
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required GameTheme theme,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: theme.accentColor.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: theme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return Colors.green;
      case UserStatus.playing:
        return Colors.blue;
      case UserStatus.offline:
        return Colors.grey;
    }
  }

  Future<void> _sendFriendRequest(String userId) async {
    final success = await ref.read(friendsProvider.notifier).sendFriendRequest(userId);
    if (success && mounted) {
      getIt<AnalyticsFacade>().trackFriendAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request sent!')));
    }
  }

  Future<void> _acceptFriendRequest(String fromUserId) async {
    final success = await ref.read(friendsProvider.notifier).acceptFriendRequest(fromUserId);
    if (success && mounted) {
      getIt<AnalyticsFacade>().trackFriendAdded();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request accepted!')));
    }
  }

  Future<void> _rejectFriendRequest(String fromUserId) async {
    final success = await ref.read(friendsProvider.notifier).rejectFriendRequest(fromUserId);
    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Friend request rejected')));
    }
  }

  void _handleFriendAction(String action, UserProfile friend) {
    switch (action) {
      case 'view_profile':
        // Navigate to user profile view
        _showUserProfile(friend);
        break;
      case 'remove_friend':
        _showRemoveFriendDialog(friend);
        break;
    }
  }

  void _showUserProfile(UserProfile friend) {
    final theme = context.read<ThemeCubit>().state.currentTheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.person, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(friend.username, style: TextStyle(color: theme.accentColor)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'High Score: ${friend.highScore}',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 8),
            Text(
              'Total Games: ${friend.totalGamesPlayed}',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 8),
            Text(
              'Level: ${friend.level}',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
            ),
            if (friend.statusMessage?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                'Status: "${friend.statusMessage}"',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.6),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: theme.accentColor)),
          ),
        ],
      ),
    );
  }

  void _showRemoveFriendDialog(UserProfile friend) {
    final theme = context.read<ThemeCubit>().state.currentTheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Remove Friend',
          style: TextStyle(color: theme.accentColor),
        ),
        content: Text(
          'Remove ${friend.displayName} from your friends list?',
          style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              navigator.pop();
              final success = await ref.read(friendsProvider.notifier).removeFriend(friend.uid);
              if (success) {
                getIt<AnalyticsFacade>().trackFriendRemoved();
              }
              if (success && mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('${friend.displayName} removed from friends'),
                  ),
                );
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
