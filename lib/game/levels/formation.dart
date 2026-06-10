import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/enemy.dart' show EnemyPattern;
import '../components/power_up.dart' show PowerUpKind;
import 'level_def.dart' show EnemyType;

/// The choreographed formation shapes. `stream` is the un-managed shape:
/// members fly on their own patterns (it replicates the old random wave
/// entries and is the mechanical-conversion target); every other shape
/// is positioned as a unit by the Formation controller, so the group
/// reads as ONE composed move the player can learn.
enum FormationShape {
  /// Staggered loose stream — members self-pilot (legacy wave feel).
  stream,

  /// V wedge opening backwards, leader at the tip.
  vWedge,

  /// Follow-the-leader chain weaving along a sine path.
  snakeChain,

  /// Two columns converging from the top and bottom edges.
  pincer,

  /// A vertical wall advancing with one ship-sized gap to thread.
  wallWithGap,

  /// Ships drop in from the top edge, settle into lanes, then advance.
  columnDive,

  /// AMBUSH: enters from the LEFT edge behind the player (telegraphed).
  ambushRear,

  /// A rotating ring advancing across the field.
  ringSpinner,

  /// A tank escorted by a diamond of guards.
  escortConvoy,
}

/// Authoring data for one formation. Pure const data — levels are lists
/// of these on a timeline.
class FormationSpec {
  const FormationSpec({
    required this.shape,
    required this.type,
    this.secondaryType,
    required this.count,
    this.y01 = 0.5,
    this.spacing = 56,
    this.speedScale = 1,
    this.pattern,
    this.spawnInterval = 0.55,
    this.ySpread01 = 0.4,
    this.gap01,
    this.wipeWindow = 4.0,
    this.wipeBonus = 250,
    this.wipeDrop = PowerUpKind.weapon,
    this.mountCeiling = false,
  });

  /// Legacy-feel loose stream (the mechanical conversion of old waves).
  const FormationSpec.stream(
    this.type, {
    required this.count,
    double every = 0.55,
    this.pattern,
    this.y01 = 0.5,
    this.ySpread01 = 0.4,
    this.speedScale = 1,
    this.wipeBonus = 250,
    this.wipeDrop = PowerUpKind.weapon,
    this.mountCeiling = false,
  })  : shape = FormationShape.stream,
        secondaryType = null,
        spacing = 56,
        spawnInterval = every,
        gap01 = null,
        wipeWindow = 4.0;

  final FormationShape shape;

  /// The body of the formation.
  final EnemyType type;

  /// escortConvoy: the escorted tank (defaults to beetle).
  final EnemyType? secondaryType;
  final int count;

  /// Vertical center as a fraction of the open playfield.
  final double y01;
  final double spacing;
  final double speedScale;

  /// stream only: per-ship movement pattern override.
  final EnemyPattern? pattern;

  /// stream only: stagger between member spawns.
  final double spawnInterval;

  /// stream only: random vertical half-band around [y01].
  final double ySpread01;

  /// wallWithGap: gap center as a playfield fraction (null = random).
  final double? gap01;

  /// First-kill → last-kill window for the wipe bonus (streams extend
  /// this by their spawn span).
  final double wipeWindow;

  /// Points for killing the WHOLE formation inside the window with no
  /// escapes (0 disables). A wipe also drops [wipeDrop].
  final int wipeBonus;
  final PowerUpKind wipeDrop;

  /// Terrain-mounted types (turrets): hang from the ceiling band.
  final bool mountCeiling;

  /// Managed shapes are positioned by the Formation controller.
  bool get managed => shape != FormationShape.stream;

  /// Vertically mirrored copy (Onslaught echo).
  FormationSpec mirrored() => FormationSpec(
        shape: shape,
        type: type,
        secondaryType: secondaryType,
        count: count,
        y01: 1 - y01,
        spacing: spacing,
        speedScale: speedScale,
        pattern: pattern,
        spawnInterval: spawnInterval,
        ySpread01: ySpread01,
        gap01: gap01 == null ? null : 1 - gap01!,
        wipeWindow: wipeWindow,
        wipeBonus: wipeBonus,
        wipeDrop: wipeDrop,
        mountCeiling: mountCeiling,
      );
}

// ---- Pure slot math (unit-testable, no game dependencies) ----

/// vWedge: slot 0 is the tip; pairs trail behind above/below.
Vector2 vWedgeOffset(int i, double spacing) {
  if (i == 0) return Vector2.zero();
  final row = (i + 1) ~/ 2;
  final side = i.isOdd ? -1.0 : 1.0;
  return Vector2(row * spacing * 0.95, side * row * spacing * 0.62);
}

/// ringSpinner: slot position on a rotating ring.
Vector2 ringOffset(int i, int n, double t, double radius,
    {double omega = 1.6}) {
  final a = (i / n) * math.pi * 2 + t * omega;
  return Vector2(math.cos(a) * radius, math.sin(a) * radius);
}

/// snakeChain: the leader's vertical path; follower i samples it
/// [i * delay] seconds in the past.
double snakeY(double t, double amp, {double freq = 2.4}) =>
    math.sin(t * freq) * amp;

/// escortConvoy: slot 0 = tank center; escorts diamond around it.
Vector2 convoyOffset(int i, double spacing) {
  if (i == 0) return Vector2.zero();
  final around = [
    Vector2(spacing, -spacing * 0.8),
    Vector2(spacing, spacing * 0.8),
    Vector2(-spacing * 0.7, -spacing * 0.8),
    Vector2(-spacing * 0.7, spacing * 0.8),
    Vector2(spacing * 1.8, 0),
    Vector2(-spacing * 1.4, 0),
  ];
  return around[(i - 1) % around.length] *
      (1 + (i - 1) ~/ around.length * 0.6);
}

/// wallWithGap: slot i's vertical fraction over the open playfield with
/// slots inside the gap window shoved to its edges.
double wallSlotY01(int i, int n, double gap01, double gapHalf01) {
  var y = n <= 1 ? 0.5 : i / (n - 1);
  final d = y - gap01;
  if (d.abs() < gapHalf01) {
    y = gap01 + (d.isNegative ? -gapHalf01 : gapHalf01);
  }
  return y.clamp(0.0, 1.0);
}

/// columnDive: eased descent progress for slot i at formation time t.
double diveProgress(double t, int i) {
  final p = ((t - i * 0.16) * 1.3).clamp(0.0, 1.0);
  return p * p * (3 - 2 * p); // smoothstep
}
