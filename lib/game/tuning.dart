/// Every gameplay-feel number introduced by the "thrill" pass lives here so
/// balancing is a one-file job. Values are per-level curves (1-based level)
/// or flat constants.
class GameTuning {
  GameTuning._();

  static double _lerpLevel(int level, double l1, double l12) {
    final t = ((level - 1) / 11).clamp(0.0, 1.0);
    return l1 + (l12 - l1) * t;
  }

  // ---- Enemy fire ----

  /// Chance a normally straight-firing enemy aims its shot at the player.
  static double aimedChance(int level) => _lerpLevel(level, 0.12, 0.6);

  /// Enemy bullet speed multiplier (base: 220 aimed / 240 straight).
  static double enemyBulletSpeed(int level) => _lerpLevel(level, 1.0, 1.35);

  // ---- Intensity director ----

  /// Clean flying (no landed hit) for this long starts raising pressure.
  static const double calmBeforeRamp = 12.0;

  /// Seconds of clean flying to go from neutral to max intensity.
  static const double rampSeconds = 20.0;

  /// Intensity bounds: multiplies enemy fire rate, aimed chance and
  /// bullet speed (speed only gets half the swing).
  static const double minIntensity = 0.8;
  static const double maxIntensity = 1.25;

  /// Each landed hit knocks intensity down by this much.
  static const double hitRelief = 0.12;

  // ---- Idle punish ----

  /// Moving less than this (px) over [idleWindow] seconds counts as idle.
  static const double idleDistance = 40.0;
  static const double idleWindow = 4.0;

  /// While idle, a sniper volley of [idleVolleyShots] aimed shots fires
  /// from off-screen right every [idleVolleyEvery] seconds.
  static const double idleVolleyEvery = 3.0;
  static const int idleVolleyShots = 3;

  // ---- Power-up drops ----

  /// Orbs bob vertically at this speed (px/s) so they must be chased.
  static const double dropDriftY = 55.0;

  // ---- Graze / Overdrive ----

  /// Grazes needed to fill the Overdrive meter.
  static const int grazesForOverdrive = 12;

  /// Extra Overdrive charge for a formation wipe (0..1 of the meter).
  static const double wipeOverdriveCharge = 0.15;

  /// Base graze points (multiplied by the combo multiplier).
  static const int grazePoints = 15;

  /// A graze keeps a live chain going for this many extra seconds.
  static const double grazeChainExtend = 0.6;

  static const double overdriveSeconds = 5.0;
  static const double overdriveScoreMult = 2.0;
  static const double overdriveEnemyTimeScale = 0.8;
  static const double overdriveFireCooldown = 0.07;
  static const int overdriveDamage = 3;

  /// Enemy bullets within this radius of the ship are vaporised during
  /// Overdrive.
  static const double overdriveShieldRadius = 70.0;

  // ---- Juice ----

  static const double bossWarningSeconds = 2.2;
  static const double bossKillSlowMoSeconds = 0.9;
  static const double bossKillSlowMoScale = 0.25;

  /// Chain lengths that trigger a streak callout.
  static const Map<int, String> streakCallouts = {
    10: 'RAMPAGE',
    20: 'UNSTOPPABLE',
    30: 'GODLIKE',
    50: 'LEGENDARY',
  };
}
