import 'dart:async';

import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';

import '../../game/cosmo_strike_game.dart';
import '../../models/level_run_result.dart';
import '../../services/audio_service.dart';
import '../../services/haptic_service.dart';
import '../../services/storage_service.dart';
import 'challenge_panel.dart';
import 'run_stat_tiles.dart';

/// The pause overlay over the blurred, frozen battlefield (82% scrim +
/// blur 10). Left = mono run meta, the "Paused" headline, a 3×2 run stat
/// grid, SFX / MUSIC / HAPTICS toggle chips, the opt-in "+1 life" ad perk,
/// and RESUME · RESTART · QUIT; right = today's daily directives with
/// inline claims.
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
    final cs = context.cs;
    final t = cs.type;
    final game = widget.game;
    final partial = game.buildPartialResult();
    final firstClears = widget.outcomes.values.where((o) => o.firstClear).length;
    // Mirrors the _submitRun payout formula — an estimate because the
    // run isn't over yet.
    final coinsEst =
        10 +
        partial.enemiesKilled +
        partial.bossesKilled * 50 +
        partial.levelsCleared * 25 +
        firstClears * 75;
    final level = game.levelNotifier.value.toString().padLeft(2, '0');
    final meta = '${game.mode.name} · L$level — ${game.levelNameNotifier.value}';

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CsFitColumn(
            children: [
              CsLabel(meta),
              SizedBox(height: cs(6)),
              Text('Paused', maxLines: 1, style: t.display(60, em: -0.04, height: 1)),
              SizedBox(height: cs(18)),
              CsStatGrid(
                columns: 3,
                stats: [
                  CsStat('${partial.score}', 'Score'),
                  CsStat('L${partial.stageReached}·W${partial.waveReached}', 'Level · Wave'),
                  CsStat('${partial.enemiesKilled}', 'Kills'),
                  CsStat('×${partial.maxCombo}', 'Max combo'),
                  CsStat('${partial.grazeCount}', 'Grazes'),
                  CsStat('$coinsEst', 'Coins (est.)', color: CsColors.gold),
                ],
              ),
              SizedBox(height: cs(18)),
              Wrap(
                spacing: cs(10),
                runSpacing: cs(10),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _QuickToggles(),
                  // Opt-in rewarded perk: watch an ad → +1 life. Only
                  // rendered when an ad is loaded and the daily cap isn't
                  // hit, so it never shows as a dead button (and never for
                  // Pro users, who can't watch ads).
                  if (widget.lifeAdReady)
                    CsButton.secondary(
                      label: 'Watch ad · +1 life',
                      icon: Symbols.favorite_rounded,
                      size: CsButtonSize.small,
                      onPressed: widget.onWatchAdForLife,
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: cs(16)),
        OverlayActions(
          children: [
            CsButton.primary(
              label: 'Resume',
              icon: Symbols.play_arrow_rounded,
              onPressed: widget.onResume,
            ),
            CsButton.secondary(
              label: _confirmRestart ? 'Confirm?' : 'Restart',
              onPressed: _tapRestart,
            ),
            CsButton.text(label: 'Quit', onPressed: widget.onQuit),
          ],
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: CsLabel('Daily directives')),
            SizedBox(width: cs(10)),
            const ChallengeClaimAllButton(),
          ],
        ),
        SizedBox(height: cs(8)),
        const Expanded(
          child: SingleChildScrollView(
            physics: ClampingScrollPhysics(),
            child: ChallengePanel(showClaimAll: false),
          ),
        ),
      ],
    );

    return GameplayOverlayFrame(
      blur: true,
      child: OverlaySplit(left: left, right: right),
    );
  }
}

/// SFX / MUSIC / HAPTICS quick toggle chips (off = 40% ink, 10% border).
/// Mirrors the settings screen's persistence exactly.
class _QuickToggles extends StatefulWidget {
  const _QuickToggles();

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
    final gap = context.cs(10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CsToggleChip(
          icon: Symbols.volume_up_rounded,
          offIcon: Symbols.volume_off_rounded,
          label: 'SFX',
          value: _sound,
          onChanged: (_) => _toggleSound(),
        ),
        SizedBox(width: gap),
        CsToggleChip(
          icon: Symbols.music_note_rounded,
          offIcon: Symbols.music_off_rounded,
          label: 'Music',
          value: _music,
          onChanged: (_) => _toggleMusic(),
        ),
        SizedBox(width: gap),
        CsToggleChip(
          icon: Symbols.vibration_rounded,
          label: 'Haptics',
          value: _haptics,
          onChanged: (_) => _toggleHaptics(),
        ),
      ],
    );
  }
}
