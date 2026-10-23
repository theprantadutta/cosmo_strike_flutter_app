import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/providers/friends_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

enum _Tab { friends, requests, add }

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  _Tab _tab = _Tab.friends;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await ref.read(friendsProvider.notifier).refresh();
  }

  void _searchUsers(String query) {
    ref.read(friendsProvider.notifier).searchUsers(query);
  }

  void _setTab(_Tab tab) {
    if (tab != _tab) setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final friendsState = ref.watch(friendsProvider);
    final cs = context.cs;

    return CsScaffold(
      title: 'Squadron',
      trailing: [
        ?_freshness(friendsState),
        CsIconButton(
          icon: Symbols.refresh_rounded,
          size: 36,
          bordered: false,
          color: CsColors.ink60,
          tooltip: 'Refresh',
          onPressed: _loadData,
        ),
      ],
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        gap: cs(40),
        // LEFT — tabs + search field (a TextField must not live inside a
        // FittedBox, so it sits outside the scaled summary), then the
        // summary, which scales down instead of scrolling.
        // When the keyboard shrinks the body below the tabs + field, the
        // column keeps a minimum height and clips at the bottom (the
        // summary is behind the keyboard anyway) instead of overflowing.
        left: LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight < cs(130) ? cs(130) : c.maxHeight;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: h,
              maxHeight: h,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: CsSegmented<_Tab>(
                      segments: const {_Tab.friends: 'Wingmates', _Tab.requests: 'Requests', _Tab.add: 'Recruit'},
                      selected: _tab,
                      onChanged: _setTab,
                    ),
                  ),
                ),
                SizedBox(height: cs(14)),
                _buildSearchField(friendsState),
                SizedBox(height: cs(18)),
                Expanded(child: _SideColumn(children: _buildSummary(friendsState))),
              ]),
            ),
          );
        }),
        // RIGHT — the selected section's list.
        right: friendsState.isLoading
            ? const CsLoadingState(label: 'Loading squadron')
            : AnimatedSwitcher(
                duration: CsMotion.base,
                switchInCurve: CsMotion.standard,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    _Tab.friends => _buildFriendsList(friendsState),
                    _Tab.requests => _buildFriendRequestsList(friendsState),
                    _Tab.add => _buildSearchResults(friendsState),
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildSearchField(FriendsState friendsState) {
    final t = context.type;
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      style: t.body.copyWith(color: CsColors.ink),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Pilot name or email',
        prefixIcon: const Icon(Symbols.search_rounded, color: CsColors.ink45, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        suffixIcon: friendsState.searchQuery.isNotEmpty
            ? CsIconButton(
                icon: Symbols.close_rounded,
                size: 30,
                bordered: false,
                color: CsColors.ink60,
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  ref.read(friendsProvider.notifier).clearSearch();
                  _setTab(_Tab.friends);
                },
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
      onChanged: (value) {
        _searchUsers(value);
        if (value.isNotEmpty) _setTab(_Tab.add);
      },
    );
  }

  List<Widget> _buildSummary(FriendsState state) {
    final cs = context.cs;
    final t = cs.type;
    final received = state.receivedRequests.length;
    final sent = state.sentRequests.length;
    return [
      const CsLabel('Your squadron'),
      SizedBox(height: cs(4)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${state.friends.length}',
          maxLines: 1,
          style: t.display(64, em: -0.04, height: 1.05, color: state.friends.isEmpty ? CsColors.ink25 : CsColors.ink),
        ),
      ),
      Text(
        state.friends.length == 1 ? 'WINGMATE' : 'WINGMATES',
        style: t.mono(12, em: 0.06, color: CsColors.ink60),
      ),
      SizedBox(height: cs(14)),
      if (received > 0)
        CsPressable(
          onTap: () => _setTab(_Tab.requests),
          semanticLabel: '$received new requests',
          child: CsChip(
            received == 1 ? '1 new request' : '$received new requests',
            kind: CsChipKind.pink,
            icon: Symbols.mail_rounded,
            size: 10,
          ),
        )
      else
        Text(
          sent > 0 ? '$sent PENDING SENT' : 'NO PENDING REQUESTS',
          style: t.mono(10, color: CsColors.ink45),
        ),
      const Spacer(),
      SizedBox(height: cs(14)),
      Text(
        'Find a pilot by name or email, then tap Add to send a request.',
        style: t.display(12, weight: FontWeight.w400, em: 0, height: 1.4, color: CsColors.ink45),
      ),
    ];
  }

  /// "UPDATED 3M AGO" for the active tab's Drift cache. Tap → forced refresh.
  /// Hidden on the search tab (no cache) and before the first population.
  Widget? _freshness(FriendsState state) {
    DateTime? ts;
    bool hasData;
    switch (_tab) {
      case _Tab.requests:
        ts = state.requestsLastRefreshedAt;
        hasData = state.friendRequests.isNotEmpty;
      case _Tab.add:
        return null;
      case _Tab.friends:
        ts = state.friendsLastRefreshedAt;
        hasData = state.friends.isNotEmpty;
    }
    if (ts == null && !hasData) return null;
    final label = ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';
    return Flexible(
      child: CsPressable(
        semanticLabel: '$label. Tap to refresh',
        onTap: () => ref.read(friendsProvider.notifier).refresh(),
        child: SizedBox(height: 44, child: Center(child: CsMeta(label))),
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

  Widget _buildFriendsList(FriendsState friendsState) {
    final friends = friendsState.friends;
    final compact = context.cs.isCompact;

    if (friends.isEmpty) {
      if (friendsState.error != null) {
        return CsEmptyState.error(
          title: "Couldn't load squadron",
          message: friendsState.error,
          action: CsButton.secondary(label: 'Retry', icon: Symbols.refresh_rounded, onPressed: _loadData),
        );
      }
      return CsEmptyState(
        icon: Symbols.group_rounded,
        title: 'No wingmates yet',
        message: 'Recruit pilots to fly with your squadron.',
        action: CsButton.primary(
          label: 'Recruit pilots',
          icon: Symbols.person_search_rounded,
          onPressed: () {
            _setTab(_Tab.add);
            _searchFocus.requestFocus();
          },
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: friends.length,
      itemBuilder: (context, index) {
        final friend = friends[index];
        return _userRow(
          friend,
          onTap: () => _showUserProfile(friend),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!compact)
              CsButton.secondary(
                label: 'Pilot File',
                size: CsButtonSize.small,
                onPressed: () => _showUserProfile(friend),
              ),
            CsIconButton(
              icon: Symbols.person_remove_rounded,
              size: 34,
              bordered: false,
              color: CsColors.pink,
              tooltip: 'Remove wingmate',
              onPressed: () => _showRemoveFriendDialog(friend),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildFriendRequestsList(FriendsState friendsState) {
    final receivedRequests = friendsState.receivedRequests;
    final sentRequests = friendsState.sentRequests;
    final cs = context.cs;

    if (receivedRequests.isEmpty && sentRequests.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.mail_rounded,
        title: 'No requests',
        message: 'Squadron requests land here.',
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (receivedRequests.isNotEmpty) ...[
          CsLabel('Received (${receivedRequests.length})'),
          SizedBox(height: cs(4)),
          for (final request in receivedRequests)
            CsListRow(
              leading: _Avatar(name: request.fromUserName, photoUrl: request.fromUserPhotoUrl),
              title: request.fromUserName,
              below: _mono('SENT ${request.formattedDate}'.toUpperCase()),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                CsButton.text(
                  label: 'Decline',
                  size: CsButtonSize.small,
                  onPressed: () => _rejectFriendRequest(request.fromUserId),
                ),
                CsButton.secondary(
                  label: 'Accept',
                  size: CsButtonSize.small,
                  icon: Symbols.check_rounded,
                  onPressed: () => _acceptFriendRequest(request.fromUserId),
                ),
              ]),
            ),
          SizedBox(height: cs(22)),
        ],
        if (sentRequests.isNotEmpty) ...[
          CsLabel('Sent (${sentRequests.length})'),
          SizedBox(height: cs(4)),
          for (final request in sentRequests)
            CsListRow(
              leading: _Avatar(name: request.toUserName),
              title: request.toUserName,
              below: _mono('SENT ${request.formattedDate}'.toUpperCase()),
              trailing: const CsChip('Pending', icon: Symbols.schedule_rounded),
            ),
        ],
      ],
    );
  }

  Widget _buildSearchResults(FriendsState friendsState) {
    final searchQuery = friendsState.searchQuery;
    final isSearching = friendsState.isSearching;
    final searchResults = friendsState.searchResults;

    if (searchQuery.isEmpty) {
      return CsEmptyState(
        icon: Symbols.person_search_rounded,
        title: 'Recruit pilots',
        message: 'Enter a pilot name or email.',
        action: CsButton.secondary(
          label: 'Start typing',
          icon: Symbols.search_rounded,
          onPressed: () => _searchFocus.requestFocus(),
        ),
      );
    }

    if (isSearching) {
      return const CsLoadingState(label: 'Searching');
    }

    if (searchResults.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.search_off_rounded,
        title: 'No pilots found',
        message: 'Try another name or email.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final user = searchResults[index];
        return _userRow(user, trailing: _buildSearchUserActions(user));
      },
    );
  }

  Widget _mono(String text, {Color color = CsColors.ink45}) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.type.mono(10, color: color),
      );

  Widget _userRow(UserProfile user, {Widget? trailing, VoidCallback? onTap}) {
    final statusColor = switch (user.status) {
      UserStatus.online => CsColors.mint,
      UserStatus.playing => CsColors.cyan,
      UserStatus.offline => CsColors.ink45,
    };
    final t = context.type;
    return CsListRow(
      leading: _Avatar(name: user.publicLabel, photoUrl: user.photoUrl),
      title: user.publicLabel,
      titleTrailing: Text(
        user.status.displayName.toUpperCase(),
        maxLines: 1,
        style: t.mono(9, color: statusColor),
      ),
      subtitle: user.statusMessage,
      below: Text.rich(
        TextSpan(children: [
          TextSpan(text: 'BEST ${_formatThousands(user.highScore)}', style: const TextStyle(color: CsColors.gold)),
          // Level, not games: the friends API doesn't send a games count,
          // so this always read "0 GAMES".
          TextSpan(text: '  ·  LV ${user.level}'),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.mono(10, color: CsColors.ink45),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSearchUserActions(UserProfile user) {
    // Check if already friends or have pending request using provider helper methods
    final notifier = ref.read(friendsProvider.notifier);
    final isFriend = notifier.isFriend(user.uid);
    final hasSentRequest = notifier.hasSentRequestTo(user.uid);
    final hasReceivedRequest = notifier.hasReceivedRequestFrom(user.uid);

    if (isFriend) {
      return const CsChip('Wingmate', kind: CsChipKind.mint, icon: Symbols.check_rounded);
    }

    if (hasSentRequest) {
      return const CsChip('Pending', icon: Symbols.schedule_rounded);
    }

    if (hasReceivedRequest) {
      return CsButton.secondary(
        label: 'Accept',
        size: CsButtonSize.small,
        icon: Symbols.check_rounded,
        onPressed: () => _acceptFriendRequest(user.uid),
      );
    }

    return CsButton.secondary(
      label: 'Add',
      size: CsButtonSize.small,
      icon: Symbols.person_add_rounded,
      onPressed: () => _sendFriendRequest(user.uid),
    );
  }

  String _formatThousands(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  Future<void> _sendFriendRequest(String userId) async {
    final success = await ref.read(friendsProvider.notifier).sendFriendRequest(userId);
    if (success && mounted) {
      getIt<AnalyticsFacade>().trackFriendAdded();
      showCsToast(context, 'Request sent.', kind: CsToastKind.success);
    }
  }

  Future<void> _acceptFriendRequest(String fromUserId) async {
    final success = await ref.read(friendsProvider.notifier).acceptFriendRequest(fromUserId);
    if (success && mounted) {
      getIt<AnalyticsFacade>().trackFriendAdded();
      showCsToast(context, 'Wingmate added.', kind: CsToastKind.success);
    }
  }

  Future<void> _rejectFriendRequest(String fromUserId) async {
    final success = await ref.read(friendsProvider.notifier).rejectFriendRequest(fromUserId);
    if (success && mounted) {
      showCsToast(context, 'Request declined.');
    }
  }

  void _showUserProfile(UserProfile friend) {
    showCsDialog<void>(
      context,
      builder: (ctx) {
        final cs = ctx.cs;
        return CsDialog(
          eyebrow: 'Pilot File',
          titleWidget: Row(children: [
            _Avatar(name: friend.username, photoUrl: friend.photoUrl, size: 44),
            SizedBox(width: cs(14)),
            Expanded(
              child: Text(
                friend.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cs.type.display(26, em: -0.03, height: 1.05),
              ),
            ),
          ]),
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            CsStatGrid(
              columns: friend.totalGamesPlayed > 0 ? 3 : 2,
              stats: [
                CsStat(_formatThousands(friend.highScore), 'Best score', color: CsColors.gold),
                // Only some endpoints send a games count; skip a bogus 0.
                if (friend.totalGamesPlayed > 0) CsStat(_formatThousands(friend.totalGamesPlayed), 'Runs flown'),
                CsStat('${friend.level}', 'Pilot Rank', color: CsColors.violet),
              ],
            ),
            if (friend.statusMessage?.isNotEmpty == true) ...[
              SizedBox(height: cs(14)),
              Text('"${friend.statusMessage}"', style: cs.type.body),
            ],
          ]),
          actions: [
            CsButton.primary(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
          ],
        );
      },
    );
  }

  Future<void> _showRemoveFriendDialog(UserProfile friend) async {
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Squadron',
      title: 'Remove wingmate?',
      message: 'Drop ${friend.displayName} from your squadron?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final success = await ref.read(friendsProvider.notifier).removeFriend(friend.uid);
    if (success) {
      getIt<AnalyticsFacade>().trackFriendRemoved();
    }
    if (success && mounted) {
      showCsToast(context, '${friend.displayName} left your squadron.');
    }
  }
}

/// Like [CsAvatarRing] but takes a network URL (falls back to initials when
/// it is missing or fails to load).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl, this.size = 40});

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = cs(size);
    final initials = Center(
      child: Text(
        CsAvatarRing.initialsOf(name),
        style: cs.type.display(size * 0.32, weight: FontWeight.w700, em: 0.02, height: 1),
      ),
    );
    return SizedBox.square(
      dimension: d,
      child: CsPrismRing(
        circle: true,
        fill: CsColors.raised,
        colors: const [Color(0x26FFFFFF)],
        child: ClipOval(
          child: photoUrl == null
              ? initials
              : Image.network(photoUrl!, fit: BoxFit.cover, width: d, height: d, errorBuilder: (_, _, _) => initials),
        ),
      ),
    );
  }
}

/// Side summary column that fills the available height (so `Spacer`s can
/// push content apart on tall tablets) and scales DOWN instead of
/// overflowing on short phones.
class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth, maxWidth: c.maxWidth, minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      );
    });
  }
}
