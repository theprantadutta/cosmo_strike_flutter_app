import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:material_ui/material_ui.dart';

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
    this.runLabel,
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

  /// The run's name ("Daily Run" / "Sector Cup" / mode) for the header;
  /// null falls back to the mode name.
  final String? runLabel;

  final VoidCallback onResume;

  /// Restart / quit: the host confirms before abandoning the run.
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
  /// Entrance: each section fades up 8 px over 260 ms, 30 ms apart; the last
  /// (slot 4) lands at 380 ms, so the whole menu is in under 400 ms and the
  /// player can resume immediately. CsFadeUp plays once per mount (each
  /// pause) and never replays on rebuilds; reduce motion = a plain 120 ms
  /// fade.
  static const Duration _enter = Duration(milliseconds: 260);
  static const Duration _step = Duration(milliseconds: 30);

  Widget _up(int slot, Widget child) =>
      CsFadeUp(delay: _step * slot, duration: _enter, distance: 8, child: child);

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
    final meta = '${widget.runLabel ?? game.mode.name} · L$level — ${game.levelNameNotifier.value}';

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CsFitColumn(
            children: [
              _up(0, CsLabel(meta)),
              SizedBox(height: cs(6)),
              _up(1, Text('Paused', maxLines: 1, style: t.display(60, em: -0.04, height: 1))),
              SizedBox(height: cs(18)),
              _up(2, CsStatGrid(
                columns: 3,
                stats: [
                  CsStat('${partial.score}', 'Score'),
                  CsStat('L${partial.stageReached}·W${partial.waveReached}', 'Level · Wave'),
                  CsStat('${partial.enemiesKilled}', 'Kills'),
                  CsStat('×${partial.maxCombo}', 'Max combo'),
                  CsStat('${partial.grazeCount}', 'Grazes'),
                  CsStat('$coinsEst', 'Credits (est.)', color: CsColors.gold),
                ],
              )),
              SizedBox(height: cs(18)),
              _up(3, Wrap(
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
                      label: 'Watch ad · +1 ship',
                      icon: Symbols.favorite_rounded,
                      size: CsButtonSize.small,
                      onPressed: widget.onWatchAdForLife,
                    ),
                ],
              )),
            ],
          ),
        ),
        SizedBox(height: cs(16)),
        _up(4, OverlayActions(
          children: [
            CsButton.primary(
              label: 'Resume',
              icon: Symbols.play_arrow_rounded,
              onPressed: widget.onResume,
            ),
            CsButton.secondary(
              label: 'Restart',
              onPressed: widget.onRestart,
            ),
            CsButton.text(label: 'Quit', onPressed: widget.onQuit),
          ],
        )),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _up(1, Row(
          children: [
            const Expanded(child: CsLabel('Daily Directives')),
            SizedBox(width: cs(10)),
            const ChallengeClaimAllButton(),
          ],
        )),
        SizedBox(height: cs(8)),
        Expanded(
          child: _up(
            2,
            const ScrollEdgeFade(
              child: SingleChildScrollView(
                physics: ClampingScrollPhysics(),
                child: ChallengePanel(showClaimAll: false),
              ),
            ),
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

/// SFX / MUSIC / HAPTICS quick toggles (on = white pill, off = outline +
/// slashed glyph).
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
    // Confirm-by-feel: a single thud instantly proves it works (CsHaptic
    // goes through HapticService, which was just switched on above).
    if (_haptics) CsHaptic.medium.play();
  }

  @override
  Widget build(BuildContext context) {
    final gap = context.cs(10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StateToggle(
          icon: Symbols.volume_up_rounded,
          offIcon: Symbols.volume_off_rounded,
          label: 'SFX',
          value: _sound,
          onTap: _toggleSound,
        ),
        SizedBox(width: gap),
        _StateToggle(
          icon: Symbols.music_note_rounded,
          offIcon: Symbols.music_off_rounded,
          label: 'Music',
          value: _music,
          onTap: _toggleMusic,
        ),
        SizedBox(width: gap),
        _StateToggle(
          icon: Symbols.vibration_rounded,
          offIcon: Symbols.mobile_off_rounded,
          label: 'Haptics',
          value: _haptics,
          onTap: _toggleHaptics,
        ),
      ],
    );
  }
}

/// A pause quick-toggle whose state reads at a glance: ON = filled white
/// pill (the design system's selected style) with dark glyph + label; OFF =
/// outline, dim slashed glyph and "<LABEL> OFF". Local wrapper: the shared
/// CsToggleChip's on/off differ only by a faint ink shift, which read as
/// identical on device.
class _StateToggle extends StatelessWidget {
  const _StateToggle({
    required this.icon,
    required this.offIcon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final IconData offIcon;
  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final c = value ? CsColors.onLight : CsColors.ink45;
    return Semantics(
      toggled: value,
      label: label,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: CsPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: CsMotion.base,
          curve: CsMotion.standard,
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: cs(16)),
          decoration: ShapeDecoration(
            color: value ? CsColors.ink : Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(color: value ? CsColors.ink : CsColors.lineStrong),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(value ? icon : offIcon, size: cs(18), color: c),
              SizedBox(width: cs(8)),
              Text(
                value ? label.toUpperCase() : '${label.toUpperCase()} OFF',
                style: cs.type.mono(11, color: c, em: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
