import '../../levels/formation.dart';
import '../../levels/level_def.dart';
import 'boss_attacks.dart';
import 'boss_brain.dart';

/// The five boss fight kits. Each is a 3-phase scripted rhythm with a
/// signature mechanic — no two bosses share a brain anymore. Numbers
/// (hp, bullet speed, cadence) still ramp per level via BossDef.

/// DREADNOUGHT (Asteroid Belt): a gun platform. Rakes the field row by
/// row, then learns the charge beam — read the band, leave the band.
class DreadnoughtBrain extends BossBrain {
  const DreadnoughtBrain();

  @override
  List<BossPhase> get phases => const [
        BossPhase(
          untilHpFrac: 0.66,
          attacks: [TurretSweepAttack(), AimedBurstAttack()],
        ),
        BossPhase(
          untilHpFrac: 0.33,
          intervalScale: 0.9,
          attacks: [
            BeamRowAttack(),
            TurretSweepAttack(),
            AimedBurstAttack(),
          ],
        ),
        BossPhase(
          untilHpFrac: 0,
          intervalScale: 0.72,
          movement: BossMovement.sweepVertical,
          attacks: [
            BeamRowAttack(),
            AimedBurstAttack(),
            TurretSweepAttack(rows: 8),
          ],
        ),
      ];
}

/// WAR MACHINE (Neon Ruins): artillery. Mortars arc onto marked ground; at
/// half health it raises shield-generator pods you break under fire, and the
/// finale brings out the twin crossfire beams. Every attack telegraphs.
class WarMachineBrain extends BossBrain {
  const WarMachineBrain();

  @override
  List<BossPhase> get phases => const [
        BossPhase(
          untilHpFrac: 0.66,
          attacks: [MortarLobAttack(count: 3), AimedBurstAttack()],
        ),
        // Pods up — but the boss keeps fighting: mortars + an aimed scatter
        // cone you must dodge WHILE breaking the shield generators.
        BossPhase(
          untilHpFrac: 0.33,
          intervalScale: 0.9,
          podCount: 2,
          invulnerableWhilePods: true,
          attacks: [MortarLobAttack(count: 4), AimedFanAttack()],
        ),
        // Escalation: twin crossfire beams (hold the centre lane) layered
        // over heavier mortar barrages and the cone.
        BossPhase(
          untilHpFrac: 0,
          intervalScale: 0.75,
          attacks: [
            MortarLobAttack(count: 5),
            CrossfireBeamsAttack(),
            AimedFanAttack(),
          ],
        ),
      ];
}

/// HIVE QUEEN (Hive Nebula): organic. Pulse rings + larva escorts, then
/// the telegraphed burrow-dash that rakes your row.
class HiveQueenBrain extends BossBrain {
  const HiveQueenBrain();

  static const _larva = FormationSpec(
    shape: FormationShape.serpentine,
    type: EnemyType.wasp,
    count: 4,
    y01: 0.35,
    spacing: 44,
    wipeBonus: 150,
  );

  @override
  List<BossPhase> get phases => const [
        BossPhase(
          untilHpFrac: 0.66,
          attacks: [PulseRingAttack(), AimedBurstAttack()],
        ),
        BossPhase(
          untilHpFrac: 0.33,
          intervalScale: 0.9,
          addWave: _larva,
          attacks: [DashSweepAttack(), PulseRingAttack()],
        ),
        BossPhase(
          untilHpFrac: 0,
          intervalScale: 0.78,
          addWave: _larva,
          attacks: [
            DashSweepAttack(),
            PulseRingAttack(count: 16),
            AimedBurstAttack(),
          ],
        ),
      ];
}

/// LEVIATHAN (Crystal Expanse): the wall. Its signature curtain keeps
/// the safe gap telegraphed green; later phases narrow it, add dive
/// sweeps, and finally double the curtain.
class LeviathanBrain extends BossBrain {
  const LeviathanBrain();

  @override
  List<BossPhase> get phases => const [
        BossPhase(
          untilHpFrac: 0.66,
          attacks: [BulletWallAttack(gapHalf: 60), AimedBurstAttack()],
        ),
        BossPhase(
          untilHpFrac: 0.33,
          intervalScale: 0.9,
          movement: BossMovement.sweepVertical,
          attacks: [BulletWallAttack(gapHalf: 50), DashSweepAttack()],
        ),
        BossPhase(
          untilHpFrac: 0,
          intervalScale: 0.8,
          movement: BossMovement.sweepVertical,
          attacks: [
            BulletWallAttack(gapHalf: 46, walls: 2),
            AimedBurstAttack(),
            DashSweepAttack(),
          ],
        ),
      ];
}

/// MOTHERSHIP (the finale): starts untouchable behind four escort pods;
/// expose the core, survive the scripts, then outrun the rotating-gap
/// desperation radials.
class MothershipBrain extends BossBrain {
  const MothershipBrain();

  static const _drones = FormationSpec(
    shape: FormationShape.vWedge,
    type: EnemyType.drone,
    count: 3,
    y01: 0.5,
    spacing: 48,
    wipeBonus: 150,
  );

  @override
  List<BossPhase> get phases => const [
        // Pods up, but already an active fight: aimed bursts + a telegraphed
        // scatter cone while you break the four escort pods.
        BossPhase(
          untilHpFrac: 0.66,
          podCount: 4,
          invulnerableWhilePods: true,
          attacks: [AimedBurstAttack(), AimedFanAttack()],
        ),
        // Core exposed: the flagship's rotating spiral barrage arrives,
        // mixed with the cone and arcing mortars; drone escorts pressure.
        BossPhase(
          untilHpFrac: 0.33,
          intervalScale: 0.88,
          addWave: _drones,
          attacks: [
            AimedFanAttack(),
            SpiralBarrageAttack(),
            MortarLobAttack(count: 3),
          ],
        ),
        // Desperation finale: rotating-gap radials and the spiral together —
        // track the moving safe wedge and weave the spinning arms.
        BossPhase(
          untilHpFrac: 0,
          intervalScale: 0.72,
          addWave: _drones,
          attacks: [
            RotatingGapRadialAttack(),
            SpiralBarrageAttack(),
            AimedBurstAttack(),
          ],
        ),
      ];
}
