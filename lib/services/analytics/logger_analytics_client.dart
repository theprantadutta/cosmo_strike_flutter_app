import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'analytics_client.dart';

/// Debug-only analytics client that logs events to the console via AppLogger.
class LoggerAnalyticsClient implements AnalyticsClient {
  static const _tag = '[Analytics]';

  @override
  Future<void> setUserId(String? userId) async {
    AppLogger.info('$_tag set_user_id: $userId');
  }

  @override
  Future<void> setUserProperties({String? authMethod, bool? isPremium}) async {
    AppLogger.info(
      '$_tag set_user_properties: authMethod=$authMethod, isPremium=$isPremium',
    );
  }

  @override
  Future<void> trackAppOpened() async {
    AppLogger.info('$_tag app_opened');
  }

  @override
  Future<void> trackScreenView(String screenName) async {
    AppLogger.info('$_tag screen_view: $screenName');
  }

  @override
  Future<void> trackSignInGoogle() async {
    AppLogger.info('$_tag sign_in_google');
  }

  @override
  Future<void> trackSignInAnonymous() async {
    AppLogger.info('$_tag sign_in_anonymous');
  }

  @override
  Future<void> trackSignInEmail() async {
    AppLogger.info('$_tag sign_in_email');
  }

  @override
  Future<void> trackSignOut() async {
    AppLogger.info('$_tag sign_out');
  }

  @override
  Future<void> trackUsernameSet() async {
    AppLogger.info('$_tag username_set');
  }

  @override
  Future<void> trackGameStarted({
    required int boardWidth,
    required int boardHeight,
    required String gameMode,
  }) async {
    AppLogger.info(
      '$_tag game_started: board=${boardWidth}x$boardHeight, mode=$gameMode',
    );
  }

  @override
  Future<void> trackGamePaused() async {
    AppLogger.info('$_tag game_paused');
  }

  @override
  Future<void> trackGameResumed() async {
    AppLogger.info('$_tag game_resumed');
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
  }) async {
    AppLogger.info(
      '$_tag game_over: score=$score, level=$level, duration=${durationSeconds}s, '
      'cause=$cause, food=$foodEaten, powerUps=$powerUpsCollected, '
      'maxCombo=$maxCombo, newHighScore=$isNewHighScore',
    );
  }

  @override
  Future<void> trackLevelUp(int level) async {
    AppLogger.info('$_tag level_up: $level');
  }

  @override
  Future<void> trackPowerUpUsed(String powerUpType) async {
    AppLogger.info('$_tag power_up_used: $powerUpType');
  }

  @override
  Future<void> trackMultiplayerQueueJoined() async {
    AppLogger.info('$_tag multiplayer_queue_joined');
  }

  @override
  Future<void> trackMultiplayerGameStarted() async {
    AppLogger.info('$_tag multiplayer_game_started');
  }

  @override
  Future<void> trackMultiplayerGameEnded({
    required int score,
    required String result,
  }) async {
    AppLogger.info('$_tag multiplayer_game_ended: score=$score, result=$result');
  }

  @override
  Future<void> trackAchievementUnlocked({
    required String achievementId,
    required String achievementName,
  }) async {
    AppLogger.info(
      '$_tag achievement_unlocked: id=$achievementId, name=$achievementName',
    );
  }

  @override
  Future<void> trackDailyChallengeCompleted(String challengeId) async {
    AppLogger.info('$_tag daily_challenge_completed: $challengeId');
  }

  @override
  Future<void> trackDailyChallengeRewardClaimed() async {
    AppLogger.info('$_tag daily_challenge_reward_claimed');
  }

  @override
  Future<void> trackBattlePassTierReached(int tier) async {
    AppLogger.info('$_tag battle_pass_tier_reached: $tier');
  }

  @override
  Future<void> trackBattlePassRewardClaimed({
    required int tier,
    required String rewardType,
  }) async {
    AppLogger.info(
      '$_tag battle_pass_reward_claimed: tier=$tier, type=$rewardType',
    );
  }

  @override
  Future<void> trackStoreTabViewed(String tabName) async {
    AppLogger.info('$_tag store_tab_viewed: $tabName');
  }

  @override
  Future<void> trackItemPurchased({
    required String itemId,
    required String itemType,
    required String price,
  }) async {
    AppLogger.info(
      '$_tag item_purchased: id=$itemId, type=$itemType, price=$price',
    );
  }

  @override
  Future<void> trackPurchaseInitiated({
    required String productId,
    required String productType,
  }) async {
    AppLogger.info(
      '$_tag purchase_initiated: id=$productId, type=$productType',
    );
  }

  @override
  Future<void> trackPurchaseCancelled({required String productId}) async {
    AppLogger.info('$_tag purchase_cancelled: id=$productId');
  }

  @override
  Future<void> trackPurchaseFailed({
    required String productId,
    String? errorCode,
  }) async {
    AppLogger.info(
      '$_tag purchase_failed: id=$productId, error=${errorCode ?? "unknown"}',
    );
  }

  @override
  Future<void> trackPremiumSubscriptionStarted() async {
    AppLogger.info('$_tag premium_subscription_started');
  }

  @override
  Future<void> trackPremiumTrialStarted() async {
    AppLogger.info('$_tag premium_trial_started');
  }

  @override
  Future<void> trackCosmeticEquipped({
    required String cosmeticType,
    required String cosmeticId,
  }) async {
    AppLogger.info(
      '$_tag cosmetic_equipped: type=$cosmeticType, id=$cosmeticId',
    );
  }

  @override
  Future<void> trackThemeSelected(String themeName) async {
    AppLogger.info('$_tag theme_selected: $themeName');
  }

  @override
  Future<void> trackSettingChanged({
    required String settingName,
    required String value,
  }) async {
    AppLogger.info('$_tag setting_changed: $settingName=$value');
  }

  @override
  Future<void> trackLeaderboardViewed(String type) async {
    AppLogger.info('$_tag leaderboard_viewed: $type');
  }

  @override
  Future<void> trackFriendAdded() async {
    AppLogger.info('$_tag friend_added');
  }

  @override
  Future<void> trackFriendRemoved() async {
    AppLogger.info('$_tag friend_removed');
  }

  @override
  Future<void> trackTournamentEntered({
    required String tournamentId,
    required String tier,
  }) async {
    AppLogger.info(
      '$_tag tournament_entered: id=$tournamentId, tier=$tier',
    );
  }

  @override
  Future<void> trackReplayViewed() async {
    AppLogger.info('$_tag replay_viewed');
  }

  @override
  Future<void> trackReplayShared() async {
    AppLogger.info('$_tag replay_shared');
  }

  @override
  Future<void> trackDailyBonusCollected() async {
    AppLogger.info('$_tag daily_bonus_collected');
  }

  @override
  Future<void> trackWalkthroughStarted() async {
    AppLogger.info('$_tag walkthrough_started');
  }

  @override
  Future<void> trackWalkthroughCompleted() async {
    AppLogger.info('$_tag walkthrough_completed');
  }

  @override
  Future<void> trackReviewRequested(String trigger) async {
    AppLogger.info('$_tag review_requested: trigger=$trigger');
  }
}
