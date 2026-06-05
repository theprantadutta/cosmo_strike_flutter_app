import 'package:flutter/material.dart';
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
  /// Cosmetics nav item (skins + trails).
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
        title: 'Welcome to Cosmo Strike!',
        message:
            'This is your launch bay — tap it to deploy. Steer your ship, '
            'blast through enemy waves, and take down the stage boss.',
        targetKey: playButtonKey,
        position: TooltipPosition.left,
        icon: Icons.rocket_launch,
        spotlightPadding: 8,
        spotlightBorderRadius: 24,
      ),

      // Step 2: Coins display (top bar, centre).
      WalkthroughStep(
        id: 'home_coins',
        title: 'Your Coins',
        message:
            'Earn coins from every run, daily challenges, and daily bonuses. '
            'Spend them in the store!',
        targetKey: coinsKey,
        position: TooltipPosition.below,
        icon: Icons.monetization_on,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 3: Daily challenges (nav rail, top row).
      WalkthroughStep(
        id: 'home_daily',
        title: 'Daily Challenges',
        message:
            'Complete daily challenges for bonus coins and XP. '
            'Three fresh ones every day!',
        targetKey: dailyChallengesKey,
        position: TooltipPosition.below,
        icon: Icons.calendar_today,
        spotlightPadding: 6,
        spotlightBorderRadius: 18,
      ),

      // Step 4: Store (action row under the launch bay).
      WalkthroughStep(
        id: 'home_store',
        title: 'The Store',
        message:
            'Buy themes, ship skins, trails, and power-ups with your coins. '
            'Go Pro for 2× coins, no ads, and every premium cosmetic.',
        targetKey: storeKey,
        position: TooltipPosition.above,
        icon: Icons.store,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 5: Cosmetics (nav rail, bottom row).
      WalkthroughStep(
        id: 'home_cosmetics',
        title: 'Skins & Trails',
        message:
            'Customize your ship here. Skins change how it looks; trails '
            'leave a glow behind it. Earn with coins or unlock with Pro.',
        targetKey: cosmeticsKey,
        position: TooltipPosition.above,
        icon: Icons.palette,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 6: Profile (top bar, right cluster).
      WalkthroughStep(
        id: 'home_profile',
        title: 'Your Profile',
        message:
            'Stats, achievements, and high scores live here. Sign in to keep '
            'your progress safe across devices.',
        targetKey: profileKey,
        position: TooltipPosition.below,
        icon: Icons.account_circle,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 7: Settings (top bar, right cluster).
      WalkthroughStep(
        id: 'home_settings',
        title: 'Settings',
        message:
            'Game modes, controls, audio, themes, and more — '
            'tune everything to your liking.',
        targetKey: settingsKey,
        position: TooltipPosition.below,
        icon: Icons.settings,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
        actionLabel: 'Start Playing!',
      ),
    ];
  }
}
