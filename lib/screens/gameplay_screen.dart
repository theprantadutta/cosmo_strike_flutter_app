import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../game/cosmo_palette.dart';
import '../game/cosmo_strike_game.dart';
import '../models/ship_coins.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../presentation/bloc/game/game_settings_cubit.dart';
import '../presentation/bloc/premium/battle_pass_cubit.dart';
import '../router/routes.dart';
import '../services/api_service.dart';
import '../ui/design.dart';
import '../utils/constants.dart';

/// Hosts the Flame shoot-'em-up. Flame is scoped to this screen only; the HUD,
/// pause / stage-clear / game-over overlays, and drag input live in Flutter on
/// top of the [GameWidget]. On game over the [GameResult] is exposed via
/// [onRunComplete] for the backend score/progression submission (see ApiService
/// wiring).
class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, this.onRunComplete});

  /// Invoked once per run with the final result (score submission hook).
  final void Function(GameResult result)? onRunComplete;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with WidgetsBindingObserver {
  late final CosmoStrikeGame _game;
  GameResult? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Full-screen play: hide the status / notification bar.
    Immersive.enterGame();
    _game = CosmoStrikeGame(
      onGameOver: _handleGameOver,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android drops immersiveSticky on resume — re-assert it.
      Immersive.enterGame();
    } else {
      _game.pauseGame();
    }
  }

  @override
  void dispose() {
    // Restore the menu chrome (status/nav bars) when leaving the game.
    Immersive.enterMenu();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleGameOver(GameResult result) {
    _lastResult = result;
    widget.onRunComplete?.call(result);
    if (!mounted) return;
    // Capture cubit references synchronously (no BuildContext across awaits).
    _submitRun(
      result,
      context.read<GameSettingsCubit>(),
      context.read<CoinsCubit>(),
      context.read<BattlePassCubit>(),
    );
  }

  /// Submit the run to the backend (leaderboards + server-side high score /
  /// achievements) and feed local progression (high score, coins, battle-pass
  /// XP). Fire-and-forget; failures are swallowed so the game-over overlay is
  /// never blocked.
  Future<void> _submitRun(
    GameResult r,
    GameSettingsCubit settings,
    CoinsCubit coins,
    BattlePassCubit battlePass,
  ) async {
    try {
      await settings.updateHighScore(r.score);
    } catch (_) {}

    unawaited(ApiService().submitGameRun(
      score: r.score,
      gameDurationSeconds: r.durationSeconds,
      enemiesKilled: r.enemiesKilled,
      stageReached: r.stageReached,
      waveReached: r.waveReached,
      bossesKilled: r.bossesKilled,
      idempotencyKey: const Uuid().v4(),
    ));

    try {
      await coins.earnCoins(
        CoinEarningSource.gameCompleted,
        customAmount: 10 + r.enemiesKilled + r.bossesKilled * 50,
      );
      battlePass.bufferXP(20 + r.score ~/ 100, source: 'game_completed');
      await battlePass.flushXP();
    } catch (_) {}
  }

  void _steer(Offset localPosition) {
    _game.steerTo(Vector2(localPosition.dx, localPosition.dy));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CosmoPalette.bgDeep,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => _steer(d.localPosition),
            onPanUpdate: (d) => _steer(d.localPosition),
            onTapDown: (_) {
              if (!_game.autoFire) _game.firePrimary();
            },
            child: GameWidget(game: _game),
          ),
          SafeArea(child: _Hud(game: _game)),
          ValueListenableBuilder<GamePhase>(
            valueListenable: _game.phaseNotifier,
            builder: (context, phase, _) {
              switch (phase) {
                case GamePhase.paused:
                  return _CenterOverlay(
                    title: 'PAUSED',
                    actions: [
                      _OverlayButton(label: 'RESUME', onTap: _game.resumeGame),
                      _OverlayButton(
                        label: 'QUIT',
                        onTap: () => context.go(AppRoutes.home),
                        secondary: true,
                      ),
                    ],
                  );
                case GamePhase.stageClear:
                  return _CenterOverlay(
                    title: 'STAGE ${_game.stage} CLEAR',
                    subtitle: 'Score ${_game.scoreNotifier.value}',
                    actions: [
                      _OverlayButton(
                        label: 'NEXT STAGE',
                        onTap: _game.advanceToNextStage,
                      ),
                    ],
                  );
                case GamePhase.gameOver:
                  final r = _lastResult;
                  return _CenterOverlay(
                    title: 'GAME OVER',
                    subtitle: r == null
                        ? null
                        : 'Score ${r.score}   •   Stage ${r.stageReached}\n'
                            '${r.enemiesKilled} destroyed   •   ${r.bossesKilled} bosses',
                    actions: [
                      _OverlayButton(
                        label: 'RETRY',
                        onTap: () => context.pushReplacement(AppRoutes.game),
                      ),
                      _OverlayButton(
                        label: 'HOME',
                        onTap: () => context.go(AppRoutes.home),
                        secondary: true,
                      ),
                    ],
                  );
                case GamePhase.ready:
                case GamePhase.playing:
                  return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// HUD skin for the glass frames — Command Cyan matches the cyan CosmoPalette
/// hull so the overlay chrome and the gameplay read as one system.
const GameTheme _hudSkin = GameTheme.classic;

class _Hud extends StatelessWidget {
  const _Hud({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GameTokens.space12),
      child: Column(
        children: [
          // Corner panels keep the central play field clear in landscape.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left: score + stage/wave.
              GlassPanel(
                theme: _hudSkin,
                radius: GameTokens.radiusMd,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: game.scoreNotifier,
                      builder: (_, score, _) => Text(
                        '$score',
                        style: const TextStyle(
                          color: CosmoPalette.highlight,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: game.stageNotifier,
                      builder: (_, stage, _) => ValueListenableBuilder<int>(
                        valueListenable: game.waveNotifier,
                        builder: (_, wave, _) => Text(
                          'S$stage · W$wave',
                          style: const TextStyle(
                            color: CosmoPalette.hull,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Top-right: lives + pause.
              GlassPanel(
                theme: _hudSkin,
                radius: GameTokens.radiusMd,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: game.livesNotifier,
                      builder: (_, lives, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          lives.clamp(0, 6),
                          (i) => const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child: Icon(Icons.flight,
                                size: 16, color: CosmoPalette.hull),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: game.pauseGame,
                      child: const Icon(Icons.pause_circle_outline,
                          color: CosmoPalette.hull, size: 26),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GameTokens.space8),
          // Slim energy bar under the score panel (left-aligned, not full width).
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: ValueListenableBuilder<double>(
                valueListenable: game.healthNotifier,
                builder: (_, hp, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hp,
                    minHeight: 6,
                    backgroundColor: CosmoPalette.bgHigh,
                    valueColor:
                        const AlwaysStoppedAnimation(CosmoPalette.energy),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Boss bar spans the bottom only while a boss is alive.
          ValueListenableBuilder<double>(
            valueListenable: game.bossHealthNotifier,
            builder: (_, boss, _) {
              if (boss < 0) return const SizedBox.shrink();
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: boss,
                  minHeight: 9,
                  backgroundColor: CosmoPalette.bgHigh,
                  valueColor:
                      const AlwaysStoppedAnimation(CosmoPalette.hostile),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CenterOverlay extends StatelessWidget {
  const _CenterOverlay({
    required this.title,
    required this.actions,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF05060F).withValues(alpha: 0.86),
      alignment: Alignment.center,
      child: GlassPanel(
        theme: _hudSkin,
        glow: true,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CosmoPalette.hull,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: CosmoPalette.highlight, fontSize: 15),
              ),
            ],
            const SizedBox(height: 24),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 240,
        child: NeonButton(
          label: label,
          onPressed: onTap,
          theme: _hudSkin,
          variant:
              secondary ? NeonButtonVariant.outline : NeonButtonVariant.solid,
        ),
      ),
    );
  }
}
