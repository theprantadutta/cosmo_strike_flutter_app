import 'package:firebase_analytics/firebase_analytics.dart';

import 'analytics_client.dart';

/// Firebase Analytics implementation of [AnalyticsClient].
///
/// Uses Firebase's built-in methods where available (screen view, user ID,
/// user properties) and custom `logEvent` for everything else.
class FirebaseAnalyticsClient implements AnalyticsClient {
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  @override
  Future<void> setUserId(String? userId) {
    return _analytics.setUserId(id: userId);
  }

  @override
  Future<void> setUserProperties({String? authMethod, bool? isPremium}) async {
    if (authMethod != null) {
      await _analytics.setUserProperty(name: 'auth_method', value: authMethod);
    }
    if (isPremium != null) {
      await _analytics.setUserProperty(
        name: 'is_premium',
        value: isPremium.toString(),
      );
    }
  }

  @override
  Future<void> trackAppOpened() {
    return _analytics.logAppOpen();
  }

  @override
  Future<void> trackScreenView(String screenName) {
    return _analytics.logScreenView(screenName: screenName);
  }

  @override
  Future<void> trackSignInGoogle() {
    return _analytics.logLogin(loginMethod: 'google');
  }

  @override
  Future<void> trackSignInAnonymous() {
    return _analytics.logLogin(loginMethod: 'anonymous');
  }

  @override
  Future<void> trackSignInEmail() {
    return _analytics.logLogin(loginMethod: 'email');
  }

  @override
  Future<void> trackSignOut() {
    return _analytics.logEvent(name: 'sign_out');
  }

  @override
  Future<void> trackUsernameSet() {
    return _analytics.logEvent(name: 'username_set');
  }

  @override
  Future<void> trackGameStarted({
    required int boardWidth,
    required int boardHeight,
    required String gameMode,
  }) {
    return _analytics.logEvent(
      name: 'game_started',
      parameters: {
        'board_width': boardWidth,
        'board_height': boardHeight,
        'game_mode': gameMode,
      },
    );
  }

  @override
  Future<void> trackGamePaused() {
    return _analytics.logEvent(name: 'game_paused');
  }

  @override
  Future<void> trackGameResumed() {
    return _analytics.logEvent(name: 'game_resumed');
  }

  @override
  Future<void> trackGameOver({
    required int score,
    required int level,
    required int durationSeconds,
    required String cause,
    required int foodEaten,
    required int powerUpsCollected,
    required int maxCombo,
    required bool isNewHighScore,
  }) {
    return _analytics.logEvent(
      name: 'game_over',
      parameters: {
        'score': score,
        'level': level,
        'duration_seconds': durationSeconds,
        'cause': cause,
        'food_eaten': foodEaten,
        'power_ups_collected': powerUpsCollected,
        'max_combo': maxCombo,
        'is_new_high_score': isNewHighScore ? 1 : 0,
      },
    );
  }

  @override
  Future<void> trackLevelUp(int level) {
    return _analytics.logLevelUp(level: level);
  }

  @override
  Future<void> trackPowerUpUsed(String powerUpType) {
    return _analytics.logEvent(
      name: 'power_up_used',
      parameters: {'power_up_type': powerUpType},
    );
  }

  @override
  Future<void> trackMultiplayerQueueJoined() {
    return _analytics.logEvent(name: 'multiplayer_queue_joined');
  }

  @override
  Future<void> trackMultiplayerGameStarted() {
    return _analytics.logEvent(name: 'multiplayer_game_started');
  }

  @override
  Future<void> trackMultiplayerGameEnded({
    required int score,
    required String result,
  }) {
    return _analytics.logEvent(
      name: 'multiplayer_game_ended',
      parameters: {'score': score, 'result': result},
    );
  }

  @override
  Future<void> trackAchievementUnlocked({
    required String achievementId,
    required String achievementName,
  }) {
    return _analytics.logUnlockAchievement(id: achievementId);
  }

  @override
  Future<void> trackDailyChallengeCompleted(String challengeId) {
    return _analytics.logEvent(
      name: 'daily_challenge_completed',
      parameters: {'challenge_id': challengeId},
    );
  }

  @override
  Future<void> trackDailyChallengeRewardClaimed() {
    return _analytics.logEvent(name: 'daily_challenge_reward_claimed');
  }

