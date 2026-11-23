import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/number_format.dart';
import 'package:material_ui/material_ui.dart';

/// The game over's inline new-best reminder ask (see `NewBestReminderAsk`):
/// "Remind me tomorrow to beat 9,170?" with REMIND ME and a dismiss ×.
/// It is the soft ask: the OS prompt only follows the tap ([onAccept]).
/// After an answer it settles to a one-line confirmation (granted) or
/// folds away (declined / dismissed). Never a dialog.
class NewBestReminderRow extends StatefulWidget {
  const NewBestReminderRow({
    super.key,
    required this.bestScore,
    required this.onAccept,
    required this.onDismiss,
  });

  final int bestScore;

  /// Runs the permission flow; resolves to whether notifications are on.
  final Future<bool> Function() onAccept;
  final VoidCallback onDismiss;

  @override
  State<NewBestReminderRow> createState() => _NewBestReminderRowState();
}

enum _AskState { asking, busy, granted, closed }

class _NewBestReminderRowState extends State<NewBestReminderRow> {
  _AskState _state = _AskState.asking;

  Future<void> _accept() async {
    if (_state != _AskState.asking) return;
    setState(() => _state = _AskState.busy);
    var granted = false;
    try {
      granted = await widget.onAccept();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _state = granted ? _AskState.granted : _AskState.closed);
  }

  void _dismiss() {
    if (_state != _AskState.asking) return;
    setState(() => _state = _AskState.closed);
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final Widget child = switch (_state) {
      _AskState.closed => const SizedBox(width: double.infinity),
      _AskState.granted => Padding(
          padding: EdgeInsets.only(bottom: cs(12)),
          child: Row(
            children: [
              Icon(Symbols.check_circle_rounded, size: cs(14), color: CsColors.mint),
              SizedBox(width: cs(8)),
              Expanded(
                child: Text(
                  'REMINDER SET · SEE YOU TOMORROW',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(10, em: 0.1, color: CsColors.mint),
                ),
              ),
            ],
          ),
        ),
      _ => Padding(
          padding: EdgeInsets.only(bottom: cs(12)),
          child: Container(
            padding: EdgeInsets.only(left: cs(12), top: cs(8), bottom: cs(8)),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: CsColors.cyan, width: 2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Remind me tomorrow to beat ${formatThousands(widget.bestScore)}?',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.rowTitle.copyWith(fontSize: cs(14)),
                  ),
                ),
                SizedBox(width: cs(10)),
                CsButton.secondary(
                  label: 'Remind me',
                  icon: Symbols.notifications_active_rounded,
                  size: CsButtonSize.small,
                  loading: _state == _AskState.busy,
                  onPressed: _accept,
                ),
                CsIconButton(
                  icon: Symbols.close_rounded,
                  size: 32,
                  bordered: false,
                  color: CsColors.ink45,
                  tooltip: 'Not now',
                  onPressed: _dismiss,
                ),
              ],
            ),
          ),
        ),
    };
    // Size settles (no opacity layer over the subtree).
    return AnimatedSize(
      duration: CsMotion.base,
      curve: CsMotion.standard,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}
