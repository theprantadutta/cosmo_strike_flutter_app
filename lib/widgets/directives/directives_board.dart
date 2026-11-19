import 'package:material_ui/material_ui.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/directive_card.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/weekly_ops_strip.dart';
import 'package:cosmo_strike_flutter_app/widgets/list_entrance.dart';

/// The right column of the Daily Directives tab: one [DirectiveCard] per
/// directive sharing the column's height equally (Expanded), then the
/// optional compact strips (all-clear bonus, Weekly Ops) underneath.
///
/// Never scrolls and never overflows: it needs a bounded height, and drops
/// strips (Weekly Ops first, then the bonus) whenever keeping them would
/// squeeze the cards below [DirectiveCard.comfortableHeight]. The cards compact
/// themselves on short phones and open up on tablets.
class DirectivesBoard extends StatelessWidget {
  const DirectivesBoard({
    super.key,
    required this.challenges,
    required this.onClaim,
    this.onFly,
    this.bonusStrip,
    this.weeklyStrip,
    this.entrance,
  });

  final List<DailyChallenge> challenges;
  final ValueChanged<DailyChallenge> onClaim;

  /// Starts a sortie from an in-progress card.
  final VoidCallback? onFly;

  /// Shown when every directive is complete (higher priority than Weekly Ops).
  final Widget? bonusStrip;

  /// Weekly Ops progress / sign-in CTA.
  final Widget? weeklyStrip;

  /// The screen's first-open stagger; cards get a fresh CsFadeUp without it.
  final ListEntrance? entrance;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final gap = cs(8);
    return LayoutBuilder(
      builder: (context, box) {
        final n = challenges.length;
        final cardsMin = n * DirectiveCard.comfortableHeight(context) + (n > 0 ? (n - 1) * gap : 0);
        final stripCost = directivesStripHeight(context) + gap;
        var room = box.maxHeight - cardsMin;

        final strips = <(String, Widget)>[];
        for (final (id, strip) in [('bonus', bonusStrip), ('weekly', weeklyStrip)]) {
          if (strip == null || room < stripCost) continue;
          strips.add((id, strip));
          room -= stripCost;
        }

        Widget wrap(int i, Widget child, Key key) {
          final e = entrance;
          if (e != null) return e.wrap(i, child, key: key);
          return CsFadeUp(key: key, index: i, child: child);
        }

        final settled = entrance?.settled ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, ch) in challenges.indexed) ...[
              if (i > 0) SizedBox(height: gap),
              Expanded(
                child: wrap(
                  i,
                  DirectiveCard(
                    challenge: ch,
                    fillOnMount: !settled,
                    onFly: onFly,
                    onClaim: () => onClaim(ch),
                  ),
                  ValueKey(ch.id),
                ),
              ),
            ],
            for (final (i, (id, strip)) in strips.indexed) ...[
              SizedBox(height: gap),
              wrap(n + i, strip, ValueKey('strip_$id')),
            ],
          ],
        );
      },
    );
  }
}
