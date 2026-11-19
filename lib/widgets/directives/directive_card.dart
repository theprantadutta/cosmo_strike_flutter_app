import 'package:material_ui/material_ui.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Where a directive stands, which decides the card's action.
enum DirectiveCardStatus {
  /// Still flying it: the card offers "Fly".
  inProgress,

  /// Target reached, reward not taken: the card offers "Claim".
  claimable,

  /// Reward taken: mint check, dimmed.
  claimed;

  static DirectiveCardStatus of(DailyChallenge c) {
    if (c.claimedReward) return DirectiveCardStatus.claimed;
    if (c.canClaim) return DirectiveCardStatus.claimable;
    return DirectiveCardStatus.inProgress;
  }
}

/// The type glyph for a directive, from its goal: score, hostiles, time in
/// the fight, sorties flown, mode runs (plus graze / boss wording, which the
/// backend may issue as score or kill directives).
IconData directiveIcon(DailyChallenge c) {
  final text = '${c.title} ${c.description}'.toLowerCase();
  if (text.contains('graze')) return Symbols.bolt_rounded;
  if (text.contains('boss')) return Symbols.skull_rounded;
  return switch (c.type) {
    ChallengeType.score => Symbols.scoreboard_rounded,
    ChallengeType.enemiesKilled => Symbols.crisis_alert_rounded,
    ChallengeType.survival => Symbols.timer_rounded,
    ChallengeType.gamesPlayed => Symbols.rocket_launch_rounded,
    ChallengeType.gameMode => Symbols.speed_rounded,
  };
}

/// One Daily Directive as a full card: type glyph, title + difficulty chip,
/// description, a big rolling "7 / 15", a thick progress line, the reward
/// (gold coin + CR, violet XP) and the state's action: Fly (in progress),
/// Claim (complete) or a mint "Claimed" (done, dimmed).
///
/// The card takes whatever height its parent gives it (the board hands each
/// card an equal share of the column) and decides its own density from that
/// height: on short phones the description and the stacked number/action
/// collapse; on tablets the glyph and number grow and the description gets
/// two lines. It never overflows a height >= [minHeight].
///
/// Motion: the bar fills from empty on first mount (CsProgressLine's 900 ms
/// lingering fill), the number rolls with CsOdometer when progress changes,
/// and the whole card pops once when the reward is claimed. Reduce motion is
/// honoured by those foundation widgets.
class DirectiveCard extends StatefulWidget {
  const DirectiveCard({
    super.key,
    required this.challenge,
    this.onFly,
    this.onClaim,
    this.fillOnMount = true,
  });

  final DailyChallenge challenge;

  /// Starts a sortie (in-progress cards). Null hides the button.
  final VoidCallback? onFly;

  /// Claims the reward (complete cards). Tapping the card also claims.
  final VoidCallback? onClaim;

  /// Fill the bar from 0 on first mount (off for cards that mount later,
  /// e.g. after the entrance has settled).
  final bool fillOnMount;

  /// The smallest height the card lays out in without overflowing, in
  /// logical px for this device (the board uses it to decide whether the
  /// Weekly Ops / bonus strips still fit).
  static double minHeight(BuildContext context) {
    final cs = context.cs;
    final s = cs.s;
    // padding + title row + reward line + bar + gaps, OR the Fly/Claim pill.
    final middle = (19.2 + 12.6) * s + 2 * cs(6) + _barHeight(cs);
    final pill = _pillHeight(cs);
    return 2 * cs(8) + (middle > pill ? middle : pill);
  }

  /// [minHeight] plus one line of description: the board keeps cards at
  /// least this tall before it spends height on the strips below them.
  static double comfortableHeight(BuildContext context) {
    final cs = context.cs;
    return minHeight(context) + 13 * 1.35 * cs.s + cs(4);
  }

  static double _barHeight(CsLayout cs) => cs(4).clamp(3.0, 6.0);
  static double _pillHeight(CsLayout cs) => cs(34).clamp(34.0, 44.0);

  @override
  State<DirectiveCard> createState() => _DirectiveCardState();
}

