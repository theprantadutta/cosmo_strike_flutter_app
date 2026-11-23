import 'dart:async';

import 'analytics_client.dart';
import 'analytics_params.dart';

/// Run context `game_over` / `game_abandoned` pick up when the caller
/// doesn't pass it. RunSession installs the provider.
typedef RunAnalyticsContext = ({
  int runNumber,
  bool onboarding,
  String? endTrigger,
});

/// `revive_offer.outcome` values.
abstract final class ReviveOutcome {
  static const ad = 'ad';
  static const coins = 'coins';
  static const free = 'free';
  static const declined = 'declined';
  static const timeout = 'timeout';

  /// The run got no revive offer because it was an onboarding run.
  static const skippedOnboarding = 'skipped_onboarding';
}

/// `game_over.end_trigger` / `game_abandoned.end_trigger` values.
abstract final class EndTrigger {
  static const death = 'death';
  static const quit = 'quit';
  static const time = 'time';
  static const victory = 'victory';
}

/// Multi-client dispatcher that fans out every analytics call to all
/// registered [AnalyticsClient] implementations.
///
/// All calls are fire-and-forget via [unawaited] so they never block the UI.
class AnalyticsFacade implements AnalyticsClient {
  final List<AnalyticsClient> _clients;

  AnalyticsFacade(this._clients);

  /// Supplies the current/last run's context for [trackGameOver] and
  /// [trackGameAbandoned] when the caller leaves it out.
  static RunAnalyticsContext? Function()? runContext;

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
  Future<void> setUserProperties({String? authMethod, bool? isPremium}) async =>
      _fire(
        (c) =>
            c.setUserProperties(authMethod: authMethod, isPremium: isPremium),
      );

  @override
  Future<void> trackAppOpened() async => _fire((c) => c.trackAppOpened());

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      _fire((c) => c.setUserProperty(name, value));

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      _fire((c) => c.setCollectionEnabled(enabled));

  @override
  Future<void> trackEvent(String name, Map<String, Object> parameters) async =>
      _fire((c) => c.trackEvent(name, parameters));

  // ==================== Screen Views ====================

  @override
  Future<void> trackScreenView(String screenName) async =>
      _fire((c) => c.trackScreenView(screenName));

  // ==================== Auth ====================

  @override
  Future<void> trackSignInGoogle() async => _fire((c) => c.trackSignInGoogle());

  @override
  Future<void> trackSignInAnonymous() async =>
      _fire((c) => c.trackSignInAnonymous());

  @override
  Future<void> trackSignInEmail() async => _fire((c) => c.trackSignInEmail());

  @override
  Future<void> trackSignInApple() async => _fire((c) => c.trackSignInApple());

  @override
  Future<void> trackSignOut() async => _fire((c) => c.trackSignOut());

  @override
  Future<void> trackUsernameSet() async => _fire((c) => c.trackUsernameSet());

  // ==================== Core Gameplay ====================

  @override
  Future<void> trackGameStarted({
    required String gameMode,
    required int startLevel,
  }) async => _fire(
    (c) => c.trackGameStarted(gameMode: gameMode, startLevel: startLevel),
  );

  @override
  Future<void> trackGamePaused() async => _fire((c) => c.trackGamePaused());

  @override
  Future<void> trackGameResumed() async => _fire((c) => c.trackGameResumed());

  @override
  Future<void> trackGameOver({
    required int score,
    required int durationSeconds,
    required int stageReached,
    required int levelsCleared,
    required int enemiesKilled,
    required int maxCombo,
    required bool victory,
    required String gameMode,
    int? runNumber,
    bool? onboarding,
    String? endTrigger,
  }) async {
    final ctx = runContext?.call();
    final trigger =
        endTrigger ??
        ctx?.endTrigger ??
        (victory ? EndTrigger.victory : EndTrigger.death);
    _fire(
      (c) => c.trackGameOver(
        score: score,
        durationSeconds: durationSeconds,
        stageReached: stageReached,
        levelsCleared: levelsCleared,
        enemiesKilled: enemiesKilled,
        maxCombo: maxCombo,
        victory: victory,
        gameMode: gameMode,
        runNumber: runNumber ?? ctx?.runNumber,
        onboarding: onboarding ?? ctx?.onboarding,
        endTrigger: trigger,
      ),
    );
  }

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
      _fire((c) => c.trackMultiplayerGameEnded(score: score, result: result));

