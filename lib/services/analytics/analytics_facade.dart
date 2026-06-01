import 'dart:async';

import 'analytics_client.dart';

/// Multi-client dispatcher that fans out every analytics call to all
/// registered [AnalyticsClient] implementations.
///
/// All calls are fire-and-forget via [unawaited] so they never block the UI.
class AnalyticsFacade implements AnalyticsClient {
  final List<AnalyticsClient> _clients;

  AnalyticsFacade(this._clients);

  void _fire(Future<void> Function(AnalyticsClient c) action) {
    for (final client in _clients) {
      unawaited(action(client));
    }
  }

  // ==================== App Lifecycle ====================

  @override
  Future<void> setUserId(String? userId) async =>
      _fire((c) => c.setUserId(userId));

  @override
  Future<void> setUserProperties({
    String? authMethod,
    bool? isPremium,
  }) async =>
      _fire(
        (c) => c.setUserProperties(
          authMethod: authMethod,
          isPremium: isPremium,
        ),
      );

  @override
  Future<void> trackAppOpened() async => _fire((c) => c.trackAppOpened());

  // ==================== Screen Views ====================

  @override
  Future<void> trackScreenView(String screenName) async =>
      _fire((c) => c.trackScreenView(screenName));

  // ==================== Auth ====================

  @override
  Future<void> trackSignInGoogle() async =>
      _fire((c) => c.trackSignInGoogle());

  @override
  Future<void> trackSignInAnonymous() async =>
      _fire((c) => c.trackSignInAnonymous());

  @override
  Future<void> trackSignInEmail() async =>
      _fire((c) => c.trackSignInEmail());

  @override
  Future<void> trackSignOut() async => _fire((c) => c.trackSignOut());

  @override
  Future<void> trackUsernameSet() async =>
      _fire((c) => c.trackUsernameSet());

  // ==================== Core Gameplay ====================

  @override
  Future<void> trackGameStarted({
    required int boardWidth,
    required int boardHeight,
    required String gameMode,
  }) async =>
      _fire(
        (c) => c.trackGameStarted(
          boardWidth: boardWidth,
          boardHeight: boardHeight,
          gameMode: gameMode,
        ),
      );

  @override
  Future<void> trackGamePaused() async => _fire((c) => c.trackGamePaused());

