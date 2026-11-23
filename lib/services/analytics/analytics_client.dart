/// Abstract analytics interface.
///
/// All analytics tracking goes through this contract so we can swap
/// implementations (Firebase, console logger, Amplitude, etc.) without
/// touching feature code.
abstract class AnalyticsClient {
  // ==================== App Lifecycle ====================

  Future<void> setUserId(String? userId);
  Future<void> setUserProperties({String? authMethod, bool? isPremium});
  Future<void> trackAppOpened();

  /// One user property by name (`install_week`, `test_device`, ...).
  /// A null [value] clears it.
  Future<void> setUserProperty(String name, String? value);

  /// Turns collection on/off for this device (Firebase:
  /// `setAnalyticsCollectionEnabled`). Off for test devices.
  Future<void> setCollectionEnabled(bool enabled);

  /// A generic named event. The retention events (revive_offer,
  /// first_input, push_opened, ...) go through this, with typed wrappers
  /// on [AnalyticsFacade] — add new events there, not a method per client.
  Future<void> trackEvent(String name, Map<String, Object> parameters);

  // ==================== Screen Views ====================

  Future<void> trackScreenView(String screenName);

  // ==================== Auth ====================

  Future<void> trackSignInGoogle();
  Future<void> trackSignInAnonymous();
  Future<void> trackSignInEmail();
  Future<void> trackSignInApple();
  Future<void> trackSignOut();
  Future<void> trackUsernameSet();

  // ==================== Core Gameplay ====================

  Future<void> trackGameStarted({
    required String gameMode,
    required int startLevel,
  });
  Future<void> trackGamePaused();
  Future<void> trackGameResumed();
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
  });
  Future<void> trackLevelUp(int level);
  Future<void> trackPowerUpUsed(String powerUpType);

  // ==================== Multiplayer ====================

  Future<void> trackMultiplayerQueueJoined();
  Future<void> trackMultiplayerGameStarted();
  Future<void> trackMultiplayerGameEnded({
    required int score,
    required String result,
  });

  // ==================== Progression ====================

  Future<void> trackAchievementUnlocked({
    required String achievementId,
    required String achievementName,
  });
  Future<void> trackDailyChallengeCompleted(String challengeId);
  Future<void> trackDailyChallengeRewardClaimed();
  Future<void> trackBattlePassTierReached(int tier);
  Future<void> trackBattlePassRewardClaimed({
    required int tier,
    required String rewardType,
  });

  // ==================== Monetization ====================

  Future<void> trackStoreTabViewed(String tabName);
  Future<void> trackItemPurchased({
    required String itemId,
    required String itemType,
    required String price,
  });

  /// User tapped a buy button — Google Play sheet is about to open.
  /// Fires before [trackItemPurchased] succeeds; gap between the two events
  /// is the IAP-sheet abandonment funnel stage.
  Future<void> trackPurchaseInitiated({
    required String productId,
    required String productType,
  });

  /// User cancelled the IAP sheet (Google Play returned `userCancelled`).
  Future<void> trackPurchaseCancelled({required String productId});

  /// IAP failed for a reason other than user cancellation (network, billing
  /// error, item unavailable, etc.). [errorCode] is the platform error code
  /// when available.
  Future<void> trackPurchaseFailed({
    required String productId,
    String? errorCode,
  });

  Future<void> trackPremiumSubscriptionStarted();
  Future<void> trackCosmeticEquipped({
    required String cosmeticType,
    required String cosmeticId,
  });
  Future<void> trackThemeSelected(String themeName);

  // ==================== Ads ====================

  /// Load outcomes for one ad [format] since the last report (aggregated
  /// per session, sent when the app is backgrounded). [errorCodes] is
  /// `"code:count,…"`, most frequent first (3 = no fill, 2 = network).
  Future<void> trackAdLoad({
    required String format,
    required int requests,
    required int filled,
    required int failed,
    required String errorCodes,
  });

  /// Revenue AdMob reported for one impression (`onPaidEvent`).
  /// [valueMicros] is in millionths of [currencyCode]; [precision] is the
  /// AdMob precision type (estimated / publisherProvided / precise / unknown).
  Future<void> trackAdRevenue({
    required String format,
    required int valueMicros,
    required String currencyCode,
    required String precision,
  });

  /// How a rewarded ad ended: `completed` (reward earned), `abandoned`
  /// (closed early), `show_failed`, or `not_ready` (asked with nothing
  /// loaded). [placement] names the offer (cap key, or `other`).
  Future<void> trackRewardedResult({
    required String placement,
    required String outcome,
  });

  // ==================== Settings ====================

  Future<void> trackSettingChanged({
    required String settingName,
    required String value,
  });

  // ==================== Social ====================

  Future<void> trackLeaderboardViewed(String type);
  Future<void> trackFriendAdded();
  Future<void> trackFriendRemoved();
  Future<void> trackTournamentEntered({
    required String tournamentId,
    required String tier,
  });
  Future<void> trackReplayViewed();
  Future<void> trackReplayShared();

  // ==================== Engagement ====================

  Future<void> trackDailyBonusCollected();
  Future<void> trackWalkthroughStarted();
  Future<void> trackWalkthroughCompleted();

  /// First-run in-game tutorial (the guided Level 1 beats — distinct
  /// from the home-screen walkthrough above).
  Future<void> trackGameTutorialStarted();
  Future<void> trackGameTutorialCompleted();
  Future<void> trackGameTutorialSkipped();

  /// Fires when ReviewService dispatches a `requestReview()` to the native
  /// platform. [trigger] is the human-readable name of the moment that
  /// caused the request (e.g. `newHighScore`). The platform does not report
  /// whether a dialog actually rendered, so this is the closest signal we
  /// have to "how often do we ask."
  Future<void> trackReviewRequested(String trigger);

  // ==================== First-run funnel ====================
  //
  // install -> first run -> second run, measured with the device-only
  // FirstRunService counters. Fired only inside the onboarding window
  // (first FirstRunService.onboardingGameCount runs).

  /// One step of a first-run guide appeared: a home walkthrough step id
  /// (`home_play`...) or an in-game tutorial beat (`tutorial_steer`...).
  Future<void> trackOnboardingStepShown(String step);

  /// The player finished (or, with [skipped], skipped past) a step.
  Future<void> trackOnboardingStepCompleted(String step, {bool skipped = false});

  /// The very first run on this device started.
  Future<void> trackFirstGameStarted({
    required int secondsSinceInstall,
    required String gameMode,
  });

  /// The second run started: the "came back for more" signal.
  Future<void> trackSecondGameStarted({
    required int secondsSinceInstall,
    required int secondsSinceFirstGame,
  });

  /// One of the onboarding runs ended. [runNumber] is 1-based; [outcome]
  /// is `game_over`, `victory` or `quit`; [eased] says whether the
  /// first-run pressure easing was active.
  Future<void> trackOnboardingRunEnded({
    required int runNumber,
    required String outcome,
    required int score,
    required int levelReached,
    required int levelsCleared,
    required int durationSeconds,
    required bool eased,
  });
}
