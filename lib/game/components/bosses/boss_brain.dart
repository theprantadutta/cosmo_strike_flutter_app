import '../../cosmo_strike_game.dart';
import '../../levels/formation.dart';
import '../../levels/level_def.dart';
import '../boss.dart';
import 'boss_kits.dart';

/// How the boss moves while it isn't attacking.
enum BossMovement {
  /// Slow vertical sine inside the open corridor (the classic weave).
  weave,

  /// Eases back to the vertical center and holds.
  station,

  /// Fast full-span vertical sweeps (late-phase pressure).
  sweepVertical,
}

/// One phase of a boss fight, active while hp/maxHp > [untilHpFrac].
/// Crossing into a new phase clears in-flight boss bullets, flashes,
/// hit-stops, and fires the phase's pods/add-wave (see Boss._enterPhase).
class BossPhase {
  const BossPhase({
    required this.untilHpFrac,
    required this.attacks,
    this.intervalScale = 1,
    this.movement = BossMovement.weave,
    this.podCount = 0,
    this.invulnerableWhilePods = false,
    this.addWave,
  });

  final double untilHpFrac;

  /// Cycled IN ORDER — scripted rhythm, not a slot machine.
  final List<BossAttack> attacks;

  /// Multiplier on BossDef.attackInterval for this phase.
  final double intervalScale;
  final BossMovement movement;

  /// Shootable pods spawned on phase entry (shield generators/escorts).
  final int podCount;

  /// While true and pods remain, the boss core takes zero damage.
  final bool invulnerableWhilePods;

  /// Escort/larva formation spawned on phase entry.
  final FormationSpec? addWave;
}

/// One boss attack. EVERY attack telegraphs (0.8–1.2 s windup: hull tint
/// pulse + sfx + optional markers) and aim is captured at telegraph
/// START — the player always dodges a known trajectory.
///
/// Attack instances are const and shared; transient state (captured aim,
/// exec clock) lives on the [Boss] scratchpad.
abstract class BossAttack {
  const BossAttack();

  double get telegraphSeconds => 1.0;

  /// Sustained attacks keep control after execute via [updateExecution].
  bool get sustained => false;

  /// Sustained attacks that drive the boss's position themselves.
  bool get controlsMovement => false;

  /// Telegraph start: capture aim into the boss scratchpad, spawn markers.
  void telegraph(Boss boss, CosmoStrikeGame game) {}

  /// Windup over: fire (using the CAPTURED aim).
  void execute(Boss boss, CosmoStrikeGame game);

  /// Sustained tick; return true while still busy.
  bool updateExecution(Boss boss, CosmoStrikeGame game, double dt) => false;
}

/// Per-type fight kits. Pure data + small attack strategies — see
/// boss_kits.dart for the five kits.
abstract class BossBrain {
  const BossBrain();

  List<BossPhase> get phases;

  static BossBrain forType(BossType type) => switch (type) {
        BossType.dreadnought => const DreadnoughtBrain(),
        BossType.warMachine => const WarMachineBrain(),
        BossType.hiveQueen => const HiveQueenBrain(),
        BossType.leviathan => const LeviathanBrain(),
        BossType.mothership => const MothershipBrain(),
      };
}