  @override
  Future<void> trackGameResumed() async =>
      _fire((c) => c.trackGameResumed());

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
  }) async =>
      _fire(
        (c) => c.trackGameOver(
          score: score,
          level: level,
          durationSeconds: durationSeconds,
          cause: cause,
          foodEaten: foodEaten,
          powerUpsCollected: powerUpsCollected,
          maxCombo: maxCombo,
          isNewHighScore: isNewHighScore,
        ),
      );

  @override
  Future<void> trackLevelUp(int level) async =>
      _fire((c) => c.trackLevelUp(level));

  @override
  Future<void> trackPowerUpUsed(String powerUpType) async =>
      _fire((c) => c.trackPowerUpUsed(powerUpType));

  // ==================== Multiplayer ====================

  @override
  Future<void> trackMultiplayerQueueJoined() async =>
      _fire((c) => c.trackMultiplayerQueueJoined());

  @override
  Future<void> trackMultiplayerGameStarted() async =>
      _fire((c) => c.trackMultiplayerGameStarted());

  @override
  Future<void> trackMultiplayerGameEnded({
    required int score,
    required String result,
  }) async =>
      _fire(
        (c) => c.trackMultiplayerGameEnded(score: score, result: result),
      );

  // ==================== Progression ====================

  @override
  Future<void> trackAchievementUnlocked({
    required String achievementId,
    required String achievementName,
  }) async =>
      _fire(
        (c) => c.trackAchievementUnlocked(
          achievementId: achievementId,
          achievementName: achievementName,
        ),
      );

  @override
  Future<void> trackDailyChallengeCompleted(String challengeId) async =>
      _fire((c) => c.trackDailyChallengeCompleted(challengeId));

  @override
  Future<void> trackDailyChallengeRewardClaimed() async =>
      _fire((c) => c.trackDailyChallengeRewardClaimed());

  @override
  Future<void> trackBattlePassTierReached(int tier) async =>
      _fire((c) => c.trackBattlePassTierReached(tier));

  @override
  Future<void> trackBattlePassRewardClaimed({
    required int tier,
    required String rewardType,
  }) async =>
      _fire(
        (c) => c.trackBattlePassRewardClaimed(
          tier: tier,
          rewardType: rewardType,
        ),
      );

  // ==================== Monetization ====================

  @override
  Future<void> trackStoreTabViewed(String tabName) async =>
      _fire((c) => c.trackStoreTabViewed(tabName));

  @override
  Future<void> trackItemPurchased({
    required String itemId,
    required String itemType,
    required String price,
  }) async =>
      _fire(
        (c) => c.trackItemPurchased(
          itemId: itemId,
          itemType: itemType,
          price: price,
        ),
      );

  @override
  Future<void> trackPurchaseInitiated({
    required String productId,
    required String productType,
  }) async =>
      _fire(
        (c) => c.trackPurchaseInitiated(
          productId: productId,
          productType: productType,
        ),
      );

  @override
  Future<void> trackPurchaseCancelled({required String productId}) async =>
      _fire((c) => c.trackPurchaseCancelled(productId: productId));

  @override
  Future<void> trackPurchaseFailed({
    required String productId,
    String? errorCode,
  }) async =>
      _fire(
        (c) => c.trackPurchaseFailed(productId: productId, errorCode: errorCode),
      );

  @override
  Future<void> trackPremiumSubscriptionStarted() async =>
      _fire((c) => c.trackPremiumSubscriptionStarted());

  @override
  Future<void> trackPremiumTrialStarted() async =>
      _fire((c) => c.trackPremiumTrialStarted());

  @override
  Future<void> trackCosmeticEquipped({
    required String cosmeticType,
    required String cosmeticId,
  }) async =>
      _fire(
        (c) => c.trackCosmeticEquipped(
          cosmeticType: cosmeticType,
          cosmeticId: cosmeticId,
        ),
      );

  @override
  Future<void> trackThemeSelected(String themeName) async =>
      _fire((c) => c.trackThemeSelected(themeName));

  // ==================== Settings ====================

  @override
  Future<void> trackSettingChanged({
    required String settingName,
    required String value,
  }) async =>
      _fire(
        (c) => c.trackSettingChanged(settingName: settingName, value: value),
      );

  // ==================== Social ====================

  @override
  Future<void> trackLeaderboardViewed(String type) async =>
      _fire((c) => c.trackLeaderboardViewed(type));

  @override
  Future<void> trackFriendAdded() async =>
      _fire((c) => c.trackFriendAdded());

  @override
  Future<void> trackFriendRemoved() async =>
      _fire((c) => c.trackFriendRemoved());

  @override
  Future<void> trackTournamentEntered({
    required String tournamentId,
    required String tier,
  }) async =>
      _fire(
        (c) => c.trackTournamentEntered(
          tournamentId: tournamentId,
          tier: tier,
        ),
      );

  @override
  Future<void> trackReplayViewed() async =>
      _fire((c) => c.trackReplayViewed());

  @override
  Future<void> trackReplayShared() async =>
      _fire((c) => c.trackReplayShared());

  // ==================== Engagement ====================

  @override
  Future<void> trackDailyBonusCollected() async =>
      _fire((c) => c.trackDailyBonusCollected());

  @override
  Future<void> trackWalkthroughStarted() async =>
      _fire((c) => c.trackWalkthroughStarted());

  @override
  Future<void> trackWalkthroughCompleted() async =>
      _fire((c) => c.trackWalkthroughCompleted());

  @override
  Future<void> trackReviewRequested(String trigger) async =>
      _fire((c) => c.trackReviewRequested(trigger));
}