class _DirectiveCardState extends State<DirectiveCard> {
  /// False for the first frame when filling on mount, so the bar animates
  /// from empty to the real value.
  bool _filled = true;

  @override
  void initState() {
    super.initState();
    if (widget.fillOnMount) {
      _filled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _filled = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.challenge;
    final status = DirectiveCardStatus.of(c);
    final claimed = status == DirectiveCardStatus.claimed;
    final claimable = status == DirectiveCardStatus.claimable;

    final card = LayoutBuilder(
      builder: (context, box) => _CardBody(
        challenge: c,
        status: status,
        height: box.maxHeight,
        width: box.maxWidth,
        barValue: _filled ? c.progressPercentage : 0,
        onFly: widget.onFly,
        onClaim: widget.onClaim,
      ),
    );

    // The pop is the claim moment; the RewardToast brings the success
    // haptic, so none is added here.
    return CsPop(
      trigger: claimed,
      peak: 1.03,
      child: Semantics(
        container: true,
        button: claimable,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: claimable ? widget.onClaim : null,
          child: card,
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.challenge,
    required this.status,
    required this.height,
    required this.width,
    required this.barValue,
    required this.onFly,
    required this.onClaim,
  });

  final DailyChallenge challenge;
  final DirectiveCardStatus status;
  final double height;
  final double width;
  final double barValue;
  final VoidCallback? onFly;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final s = cs.s;
    final c = challenge;
    final claimed = status == DirectiveCardStatus.claimed;
    final claimable = status == DirectiveCardStatus.claimable;
    final done = claimed || claimable;

    // ── Density, from the height this card was given ──────────────────────
    final h = height.isFinite ? height : cs(150);
    final roomy = h >= cs(130);
    final padV = roomy ? cs(18) : (h >= cs(110) ? cs(14) : cs(8));
    final padH = roomy ? cs(22) : cs(16);
    final inner = h - 2 * padV;

    final barH = DirectiveCard._barHeight(cs);
    final pillH = DirectiveCard._pillHeight(cs);
    final titleSize = roomy ? 20.0 : 16.0;
    final titleH = titleSize * 1.2 * s;
    final rewardH = 12.6 * s;
    final descLineH = 13 * 1.35 * s;
    final gapS = cs(4);
    final gapM = cs(6);
    // Title row + reward + bar and their gaps (the minimum middle column).
    final base = titleH + gapM + rewardH + gapM + barH;
    final descLines = inner >= base + gapS + 2 * descLineH + cs(8)
        ? 2
        : (inner >= base + gapS + descLineH ? 1 : 0);

    // Number grows with the card (22 → 44 design px).
    final numberSize = (inner / s * 0.3).clamp(22.0, 44.0);
    final numberH = numberSize * s;
    // Stack the number over the action when both fit; side by side if not.
    final stacked = inner >= numberH + cs(8) + pillH;
    final iconSize = (inner * 0.5).clamp(cs(30), cs(60)).toDouble();

    // ── Colours by state ─────────────────────────────────────────────────
    final titleColor = claimed ? CsColors.ink45 : CsColors.ink;
    final Color numberColor = switch (status) {
      DirectiveCardStatus.claimed => CsColors.ink45,
      DirectiveCardStatus.claimable => CsColors.mint,
      DirectiveCardStatus.inProgress => CsColors.ink,
    };
    final Gradient barGradient;
    if (claimed) {
      barGradient = LinearGradient(colors: [
        CsColors.mint.withValues(alpha: .4),
        CsColors.mint.withValues(alpha: .4),
      ]);
    } else if (done) {
      barGradient = CsGradients.complete;
    } else if (c.progressPercentage >= 0.75) {
      // Nearly there: the one place the prism earns its keep.
      barGradient = CsGradients.prism;
    } else {
      barGradient = const LinearGradient(colors: [CsColors.ink70, CsColors.ink70]);
    }

    // ── Pieces ───────────────────────────────────────────────────────────
    final glyph = SizedBox.square(
      dimension: iconSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: claimed ? null : CsColors.raised,
          border: Border.all(
            color: claimable ? CsColors.mint.withValues(alpha: .5) : CsColors.hairline,
          ),
        ),
        child: Icon(
          claimed ? Symbols.check_rounded : directiveIcon(c),
          size: iconSize * 0.5,
          fill: 1,
          color: switch (status) {
            DirectiveCardStatus.claimed => CsColors.mint.withValues(alpha: .7),
            DirectiveCardStatus.claimable => CsColors.mint,
            DirectiveCardStatus.inProgress => CsColors.ink,
          },
        ),
      ),
    );

