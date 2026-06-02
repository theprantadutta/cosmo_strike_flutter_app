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
      // Step 1: Welcome and Play Button
      WalkthroughStep(
        id: 'home_play',
        title: 'Welcome to Cosmo Strike!',
        message: 'Tap the PLAY button to start a game. Swipe to control your ship and eat food to grow!',
        targetKey: playButtonKey,
        position: TooltipPosition.above,
        icon: Icons.play_arrow_rounded,
        spotlightPadding: 12,
        spotlightBorderRadius: 100, // Circular button
      ),

      // Step 2: Coins Display
      WalkthroughStep(
        id: 'home_coins',
        title: 'Your Coins',
        message: 'Earn coins by playing games, completing challenges, and daily bonuses. Use them in the store!',
        targetKey: coinsKey,
        position: TooltipPosition.below,
        icon: Icons.monetization_on,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 3: Daily Challenges
      WalkthroughStep(
        id: 'home_daily',
        title: 'Daily Challenges',
        message: 'Complete daily challenges for bonus coins and rewards. New challenges every day!',
        targetKey: dailyChallengesKey,
        position: TooltipPosition.above,
        icon: Icons.calendar_today,
        spotlightPadding: 6,
        spotlightBorderRadius: 18,
      ),

      // Step 4: Store
      WalkthroughStep(
        id: 'home_store',
        title: 'The Store',
        message: 'Buy themes, ship skins, trails, and power-ups with your coins. Unlock Pro for premium boards and exclusive cosmetics.',
        targetKey: storeKey,
        position: TooltipPosition.above,
        icon: Icons.store,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 5: Cosmetics
      WalkthroughStep(
        id: 'home_cosmetics',
        title: 'Skins & Trails',
        message: 'Customize your ship here. Skins change how the ship itself looks; trails leave a glow behind it. Earn with coins or unlock with Pro.',
        targetKey: cosmeticsKey,
        position: TooltipPosition.above,
        icon: Icons.palette,
        spotlightPadding: 6,
        spotlightBorderRadius: 14,
      ),

      // Step 7: Profile
      WalkthroughStep(
        id: 'home_profile',
        title: 'Your Profile',
        message: "Stats, achievements, and high scores live here. Achievements unlock as you hit milestones — some require a specific mode (Classic, Hard, etc.). Sign in to sync across devices.",
        targetKey: profileKey,
        position: TooltipPosition.below,
        icon: Icons.account_circle,
        spotlightPadding: 8,
        spotlightBorderRadius: 20,
      ),

      // Step 8: Settings
      WalkthroughStep(
        id: 'home_settings',
        title: 'Settings',
        message: 'Customize your game experience - change themes, controls, audio, and more!',
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
