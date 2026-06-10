import '../components/power_up.dart' show PowerUpKind;
import 'formation.dart';

/// Edge-warning kinds a script can author directly (the ambushRear
/// formation telegraphs itself automatically).
enum ScriptTelegraphKind { edgeLeft, edgeRight }

/// One step of a level's choreographed timeline.
///
/// Timing is RELATIVE: [delay] counts from the moment the previous event
/// fired (and, for barrier events, from the moment the field cleared).
/// That makes intensity curves trivial to author — a breather is simply
/// a bigger delay on the next event.
sealed class LevelEvent {
  const LevelEvent(this.delay, {this.waitForFieldClear = false});

  /// Seconds after the previous event fired.
  final double delay;

  /// Hold this event (and the clock) until no enemy is alive.
  final bool waitForFieldClear;
}

/// Spawn a formation. [countsAsSection] advances the HUD wave counter
/// (and therefore LevelRunResult.waveReached — keep it on the events
/// that BEGIN a new beat of the level).
class FormationEvent extends LevelEvent {
  const FormationEvent(
    super.delay,
    this.spec, {
    this.countsAsSection = false,
    super.waitForFieldClear,
  });

  final FormationSpec spec;
  final bool countsAsSection;
}

/// A guaranteed orb scrolling in from the right at [y01].
class DropEvent extends LevelEvent {
  const DropEvent(super.delay, this.kind, {this.y01 = 0.5});

  final PowerUpKind kind;
  final double y01;
}

/// A timed set-piece window: HUD banner + optional mine rain. Corridor
/// squeezes/scroll changes are authored in the level's TerrainProfile to
/// line up with this window.
class SetPieceEvent extends LevelEvent {
  const SetPieceEvent(
    super.delay, {
    this.duration = 10,
    this.mineRainPerSecond = 0,
    this.banner,
    super.waitForFieldClear,
  });

  final double duration;
  final double mineRainPerSecond;
  final String? banner;
}

/// A scripted edge warning (incoming threat callout).
class TelegraphEvent extends LevelEvent {
  const TelegraphEvent(super.delay, this.kind, {this.y01 = 0.5});

  final ScriptTelegraphKind kind;
  final double y01;
}

/// The level's boss. Always waits for the field to clear first.
class BossEvent extends LevelEvent {
  const BossEvent({double delay = 1.2}) : super(delay, waitForFieldClear: true);
}

/// A level's full choreography: ordered events ending in a [BossEvent].
class LevelScript {
  const LevelScript(this.events);

  final List<LevelEvent> events;

  /// How many HUD sections (waves) the script declares.
  int get sectionCount => events
      .whereType<FormationEvent>()
      .where((e) => e.countsAsSection)
      .length;
}
