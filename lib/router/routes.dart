/// Route path constants for type-safe navigation with GoRouter.
abstract class AppRoutes {
  // Core routes
  static const String loading = '/';
  static const String firstTimeAuth = '/first-time-auth';
  static const String privacyConsent = '/privacy-consent';
  static const String emailAuth = '/email-auth';
  static const String usernameSetup = '/username-setup';
  static const String home = '/home';

  // Game flow
  static const String playLoading = '/play-loading';
  static const String game = '/game';
  static const String gameOver = '/game-over';

  // Profile & Stats
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String statistics = '/statistics';
  static const String achievements = '/achievements';

  // Social & Competitive
  static const String leaderboard = '/leaderboard';
  static const String friendsLeaderboard = '/friends-leaderboard';
  static const String friends = '/friends';
  static const String tournaments = '/tournaments';
  static const String tournamentDetail = '/tournaments/:id';

  // Helper to generate tournament detail path with ID
  static String tournamentDetailPath(String id) => '/tournaments/$id';

  // Monetization
  static const String store = '/store';
  static const String premiumBenefits = '/premium-benefits';
  static const String cosmetics = '/cosmetics';
  static const String battlePass = '/battle-pass';

  // Other features
  static const String dailyChallenges = '/daily-challenges';
  static const String weeklyQuests = '/weekly-quests';
  static const String instructions = '/instructions';
  static const String replays = '/replays';
  static const String replayViewer = '/replays/:id';

  // Helper to generate replay viewer path with ID
  static String replayViewerPath(String id) => '/replays/$id';

  // Multiplayer
  static const String multiplayerLobby = '/multiplayer';
  static const String multiplayerLobbyWithId = '/multiplayer/:gameId';
  static const String multiplayerGame = '/multiplayer/game';

  // Helper to generate multiplayer lobby path with game ID
  static String multiplayerLobbyPath(String gameId) => '/multiplayer/$gameId';
}