    final titleRow = Row(
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              c.displayTitle,
              maxLines: 1,
              style: t.display(titleSize, weight: FontWeight.w700, em: -0.01, height: 1.2, color: titleColor),
            ),
          ),
        ),
        SizedBox(width: cs(8)),
        CsChip(c.difficulty.displayName),
      ],
    );

    final xpColor = claimed ? CsColors.ink45 : CsColors.violet;
    final coinColor = claimed ? CsColors.ink45 : CsColors.gold;
    final reward = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CsCoinGlyph(size: 12),
        SizedBox(width: cs(5)),
        Text(
          '+${c.coinReward} CR',
          maxLines: 1,
          style: t.mono(10.5, weight: FontWeight.w600, em: 0.06, color: coinColor, height: 1.2),
        ),
        SizedBox(width: cs(10)),
        Text(
          '+${c.xpReward} XP',
          maxLines: 1,
          style: t.mono(10.5, weight: FontWeight.w600, em: 0.06, color: xpColor, height: 1.2),
        ),
      ],
    );

    final middle = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleRow,
        if (descLines > 0) ...[
          SizedBox(height: gapS),
          Text(
            c.displayDescription,
            maxLines: descLines,
            overflow: TextOverflow.ellipsis,
            style: t.body.copyWith(color: claimed ? CsColors.ink30 : CsColors.ink60),
          ),
        ],
        SizedBox(height: gapM),
        CsProgressLine(value: barValue, height: barH, gradient: barGradient),
        SizedBox(height: gapM),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: reward),
      ],
    );

    final current = c.currentProgress.clamp(0, c.targetValue);
    final unit = c.type == ChallengeType.survival ? ' s' : '';
    final number = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          CsOdometer(
            value: current,
            style: t.number(numberSize, em: -0.04, height: 1, color: numberColor),
            semanticsLabel: '$current of ${c.targetValue}$unit',
          ),
          Text(
            ' / ${formatDirectiveCount(c.targetValue)}$unit',
            maxLines: 1,
            style: t.number(numberSize * 0.5, height: 1, color: CsColors.ink45),
          ),
        ],
      ),
    );

    final Widget? action = switch (status) {
      DirectiveCardStatus.claimable => CsButton.primary(
          label: 'Claim',
          icon: Symbols.redeem_rounded,
          size: CsButtonSize.small,
          onPressed: onClaim,
        ),
      DirectiveCardStatus.claimed =>
        const CsChip('Claimed', kind: CsChipKind.mint, icon: Symbols.check_rounded),
      DirectiveCardStatus.inProgress => onFly == null
          ? null
          : CsButton.secondary(
              label: 'Fly',
              icon: Symbols.rocket_launch_rounded,
              size: CsButtonSize.small,
              onPressed: onFly,
            ),
    };

    // A fixed share of the card (not the content's width) so the middle
    // columns, and so the progress lines, line up across the three cards.
    final trailingWidth = width.isFinite ? width * (stacked ? 0.27 : 0.4) : cs(200);
    final Widget trailing = SizedBox(
      width: trailingWidth,
      child: stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                number,
                if (action != null) ...[SizedBox(height: cs(8)), action],
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(child: number),
                if (action != null) ...[SizedBox(width: cs(10)), action],
              ],
            ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: claimed ? null : CsColors.fill03,
        borderRadius: BorderRadius.circular(cs(CsRadius.tile)),
        border: Border.all(
          color: claimable ? CsColors.mint.withValues(alpha: .35) : CsColors.hairline,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: Row(
          children: [
            glyph,
            SizedBox(width: roomy ? cs(20) : cs(14)),
            Expanded(child: middle),
            SizedBox(width: roomy ? cs(24) : cs(16)),
            trailing,
          ],
        ),
      ),
    );
  }
}