  // ==================== Progression ====================

  @override
  Future<void> trackAchievementUnlocked({
    required String achievementId,
    required String achievementName,
  }) async => _fire(
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
  }) async => _fire(
    (c) => c.trackBattlePassRewardClaimed(tier: tier, rewardType: rewardType),
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
  }) async => _fire(
    (c) =>
        c.trackItemPurchased(itemId: itemId, itemType: itemType, price: price),
  );

  @override
  Future<void> trackPurchaseInitiated({
    required String productId,
    required String productType,
  }) async => _fire(
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
  }) async => _fire(
    (c) => c.trackPurchaseFailed(productId: productId, errorCode: errorCode),
  );

  @override
  Future<void> trackPremiumSubscriptionStarted() async =>
      _fire((c) => c.trackPremiumSubscriptionStarted());

  @override
  Future<void> trackCosmeticEquipped({
    required String cosmeticType,
    required String cosmeticId,
  }) async => _fire(
    (c) => c.trackCosmeticEquipped(
      cosmeticType: cosmeticType,
      cosmeticId: cosmeticId,
    ),
  );

  @override
  Future<void> trackThemeSelected(String themeName) async =>
      _fire((c) => c.trackThemeSelected(themeName));

  // ==================== Ads ====================

  @override
  Future<void> trackAdLoad({
    required String format,
    required int requests,
    required int filled,
    required int failed,
    required String errorCodes,
  }) async => _fire(
    (c) => c.trackAdLoad(
      format: format,
      requests: requests,
      filled: filled,
      failed: failed,
      errorCodes: errorCodes,
    ),
  );

  @override
  Future<void> trackAdRevenue({
    required String format,
    required int valueMicros,
    required String currencyCode,
    required String precision,
  }) async => _fire(
    (c) => c.trackAdRevenue(
      format: format,
      valueMicros: valueMicros,
      currencyCode: currencyCode,
      precision: precision,
    ),
  );

  @override
  Future<void> trackRewardedResult({
    required String placement,
    required String outcome,
  }) async => _fire(
    (c) => c.trackRewardedResult(placement: placement, outcome: outcome),
  );

  // ==================== Settings ====================

  @override
  Future<void> trackSettingChanged({
    required String settingName,
    required String value,
  }) async => _fire(
    (c) => c.trackSettingChanged(settingName: settingName, value: value),
  );

  // ==================== Social ====================

  @override
  Future<void> trackLeaderboardViewed(String type) async =>
      _fire((c) => c.trackLeaderboardViewed(type));

  @override
  Future<void> trackFriendAdded() async => _fire((c) => c.trackFriendAdded());

  @override
  Future<void> trackFriendRemoved() async =>
      _fire((c) => c.trackFriendRemoved());

  @override
  Future<void> trackTournamentEntered({
    required String tournamentId,
    required String tier,
  }) async => _fire(
    (c) => c.trackTournamentEntered(tournamentId: tournamentId, tier: tier),
  );

  @override
  Future<void> trackReplayViewed() async => _fire((c) => c.trackReplayViewed());

  @override
  Future<void> trackReplayShared() async => _fire((c) => c.trackReplayShared());

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
  Future<void> trackGameTutorialStarted() async =>
      _fire((c) => c.trackGameTutorialStarted());

  @override
  Future<void> trackGameTutorialCompleted() async =>
      _fire((c) => c.trackGameTutorialCompleted());

  @override
  Future<void> trackGameTutorialSkipped() async =>
      _fire((c) => c.trackGameTutorialSkipped());

  @override
  Future<void> trackReviewRequested(String trigger) async =>
      _fire((c) => c.trackReviewRequested(trigger));

  // ==================== First-run funnel ====================

  @override
  Future<void> trackOnboardingStepShown(String step) async =>
      _fire((c) => c.trackOnboardingStepShown(step));

  @override
  Future<void> trackOnboardingStepCompleted(
    String step, {
    bool skipped = false,
  }) async =>
      _fire((c) => c.trackOnboardingStepCompleted(step, skipped: skipped));

  @override
  Future<void> trackFirstGameStarted({
    required int secondsSinceInstall,
    required String gameMode,
  }) async => _fire(
    (c) => c.trackFirstGameStarted(
      secondsSinceInstall: secondsSinceInstall,
      gameMode: gameMode,
    ),
  );

  @override
  Future<void> trackSecondGameStarted({
    required int secondsSinceInstall,
    required int secondsSinceFirstGame,
  }) async => _fire(
    (c) => c.trackSecondGameStarted(
      secondsSinceInstall: secondsSinceInstall,
      secondsSinceFirstGame: secondsSinceFirstGame,
    ),
  );

  @override
  Future<void> trackOnboardingRunEnded({
    required int runNumber,
    required String outcome,
    required int score,
    required int levelReached,
    required int levelsCleared,
    required int durationSeconds,
    required bool eased,
  }) async => _fire(
    (c) => c.trackOnboardingRunEnded(
      runNumber: runNumber,
      outcome: outcome,
      score: score,
      levelReached: levelReached,
      levelsCleared: levelsCleared,
      durationSeconds: durationSeconds,
      eased: eased,
    ),
  );

  // ==================== Retention (generic-event wrappers) ====================
  //
  // Parameter names must be registered in GA4 as custom definitions:
  // docs/analytics/GA4_CUSTOM_DEFINITIONS.md.

  /// A run left mid-play (quit / restart from pause). Same shape as
  /// `game_over` so the two add up to "runs started".
  Future<void> trackGameAbandoned({
    required int score,
    required int durationSeconds,
    required int stageReached,
    required int levelsCleared,
    required String gameMode,
    int? runNumber,
    bool? onboarding,
    String endTrigger = EndTrigger.quit,
  }) async {
    final ctx = runContext?.call();
    final run = runNumber ?? ctx?.runNumber;
    final onb = onboarding ?? ctx?.onboarding;
    await trackEvent('game_abandoned', {
      'score': score,
      'duration_seconds': durationSeconds,
      'stage_reached': stageReached,
      'levels_cleared': levelsCleared,
      'game_mode': gameMode,
      'end_trigger': endTrigger,
      'run_number': ?run,
      if (onb != null) 'onboarding': onb ? 1 : 0,
    });
  }

  /// How the one-per-run revive offer ended ([ReviveOutcome]).
  Future<void> trackReviveOffer({
    required String outcome,
    required int runNumber,
  }) => trackEvent('revive_offer', {
    'outcome': outcome,
    'run_number': runNumber,
  });

  /// First steer/tap of an install's very first run. [controlScheme] is
  /// the selected scheme (`drag` / `dpad`); [input] what was touched
  /// (`drag` / `dpad` / `tap`).
  Future<void> trackFirstInput({
    required int secondsSinceRunStart,
    required String controlScheme,
    String? input,
  }) => trackEvent('first_input', {
    'seconds_since_run_start': secondsSinceRunStart,
    'control_scheme': controlScheme,
    'input': ?input,
  });

  /// A tapped notification. [pushType] is the payload's `type`
  /// (`comeback_reminder`, server types...); [source] is `fcm` or `local`;
  /// [coldStart] is 1 when the tap launched the app from scratch.
  Future<void> trackPushOpened({
    required String pushType,
    required String source,
    bool? coldStart,
  }) => trackEvent('push_opened', {
    'push_type': AnalyticsParams.clip(pushType),
    'source': source,
    if (coldStart != null) 'cold_start': coldStart ? 1 : 0,
  });

  /// One step of a notification-permission ask. [placement]: where it was
  /// asked (`home_soft_ask`, `settings`, `new_best`...). [result]:
  /// `soft_shown` / `soft_declined` / `already_enabled` / `granted` /
  /// `denied` / `settings_opened`.
  Future<void> trackNotificationPermission({
    required String placement,
    required String result,
  }) => trackEvent('notification_permission', {
    'placement': placement,
    'result': result,
  });

  /// The game-over "Next up" strip showed a goal of [kind].
  Future<void> trackNextGoalShown({required String kind}) =>
      trackEvent('next_goal_shown', {'kind': kind});

  /// The player tapped the "Next up" goal of [kind].
  Future<void> trackNextGoalTapped({required String kind}) =>
      trackEvent('next_goal_tapped', {'kind': kind});

  /// User property `install_week` (ISO year-week of the install).
  Future<void> setInstallWeek(DateTime installedAt) =>
      setUserProperty('install_week', AnalyticsParams.isoWeek(installedAt));

  /// User property `onboarding_done` (0/1).
  Future<void> setOnboardingDone(bool done) =>
      setUserProperty('onboarding_done', done ? '1' : '0');
}
