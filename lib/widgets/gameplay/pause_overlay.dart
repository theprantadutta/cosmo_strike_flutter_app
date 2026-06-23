import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/cosmo_palette.dart';
import '../../game/cosmo_strike_game.dart';
import '../../models/level_run_result.dart';
import '../../services/audio_service.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';
import '../../ui/design.dart';
import 'challenge_panel.dart';
import 'run_stat_tiles.dart';

/// The pause "mission console": a two-region landscape overlay on the
/// dimmed, frozen battlefield. Left = live run telemetry + audio/haptic
/// quick toggles + Resume/Restart/Quit; right = today's daily directives
/// with inline claims.
///
/// The Flame engine is frozen while this is up, so the one-shot
/// [CosmoStrikeGame.buildPartialResult] read in build is stable.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.game,
    required this.outcomes,
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
    this.lifeAdReady = false,
    required this.onWatchAdForLife,
  });

  final CosmoStrikeGame game;

  /// Incremental per-level-clear persist outcomes (for the coin estimate's
  /// first-clear bonus).
  final Map<int, StageClearOutcome> outcomes;

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  /// A rewarded ad is loaded AND the daily power-up cap isn't hit — gate the
  /// opt-in "+1 life" perk on this so the button never appears dead (and never
  /// for Pro users, who can't watch ads).
  final bool lifeAdReady;

  /// Watch a rewarded ad → grant +1 life (handled by the host screen).
  final VoidCallback onWatchAdForLife;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay> {
  /// Restart is destructive mid-run — first tap arms a 3s "CONFIRM?" beat.
  bool _confirmRestart = false;
  Timer? _confirmTimer;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  void _tapRestart() {
    if (_confirmRestart) {
      _confirmTimer?.cancel();
      widget.onRestart();
      return;
    }
    setState(() => _confirmRestart = true);
    _confirmTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _confirmRestart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final partial = game.buildPartialResult();
    final firstClears =
        widget.outcomes.values.where((o) => o.firstClear).length;
    // Mirrors the _submitRun payout formula — an estimate because the
    // run isn't over yet.
    final coinsEst = 10 +
        partial.enemiesKilled +
        partial.bossesKilled * 50 +
        partial.levelsCleared * 25 +
        firstClears * 75;

    return Stack(
      children: [
        // Dimmed frozen battlefield — also swallows stray taps.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: const Color(0xFF05060F).withValues(alpha: 0.72),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GameTokens.space24,
              vertical: GameTokens.space16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT — telemetry console. Never scrolls: natural size
                // inside a FittedBox so short phones scale it down.
                Expanded(
                  flex: 11,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 380,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PAUSED',
                                  style: TextStyle(
                                    color: CosmoPalette.hull,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                    shadows: [
                                      Shadow(
                                        color: CosmoPalette.hull
                                            .withValues(alpha: 0.7),
                                        blurRadius: 16,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${game.mode.name.toUpperCase()} · '
                                  'L${game.levelNotifier.value} — '
                                  '${game.levelNameNotifier.value.toUpperCase()}',
                                  style: TextStyle(
                                    color:
                                        CosmoPalette.hull.withValues(alpha: 0.75),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                                const SizedBox(height: GameTokens.space20),
                                Wrap(
                                  spacing: GameTokens.space16,
                                  runSpacing: GameTokens.space12,
                                  children: [
                                    RunStatTile(
                                      icon: Icons.score,
                                      value: '${partial.score}',
                                      label: 'SCORE',
                                    ),
                                    RunStatTile(
                                      icon: Icons.flag,
                                      value:
                                          'L${partial.stageReached} · W${partial.waveReached}',
                                      label: 'LEVEL · WAVE',
                                    ),
                                    RunStatTile(
                                      icon: Icons.gps_fixed,
                                      value: '${partial.enemiesKilled}',
                                      label: 'KILLS',
                                    ),
                                    RunStatTile(
                                      icon: Icons.bolt,
                                      value: '×${partial.maxCombo}',
                                      label: 'MAX COMBO',
                                    ),
                                    RunStatTile(
                                      icon: Icons.shield_moon,
                                      value: '${partial.grazeCount}',
                                      label: 'GRAZES',
                                    ),
                                    RunStatTile(
                                      icon: Icons.monetization_on,
                                      value: '$coinsEst',
                                      label: 'COINS (EST.)',
                                      accent: const Color(0xFFFFD37B),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: GameTokens.space20),
                                _QuickToggles(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Opt-in rewarded perk: watch an ad → +1 life. Only
                      // rendered when an ad is loaded and the daily cap isn't
                      // hit, so it never shows as a dead button (and never for
                      // Pro users, who can't watch ads).
                      if (widget.lifeAdReady) ...[
                        const SizedBox(height: GameTokens.space12),
                        SizedBox(
                          width: double.infinity,
                          child: OverlayActionButton(
                            label: '▶ WATCH AD  ·  +1 LIFE',
                            onTap: widget.onWatchAdForLife,
                            variant: NeonButtonVariant.outline,
                          ),
                        ),
                      ],
                      const SizedBox(height: GameTokens.space12),
                      Row(
                        children: [
                          Expanded(
                            child: OverlayActionButton(
                              label: 'RESUME',
                              onTap: widget.onResume,
                            ),
                          ),
                          const SizedBox(width: GameTokens.space8),
                          Expanded(
                            child: OverlayActionButton(
                              label: _confirmRestart ? 'CONFIRM?' : 'RESTART',
                              onTap: _tapRestart,
                              variant: NeonButtonVariant.outline,
                            ),
                          ),
                          const SizedBox(width: GameTokens.space8),
                          Expanded(
                            child: OverlayActionButton(
                              label: 'QUIT',
                              onTap: widget.onQuit,
                              variant: NeonButtonVariant.ghost,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GameTokens.space24),
                // RIGHT — daily directives (the only scrollable).
                Expanded(
                  flex: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader('DAILY DIRECTIVES'),
                      const SizedBox(height: GameTokens.space12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: ChallengePanel(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sound / music / haptics quick toggles — neon icon discs, lit when on,
/// dimmed when off. Mirrors the settings screen's persistence exactly.
class _QuickToggles extends StatefulWidget {
  @override
  State<_QuickToggles> createState() => _QuickTogglesState();
}

class _QuickTogglesState extends State<_QuickToggles> {
  late bool _sound = AudioService().isSoundEnabled;
  late bool _music = AudioService().isMusicEnabled;
  late bool _haptics = HapticService().isEnabled;

  Future<void> _toggleSound() async {
    setState(() => _sound = !_sound);
    await AudioService().setSoundEnabled(_sound);
    if (_sound) AudioService().playSound('button_click');
  }

  Future<void> _toggleMusic() async {
    setState(() => _music = !_music);
    AudioService().playSound('button_click');
    await AudioService().setMusicEnabled(_music);
  }

  Future<void> _toggleHaptics() async {
    setState(() => _haptics = !_haptics);
    HapticService().setEnabled(_haptics);
    await StorageService().setHapticsEnabled(_haptics);
    // Confirm-by-feel: a single thud instantly proves it works.
    if (_haptics) await HapticService().mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleDisc(
          icon: Icons.volume_up,
          enabled: _sound,
          onTap: _toggleSound,
        ),
        const SizedBox(width: GameTokens.space12),
        _ToggleDisc(
          icon: Icons.music_note,
          enabled: _music,
          onTap: _toggleMusic,
        ),
        const SizedBox(width: GameTokens.space12),
        _ToggleDisc(
          icon: Icons.vibration,
          enabled: _haptics,
          onTap: _toggleHaptics,
        ),
      ],
    );
  }
}

class _ToggleDisc extends StatelessWidget {
  const _ToggleDisc({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CosmoPalette.hull.withValues(alpha: enabled ? 0.14 : 0.06),
            boxShadow:
                enabled ? softGlow(CosmoPalette.hull, intensity: 0.6) : null,
          ),
          child: Icon(icon, size: 20, color: CosmoPalette.hull),
        ),
      ),
    );
  }
}
