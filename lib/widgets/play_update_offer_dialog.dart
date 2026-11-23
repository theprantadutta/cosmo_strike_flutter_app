import 'package:material_ui/material_ui.dart';

import '../services/in_app_update_service.dart';
import '../ui/cs.dart';

/// The Android update offer, shown by Home's prompt queue as the visit's
/// only popup when [InAppUpdateService.checkForUpdate] resolves to
/// `UpdateFlow.offer`.
///
/// "Update now" hands over to Play's blocking flow (download with progress,
/// then Play installs and restarts the game by itself: no Restart button to
/// forget). "Later", a tap outside and back all snooze the offer for
/// `UpdatePolicy.snooze`.
Future<void> showPlayUpdateOfferDialog(BuildContext context) async {
  final service = InAppUpdateService();
  service.markOfferShown();
  final accepted = await showCsDialog<bool>(
    context,
    builder: (ctx) => CsDialog(
      icon: Symbols.system_update_rounded,
      iconColor: CsColors.cyan,
      eyebrow: 'New build',
      title: 'Update available',
      message:
          'A new version of Cosmo Strike is ready. Update now and Google Play '
          'downloads it, installs it and restarts the game by itself.',
      maxWidth: 480,
      actions: [
        CsButton.text(
          label: 'Later',
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
        CsButton.primary(
          label: 'Update now',
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await service.acceptOffer();
  } else {
    await service.snoozeOffer();
  }
}