  @override
  Future<void> trackBattlePassTierReached(int tier) {
    return _analytics.logEvent(
      name: 'battle_pass_tier_reached',
      parameters: {'tier': tier},
    );
  }

  @override
  Future<void> trackBattlePassRewardClaimed({
    required int tier,
    required String rewardType,
  }) {
    return _analytics.logEvent(
      name: 'battle_pass_reward_claimed',
      parameters: {'tier': tier, 'reward_type': rewardType},
    );
  }

  @override
  Future<void> trackStoreTabViewed(String tabName) {
    return _analytics.logEvent(
      name: 'store_tab_viewed',
      parameters: {'tab_name': tabName},
    );
  }

  @override
  Future<void> trackItemPurchased({
    required String itemId,
    required String itemType,
    required String price,
  }) {
    return _analytics.logEvent(
      name: 'item_purchased',
      parameters: {
        'item_id': itemId,
        'item_type': itemType,
        'price': price,
      },
    );
  }

  @override
  Future<void> trackPurchaseInitiated({
    required String productId,
    required String productType,
  }) {
    return _analytics.logEvent(
      name: 'purchase_initiated',
      parameters: {
        'product_id': productId,
        'product_type': productType,
      },
    );
  }

  @override
  Future<void> trackPurchaseCancelled({required String productId}) {
    return _analytics.logEvent(
      name: 'purchase_cancelled',
      parameters: {'product_id': productId},
    );
  }

  @override
  Future<void> trackPurchaseFailed({
    required String productId,
    String? errorCode,
  }) {
    return _analytics.logEvent(
      name: 'purchase_failed',
      parameters: {
        'product_id': productId,
        'error_code': ?errorCode,
      },
    );
  }

  @override
  Future<void> trackPremiumSubscriptionStarted() {
    return _analytics.logEvent(name: 'premium_subscription_started');
  }

  @override
  Future<void> trackPremiumTrialStarted() {
    return _analytics.logEvent(name: 'premium_trial_started');
  }

  @override
  Future<void> trackCosmeticEquipped({
    required String cosmeticType,
    required String cosmeticId,
  }) {
    return _analytics.logEvent(
      name: 'cosmetic_equipped',
      parameters: {
        'cosmetic_type': cosmeticType,
        'cosmetic_id': cosmeticId,
      },
    );
  }

  @override
  Future<void> trackThemeSelected(String themeName) {
    return _analytics.logEvent(
      name: 'theme_selected',
      parameters: {'theme_name': themeName},
    );
  }

  @override
  Future<void> trackSettingChanged({
    required String settingName,
    required String value,
  }) {
    return _analytics.logEvent(
      name: 'setting_changed',
      parameters: {'setting_name': settingName, 'value': value},
    );
  }

  @override
  Future<void> trackLeaderboardViewed(String type) {
    return _analytics.logEvent(
      name: 'leaderboard_viewed',
      parameters: {'type': type},
    );
  }

  @override
  Future<void> trackFriendAdded() {
    return _analytics.logEvent(name: 'friend_added');
  }

  @override
  Future<void> trackFriendRemoved() {
    return _analytics.logEvent(name: 'friend_removed');
  }

  @override
  Future<void> trackTournamentEntered({
    required String tournamentId,
    required String tier,
  }) {
    return _analytics.logEvent(
      name: 'tournament_entered',
      parameters: {'tournament_id': tournamentId, 'tier': tier},
    );
  }

  @override
  Future<void> trackReplayViewed() {
    return _analytics.logEvent(name: 'replay_viewed');
  }

  @override
  Future<void> trackReplayShared() {
    return _analytics.logEvent(name: 'replay_shared');
  }

  @override
  Future<void> trackDailyBonusCollected() {
    return _analytics.logEvent(name: 'daily_bonus_collected');
  }

  @override
  Future<void> trackWalkthroughStarted() {
    return _analytics.logTutorialBegin();
  }

  @override
  Future<void> trackWalkthroughCompleted() {
    return _analytics.logTutorialComplete();
  }

  @override
  Future<void> trackReviewRequested(String trigger) {
    return _analytics.logEvent(
      name: 'review_requested',
      parameters: {'trigger': trigger},
    );
  }
}
