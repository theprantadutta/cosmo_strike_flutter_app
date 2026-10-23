import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Subscription tier. `pro` = an active Strike Command subscription (the
/// internal name predates the rebrand and is never shown).
enum PremiumTier { free, pro }

/// Status of the premium cubit
enum PremiumStatus { initial, loading, ready, error }

/// Premium content definition
class PremiumContent {
  /// Sectors that require Strike Command or a purchase to unlock.
  static const Set<GameTheme> premiumThemes = {
    GameTheme.aurora,
    GameTheme.solar,
    GameTheme.abyss,
    GameTheme.ion,
    GameTheme.crimson,
  };

  /// Check if a sector requires Strike Command / a purchase.
  static bool isPremiumTheme(GameTheme theme) => premiumThemes.contains(theme);
}

/// State class for PremiumCubit
class PremiumState extends Equatable {
  final PremiumStatus status;
  final PremiumTier tier;
  final DateTime? subscriptionExpiry;
  final Set<GameTheme> ownedThemes;
  /// Owned livery IDs ([LiveryType.id]).
  final Set<String> ownedSkins;

  /// Owned exhaust IDs ([ExhaustType.id]).
  final Set<String> ownedTrails;
  final Set<String> ownedPowerUps;
  final Set<String> ownedBundles;
  /// Equipped livery ID ([LiveryType.id]).
  final String selectedSkinId;

  /// Equipped exhaust ID ([ExhaustType.id]).
  final String selectedTrailId;
  final String? errorMessage;

  // Tournament entries
  final int bronzeTournamentEntries;
  final int silverTournamentEntries;
  final int goldTournamentEntries;

  // Battle pass
  final bool hasBattlePass;
  final int battlePassTier;

  // Server-side promo (welcome bonus / app-wide giveaway). When `isOnPromo`
  // is true the user has Strike Command for free until `promoExpiresAt`;
  // revocation is handled server-side by the ExpirePromosJob. (This is the
  // only free-subscription mechanism — the old in-app trial was removed.)
  final bool isOnPromo;
  final DateTime? promoExpiresAt;
  final String? promoSource;

  const PremiumState({
    this.status = PremiumStatus.initial,
    this.tier = PremiumTier.free,
    this.subscriptionExpiry,
    this.ownedThemes = const {},
    this.ownedSkins = const {},
    this.ownedTrails = const {},
    this.ownedPowerUps = const {},
    this.ownedBundles = const {},
    this.selectedSkinId = 'standard',
    this.selectedTrailId = 'stock',
    this.errorMessage,
    this.bronzeTournamentEntries = 0,
    this.silverTournamentEntries = 0,
    this.goldTournamentEntries = 0,
    this.hasBattlePass = false,
    this.battlePassTier = 0,
    this.isOnPromo = false,
    this.promoExpiresAt,
    this.promoSource,
  });

  /// Initial state
  factory PremiumState.initial() => const PremiumState();

  /// Create a copy with updated values
  PremiumState copyWith({
    PremiumStatus? status,
    PremiumTier? tier,
    DateTime? subscriptionExpiry,
    Set<GameTheme>? ownedThemes,
    Set<String>? ownedSkins,
    Set<String>? ownedTrails,
    Set<String>? ownedPowerUps,
    Set<String>? ownedBundles,
    String? selectedSkinId,
    String? selectedTrailId,
    String? errorMessage,
    bool clearError = false,
    int? bronzeTournamentEntries,
    int? silverTournamentEntries,
    int? goldTournamentEntries,
    bool? hasBattlePass,
    int? battlePassTier,
    bool? isOnPromo,
    DateTime? promoExpiresAt,
    String? promoSource,
    bool clearPromo = false,
  }) {
    return PremiumState(
      status: status ?? this.status,
      tier: tier ?? this.tier,
      subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
      ownedThemes: ownedThemes ?? this.ownedThemes,
      ownedSkins: ownedSkins ?? this.ownedSkins,
      ownedTrails: ownedTrails ?? this.ownedTrails,
      ownedPowerUps: ownedPowerUps ?? this.ownedPowerUps,
      ownedBundles: ownedBundles ?? this.ownedBundles,
      selectedSkinId: selectedSkinId ?? this.selectedSkinId,
      selectedTrailId: selectedTrailId ?? this.selectedTrailId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      bronzeTournamentEntries:
          bronzeTournamentEntries ?? this.bronzeTournamentEntries,
      silverTournamentEntries:
          silverTournamentEntries ?? this.silverTournamentEntries,
      goldTournamentEntries:
          goldTournamentEntries ?? this.goldTournamentEntries,
      hasBattlePass: hasBattlePass ?? this.hasBattlePass,
      battlePassTier: battlePassTier ?? this.battlePassTier,
      isOnPromo: clearPromo ? false : (isOnPromo ?? this.isOnPromo),
      promoExpiresAt:
          clearPromo ? null : (promoExpiresAt ?? this.promoExpiresAt),
      promoSource: clearPromo ? null : (promoSource ?? this.promoSource),
    );
  }

  /// Whether the premium cubit is initialized
  bool get isInitialized => status == PremiumStatus.ready;

  /// Whether user has active premium
  bool get hasPremium => tier == PremiumTier.pro && !isSubscriptionExpired;

  /// Whether subscription is expired
  bool get isSubscriptionExpired {
    if (subscriptionExpiry == null) return true;
    return DateTime.now().isAfter(subscriptionExpiry!);
  }

  /// "Renews Nov 19, 2026" for an active subscription. Null when there is no
  /// expiry or it is more than 10 years out (operator / lifetime grants),
  /// where a far-future date would only read as a glitch.
  String? get renewalLabel {
    final expiry = subscriptionExpiry;
    if (expiry == null || expiry.isAfter(DateTime.now().add(const Duration(days: 3650)))) {
      return null;
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = expiry.toLocal();
    return 'Renews ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  /// Check if a theme is owned
  bool isThemeOwned(GameTheme theme) => ownedThemes.contains(theme);

  /// Check if a sector is unlocked (free sectors always; premium needs a purchase or Strike Command)
  bool isThemeUnlocked(GameTheme theme) =>
      !PremiumContent.isPremiumTheme(theme) || hasPremium || ownedThemes.contains(theme);

  /// Check if a livery is owned. Strict set-membership only — used by the
  /// purchase-pending reconciler (`_isProductOwned`) where we need to know
  /// whether the IAP grant has landed, independent of Strike Command.
  bool isSkinOwned(String liveryId) => ownedSkins.contains(liveryId);

  /// Check if an exhaust is owned. Same strict-set semantics as [isSkinOwned].
  bool isTrailOwned(String exhaustId) => ownedTrails.contains(exhaustId);

  /// Check if a livery is usable by the player — the free livery always is;
  /// premium liveries unlock through an individual purchase, a Fleet Kit OR
  /// an active Strike Command subscription (which includes every cosmetic,
  /// mirroring the sector fast-path). Use this in UI gating.
  bool isLiveryUnlocked(LiveryType livery) =>
      !livery.isPremium || hasPremium || ownedSkins.contains(livery.id);

  /// Check if an exhaust is usable by the player. Same fast-path as
  /// [isLiveryUnlocked].
  bool isExhaustUnlocked(ExhaustType exhaust) =>
      !exhaust.isPremium || hasPremium || ownedTrails.contains(exhaust.id);

  /// Legacy "unlocked power-up" set (vestigial — gear is a consumable)
  bool isPowerUpUnlocked(String powerUpId) => ownedPowerUps.contains(powerUpId);

  /// Check if a bundle is owned
  bool isBundleOwned(String bundleId) => ownedBundles.contains(bundleId);

  /// Check if user has a Cup Pass of a tier (wire tiers: bronze/silver/gold)
  bool hasTournamentEntry(String tournamentType) {
    switch (tournamentType.toLowerCase()) {
      case 'bronze':
        return bronzeTournamentEntries > 0;
      case 'silver':
        return silverTournamentEntries > 0;
      case 'gold':
        return goldTournamentEntries > 0;
      default:
        return false;
    }
  }

  /// Get Cup Pass count for a tier
  int getTournamentEntryCount(String tournamentType) {
    switch (tournamentType.toLowerCase()) {
      case 'bronze':
        return bronzeTournamentEntries;
      case 'silver':
        return silverTournamentEntries;
      case 'gold':
        return goldTournamentEntries;
      default:
        return 0;
    }
  }

  @override
  List<Object?> get props => [
    status,
    tier,
    subscriptionExpiry,
    ownedThemes,
    ownedSkins,
    ownedTrails,
    ownedPowerUps,
    ownedBundles,
    selectedSkinId,
    selectedTrailId,
    errorMessage,
    bronzeTournamentEntries,
    silverTournamentEntries,
    goldTournamentEntries,
    hasBattlePass,
    battlePassTier,
    isOnPromo,
    promoExpiresAt,
    promoSource,
  ];
}
