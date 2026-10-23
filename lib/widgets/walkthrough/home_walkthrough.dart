import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';

/// Defines the walkthrough steps for the home screen
class HomeWalkthrough {
  /// GlobalKeys for target widgets on the home screen
  /// These need to be assigned to the corresponding widgets in HomeScreen
  static final playButtonKey = GlobalKey();
  static final coinsKey = GlobalKey();
  static final dailyChallengesKey = GlobalKey();
  static final storeKey = GlobalKey();
  static final profileKey = GlobalKey();
  static final settingsKey = GlobalKey();
  /// Hangar nav item (permanent upgrades, ships, skins + trails).
  static final cosmeticsKey = GlobalKey();

  /// Get the list of walkthrough steps
  /// Call this after the keys have been assigned to their widgets
  static List<WalkthroughStep> getSteps() {
    return [
      // Step 1: Welcome and the launch bay. The bay fills the right column,
      // so the tooltip goes to its LEFT (above/below have no room in the
      // short landscape viewport).
      WalkthroughStep(
        id: 'home_play',
        title: 'Launch bay',
        message:
            'Tap to launch. Fly the campaign: break formations, graze '
            'enemy fire to charge Overdrive, and drop each boss.',
        targetKey: playButtonKey,
        position: TooltipPosition.left,
        icon: Symbols.rocket_launch_rounded,
        spotlightPadding: 8,
        spotlightBorderRadius: 24,
      ),

      // Step 2: Credits display (top bar, centre).
      WalkthroughStep(
        id: 'home_coins',
        title: 'Credits',
        message:
            'Every run, Daily Directive and Supply Drop pays out in credits. '
            'Spend them on Hangar upgrades and Armory gear.',
        targetKey: coinsKey,
        position: TooltipPosition.below,
        icon: Symbols.paid_rounded,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 3: Daily Directives (nav rail, top row).
      WalkthroughStep(
        id: 'home_daily',
        title: 'Daily Directives',
        message:
            'Three new orders every day. Complete them for credits and '
            'Frontline XP.',
        targetKey: dailyChallengesKey,
        position: TooltipPosition.below,
        icon: Symbols.calendar_today_rounded,
        spotlightPadding: 6,
        spotlightBorderRadius: 18,
      ),

      // Step 4: Armory (action row under the launch bay).
      WalkthroughStep(
        id: 'home_store',
        title: 'Armory',
        message:
            'Liveries, exhausts, Sectors and Tactical Gear. Strike Command '
            'adds 50% to credit payouts and removes ads.',
        targetKey: storeKey,
        position: TooltipPosition.above,
        icon: Symbols.storefront_rounded,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 5: Cosmetics (nav rail, bottom row).
      WalkthroughStep(
        id: 'home_cosmetics',
        title: 'Hangar',
        message:
            'Permanent ship upgrades for every run. Clear campaign levels '
            'to unlock new frames.',
        targetKey: cosmeticsKey,
        position: TooltipPosition.above,
        icon: Symbols.palette_rounded,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 6: Profile (top bar, right cluster).
      WalkthroughStep(
        id: 'home_profile',
        title: 'Pilot File',
        message:
            'Service Record, Commendations and best scores. Sign in to back '
            'up your progress across devices.',
        targetKey: profileKey,
        position: TooltipPosition.below,
        icon: Symbols.account_circle_rounded,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 7: Settings (top bar, right cluster).
      WalkthroughStep(
        id: 'home_settings',
        title: 'Settings',
        message:
            'Flight mode, controls, audio and Sectors. Tune the ship to '
            'your hands.',
        targetKey: settingsKey,
        position: TooltipPosition.below,
        icon: Symbols.settings_rounded,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
        actionLabel: 'Launch',
      ),
    ];
  }
}
