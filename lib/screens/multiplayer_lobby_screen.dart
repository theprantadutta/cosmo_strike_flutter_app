import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/multiplayer/multiplayer_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/widgets/gradient_button.dart';

class MultiplayerLobbyScreen extends StatefulWidget {
  final String? gameId;

  const MultiplayerLobbyScreen({super.key, this.gameId});

  @override
  State<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends State<MultiplayerLobbyScreen> {
  final TextEditingController _roomCodeController = TextEditingController();
  final ConnectivityService _connectivityService = ConnectivityService();
  int _selectedPlayerCount = 2;

  @override
  void initState() {
    super.initState();
    _connectivityService.addListener(_onConnectivityChanged);

    // Load available games on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_connectivityService.isOnline) {
        context.read<MultiplayerCubit>().loadAvailableGames();
      }

      // If gameId is provided, join that game
      if (widget.gameId != null) {
        if (_connectivityService.isOnline) {
          context.read<MultiplayerCubit>().joinGame(widget.gameId!);
        } else {
          _showOfflineMessage();
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivityService.removeListener(_onConnectivityChanged);
    _roomCodeController.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() {
    // Trigger rebuild when connectivity changes
    if (mounted) setState(() {});
  }

  void _showOfflineMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'You\'re offline. Multiplayer requires an internet connection.',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return BlocListener<MultiplayerCubit, MultiplayerState>(
          listenWhen: (prev, curr) =>
              prev.errorMessage != curr.errorMessage &&
              curr.errorMessage != null,
          listener: (context, state) {
            // Show error snackbar
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'DISMISS',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ),
            );
            context.read<MultiplayerCubit>().clearError();
          },
          child: BlocBuilder<MultiplayerCubit, MultiplayerState>(
            builder: (context, multiplayerState) {
              return BlocBuilder<AuthCubit, AuthState>(
                builder: (context, authState) {
                  // Navigate to game screen when game starts
                  if (multiplayerState.isGameActive) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      context.pushReplacement(AppRoutes.multiplayerGame);
                    });
                  }

                  return Scaffold(
                    bottomNavigationBar: const SnakeBannerAd(),
                    body: AppBackground(
                      theme: theme,
                      child: SafeArea(
                        child: multiplayerState.matchmakingTimedOut
                            ? _buildMatchmakingTimeoutUI(
                                context,
                                multiplayerState,
                                theme,
                              )
                            : multiplayerState.status ==
                                  MultiplayerStatus.inMatchmaking
                            ? _buildMatchmakingUI(
                                context,
                                multiplayerState,
                                theme,
                              )
                            : multiplayerState.isInGame
                            ? _buildGameLobby(
                                context,
                                multiplayerState,
                                theme,
                                authState,
                              )
                            : _buildMainLobby(
                                context,
                                multiplayerState,
                                theme,
                                authState,
                              ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMainLobby(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
    AuthState authState,
  ) {
    return Column(
      children: [
        // Header
        _buildHeader(theme),

        // Main content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Quick Match Section
                _buildQuickMatchSection(context, multiplayerState, theme),

                const SizedBox(height: 32),

                // Join Game Section
                _buildJoinGameSection(context, multiplayerState, theme),

                const SizedBox(height: 32),

                // Create Game Section
                _buildCreateGameSection(context, multiplayerState, theme),

                if (multiplayerState.availableGames.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildAvailableGamesSection(context, multiplayerState, theme),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGameLobby(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
    AuthState authState,
  ) {
    final game = multiplayerState.currentGame!;
    final isStarting = game.status == MultiplayerGameStatus.starting;

    return Stack(
      children: [
        Column(
          children: [
            // Header with room info
            _buildGameHeader(theme, game),

            // Game info and players
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Game mode info
                    _buildGameModeCard(theme, game),

                    const SizedBox(height: 24),

                    // Players list
                    _buildPlayersSection(theme, game, authState),

                    const Spacer(),

                    // Ready/Leave buttons
                    _buildLobbyActions(
                      context,
                      multiplayerState,
                      theme,
                      game,
                      authState,
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Countdown overlay
        if (isStarting) _buildCountdownOverlay(theme),
      ],
    );
  }

  Widget _buildCountdownOverlay(GameTheme theme) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 3, end: 0),
      duration: const Duration(seconds: 3),
      builder: (context, value, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.85),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                  child: Text(
                    value > 0 ? '$value' : 'GO!',
                    key: ValueKey<int>(value),
                    style: TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: value > 0 ? Colors.white : Colors.green,
                      shadows: [
                        Shadow(
                          color: value > 0 ? theme.accentColor : Colors.green,
                          blurRadius: 30,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  value > 0 ? 'Get Ready!' : '',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(GameTheme theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back, color: theme.accentColor, size: 24),
          ),

          const SizedBox(width: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MULTIPLAYER',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: theme.accentColor,
                  letterSpacing: 2,
                ),
              ).gameEntrance(),

              Text(
                'Play with friends online',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.accentColor.withValues(alpha: 0.7),
                ),
              ).gameEntrance(delay: 100.ms),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGameHeader(GameTheme theme, MultiplayerGame game) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              context.read<MultiplayerCubit>().leaveGame();
              context.pop();
            },
            icon: Icon(Icons.arrow_back, color: theme.accentColor, size: 24),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.modeDisplayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: theme.accentColor,
                  ),
                ),

                if (game.roomCode != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.foodColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.foodColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.key, size: 16, color: theme.foodColor),
                        const SizedBox(width: 6),
                        Text(
                          'Room: ${game.roomCode}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.foodColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: game.roomCode!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Room code copied!'),
                                backgroundColor: theme.foodColor,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Icon(
                            Icons.copy,
                            size: 14,
                            color: theme.foodColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMatchSection(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.withValues(alpha: 0.15),
            Colors.green.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.flash_on, size: 40, color: Colors.green),

          const SizedBox(height: 16),

          Text(
            'QUICK MATCH',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Find opponents automatically',
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 16),

          // Player count selector
          Text(
            'Players:',
            style: TextStyle(
              fontSize: 12,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [2, 4, 6, 8].map((count) {
              final isSelected = _selectedPlayerCount == count;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedPlayerCount = count),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.green.withValues(alpha: 0.3)
                          : theme.backgroundColor.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.green
                            : theme.accentColor.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.green : theme.accentColor,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          GradientButton(
            onPressed: multiplayerState.isLoading
                ? null
                : () {
                    context.read<MultiplayerCubit>().quickMatch(
                      MultiplayerGameMode.classic,
                      playerCount: _selectedPlayerCount,
                    );
                  },
            text: multiplayerState.isLoading ? 'FINDING...' : 'FIND MATCH',
            primaryColor: Colors.green,
            secondaryColor: Colors.green.withValues(alpha: 0.8),
            icon: Icons.search,
          ),
        ],
      ),
    ).gameZoomIn(delay: 100.ms);
  }

  Widget _buildMatchmakingUI(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    final elapsed = multiplayerState.matchmakingElapsedSeconds;
    final remaining = 60 - elapsed;
    final progress = elapsed / 60.0;

    return Column(
      children: [
        _buildHeader(theme),

        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green.withValues(alpha: 0.15),
                    Colors.green.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated search indicator with timer
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: 1 - progress,
                          strokeWidth: 6,
                          backgroundColor: Colors.grey.withValues(alpha: 0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            remaining <= 10 ? Colors.orange : Colors.green,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$remaining',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: remaining <= 10
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                          Text(
                            'sec',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.accentColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'SEARCHING FOR PLAYERS...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.accentColor,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '${multiplayerState.matchmakingMode?.modeDisplayName ?? 'Classic'} • ${multiplayerState.matchmakingPlayerCount ?? 2} Players',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.accentColor.withValues(alpha: 0.7),
                    ),
                  ),

                  if (multiplayerState.matchmakingQueuePosition > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Queue Position: ${multiplayerState.matchmakingQueuePosition}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.accentColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  GradientButton(
                    onPressed: () {
                      context.read<MultiplayerCubit>().cancelMatchmaking();
                    },
                    text: 'CANCEL',
                    primaryColor: Colors.red,
                    secondaryColor: Colors.red.withValues(alpha: 0.8),
                    icon: Icons.close,
                    outlined: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchmakingTimeoutUI(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    return Column(
      children: [
        _buildHeader(theme),

        Expanded(
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withValues(alpha: 0.15),
                    Colors.orange.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Timeout icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.hourglass_empty,
                      size: 40,
                      color: Colors.orange,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'NO PLAYERS FOUND',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: theme.accentColor,
                      letterSpacing: 1,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'Sorry, we couldn\'t find any opponents.\nTry again or create your own room!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.accentColor.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          onPressed: () {
                            context
                                .read<MultiplayerCubit>()
                                .clearMatchmakingTimeout();
                          },
                          text: 'GO BACK',
                          primaryColor: Colors.grey,
                          secondaryColor: Colors.grey.withValues(alpha: 0.8),
                          icon: Icons.arrow_back,
                          outlined: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          onPressed: () {
                            context
                                .read<MultiplayerCubit>()
                                .clearMatchmakingTimeout();
                            context.read<MultiplayerCubit>().quickMatch(
                              multiplayerState.matchmakingMode ??
                                  MultiplayerGameMode.classic,
                              playerCount:
                                  multiplayerState.matchmakingPlayerCount ?? 2,
                            );
                          },
                          text: 'TRY AGAIN',
                          primaryColor: Colors.green,
                          secondaryColor: Colors.green.withValues(alpha: 0.8),
                          icon: Icons.refresh,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJoinGameSection(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.15),
            Colors.blue.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.meeting_room, size: 40, color: Colors.blue),

          const SizedBox(height: 16),

          Text(
            'JOIN ROOM',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Enter room code to join',
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _roomCodeController,
            decoration: InputDecoration(
              hintText: 'Enter room code',
              hintStyle: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
              filled: true,
              fillColor: theme.backgroundColor.withValues(alpha: 0.5),
            ),
            style: TextStyle(color: theme.accentColor),
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
          ),

          const SizedBox(height: 16),

          GradientButton(
            onPressed:
                multiplayerState.isLoading || _roomCodeController.text.isEmpty
                ? null
                : () {
                    context.read<MultiplayerCubit>().joinGame(
                      _roomCodeController.text.trim(),
                    );
                  },
            text: 'JOIN ROOM',
            primaryColor: Colors.blue,
            secondaryColor: Colors.blue.withValues(alpha: 0.8),
            icon: Icons.login,
          ),
        ],
      ),
    ).gameZoomIn(delay: 200.ms);
  }

  Widget _buildCreateGameSection(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: 0.15),
            Colors.purple.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.add_circle, size: 40, color: Colors.purple),

          const SizedBox(height: 16),

          Text(
            'CREATE ROOM',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Start your own game',
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: GradientButton(
                  onPressed: multiplayerState.isLoading
                      ? null
                      : () {
                          _showCreateGameDialog(context, theme, false);
                        },
                  text: 'PUBLIC',
                  primaryColor: Colors.purple,
                  secondaryColor: Colors.purple.withValues(alpha: 0.8),
                  icon: Icons.public,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: GradientButton(
                  onPressed: multiplayerState.isLoading
                      ? null
                      : () {
                          _showCreateGameDialog(context, theme, true);
                        },
                  text: 'PRIVATE',
                  primaryColor: Colors.purple,
                  secondaryColor: Colors.purple.withValues(alpha: 0.8),
                  icon: Icons.lock,
                ),
              ),
            ],
          ),
        ],
      ),
    ).gameZoomIn(delay: 300.ms);
  }

  Widget _buildAvailableGamesSection(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AVAILABLE GAMES',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.accentColor,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(height: 16),

        ...multiplayerState.availableGames.map(
          (game) => _buildGameCard(context, theme, game),
        ),
      ],
    );
  }

  Widget _buildGameCard(
    BuildContext context,
    GameTheme theme,
    MultiplayerGame game,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(game.modeEmoji, style: const TextStyle(fontSize: 24)),
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.modeDisplayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                Text(
                  '${game.players.length}/${game.maxPlayers} players',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.accentColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          GradientButton(
            onPressed: () {
              context.read<MultiplayerCubit>().joinGame(game.id);
            },
            text: 'JOIN',
            primaryColor: theme.accentColor,
            secondaryColor: theme.foodColor,
            width: 80,
            height: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildGameModeCard(GameTheme theme, MultiplayerGame game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.withValues(alpha: 0.15),
            Colors.orange.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(game.modeEmoji, style: const TextStyle(fontSize: 32)),
            ),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.modeDisplayName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getGameModeDescription(game.mode),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.accentColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayersSection(
    GameTheme theme,
    MultiplayerGame game,
    AuthState authState,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PLAYERS (${game.players.length}/${game.maxPlayers})',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.accentColor.withValues(alpha: 0.8),
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 16),

          ...game.players.map(
            (player) => _buildPlayerItem(theme, player, authState),
          ),

          if (!game.isFull) _buildWaitingSlot(theme),
        ],
      ),
    );
  }

  Widget _buildPlayerItem(
    GameTheme theme,
    MultiplayerPlayer player,
    AuthState authState,
  ) {
    final currentUserId = authState.userId;
    final isCurrentUser = currentUserId == player.userId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? theme.accentColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isCurrentUser
            ? Border.all(color: theme.accentColor.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: player.photoUrl != null
                ? NetworkImage(player.photoUrl!)
                : null,
            onBackgroundImageError: player.photoUrl != null ? (e, s) {} : null,
            backgroundColor: theme.accentColor.withValues(alpha: 0.2),
            child: player.photoUrl == null
                ? Icon(Icons.person, color: theme.accentColor, size: 24)
                : null,
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      player.publicLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: theme.accentColor,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.accentColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getStatusColor(player.status),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStatusText(player.status),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.accentColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingSlot(GameTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
            child: Icon(Icons.person_add, color: Colors.grey, size: 24),
          ),

          const SizedBox(width: 12),

          Text(
            'Waiting for player...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLobbyActions(
    BuildContext context,
    MultiplayerState multiplayerState,
    GameTheme theme,
    MultiplayerGame game,
    AuthState authState,
  ) {
    final currentUserId = authState.userId;
    final currentPlayer = game.getPlayer(currentUserId ?? '');
    final isReady = currentPlayer?.status == PlayerStatus.ready;
    final isHost = currentPlayer?.rank == 0; // PlayerIndex 0 is host
    final allPlayersReady =
        game.players.isNotEmpty &&
        game.players.every((p) => p.status == PlayerStatus.ready);
    final canStartGame = isHost && allPlayersReady && game.players.length >= 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Show Start Game button for host when all players are ready
        if (canStartGame) ...[
          GradientButton(
            onPressed: multiplayerState.isLoading
                ? null
                : () {
                    context.read<MultiplayerCubit>().startGame();
                  },
            text: 'START GAME',
            primaryColor: Colors.green,
            secondaryColor: Colors.green.shade700,
            icon: Icons.play_arrow,
          ),
          const SizedBox(height: 12),
        ],

        // Show waiting message for non-host when all ready
        if (!isHost && allPlayersReady && game.players.length >= 2) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for host to start...',
                  style: TextStyle(fontSize: 14, color: Colors.green),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Row(
          children: [
            Expanded(
              child: GradientButton(
                onPressed: () {
                  context.read<MultiplayerCubit>().leaveGame();
                  context.pop();
                },
                text: 'LEAVE',
                primaryColor: Colors.red,
                secondaryColor: Colors.red.withValues(alpha: 0.8),
                icon: Icons.exit_to_app,
                outlined: true,
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: GradientButton(
                onPressed: multiplayerState.isLoading || isReady
                    ? null
                    : () {
                        context.read<MultiplayerCubit>().markPlayerReady();
                      },
                text: isReady ? 'READY!' : 'READY',
                primaryColor: isReady ? Colors.green : theme.accentColor,
                secondaryColor: isReady
                    ? Colors.green.withValues(alpha: 0.8)
                    : theme.foodColor,
                icon: isReady ? Icons.check : Icons.check_circle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showCreateGameDialog(
    BuildContext context,
    GameTheme theme,
    bool isPrivate,
  ) {
    MultiplayerGameMode selectedMode = MultiplayerGameMode.classic;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: theme.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Create ${isPrivate ? 'Private' : 'Public'} Room',
            style: TextStyle(
              color: theme.accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose game mode:',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.8),
                ),
              ),

              const SizedBox(height: 16),

              ...MultiplayerGameMode.values.map(
                (mode) => Padding(
                  // Color + border were previously on an outer DecoratedBox,
                  // which hides ListTile's own ink ripple. Moved to
                  // tileColor/shape so ripples render correctly and Flutter
                  // stops warning about the Material-ancestor mismatch.
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    tileColor: selectedMode == mode
                        ? theme.accentColor.withValues(alpha: 0.1)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: selectedMode == mode
                          ? BorderSide(
                              color:
                                  theme.accentColor.withValues(alpha: 0.3),
                            )
                          : BorderSide.none,
                    ),
                    leading: Icon(
                      selectedMode == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: theme.accentColor,
                    ),
                    title: Text(
                      '${mode.modeEmoji} ${mode.modeDisplayName}',
                      style: TextStyle(color: theme.accentColor),
                    ),
                    subtitle: Text(
                      _getGameModeDescription(mode),
                      style: TextStyle(
                        color: theme.accentColor.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        selectedMode = mode;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.7),
                ),
              ),
            ),
            GradientButton(
              onPressed: () {
                context.pop();
                context.read<MultiplayerCubit>().createGame(
                  mode: selectedMode,
                  isPrivate: isPrivate,
                );
              },
              text: 'CREATE',
              primaryColor: theme.accentColor,
              secondaryColor: theme.foodColor,
              width: 100,
              height: 40,
            ),
          ],
        ),
      ),
    );
  }

  String _getGameModeDescription(MultiplayerGameMode mode) {
    switch (mode) {
      case MultiplayerGameMode.classic:
        return 'Classic Cosmo Strike battle';
      case MultiplayerGameMode.speedRun:
        return 'Speed increases over time';
      case MultiplayerGameMode.survival:
        return 'Last ship standing wins';
      case MultiplayerGameMode.powerUpMadness:
        return 'Power-ups everywhere!';
    }
  }

  Color _getStatusColor(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.waiting:
        return Colors.orange;
      case PlayerStatus.ready:
        return Colors.green;
      case PlayerStatus.playing:
        return Colors.blue;
      case PlayerStatus.crashed:
        return Colors.red;
      case PlayerStatus.disconnected:
        return Colors.grey;
    }
  }

  String _getStatusText(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.waiting:
        return 'Waiting';
      case PlayerStatus.ready:
        return 'Ready';
      case PlayerStatus.playing:
        return 'Playing';
      case PlayerStatus.crashed:
        return 'Crashed';
      case PlayerStatus.disconnected:
        return 'Disconnected';
    }
  }
}
