import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';

/// Status of the battle pass cubit
enum BattlePassStatus { initial, loading, ready, error }

/// Battle pass reward tier
enum RewardTier { free, premium }

/// State class for BattlePassCubit
class BattlePassState extends Equatable {
  final BattlePassStatus status;
  final bool isActive;
  final int currentTier;
  final int currentXP;
  final int xpForNextTier;
  final DateTime? expiryDate;
  final Set<int> claimedFreeTiers;
  final Set<int> claimedPremiumTiers;
  final String? errorMessage;
  final String seasonName;
  final BattlePassSeason? season;

  const BattlePassState({
    this.status = BattlePassStatus.initial,
    this.isActive = false,
    this.currentTier = 0,
    this.currentXP = 0,
    this.xpForNextTier = 100,
    this.expiryDate,
    this.claimedFreeTiers = const {},
    this.claimedPremiumTiers = const {},
    this.errorMessage,
    this.seasonName = 'Season 1',
    this.season,
  });

  /// Initial state
  factory BattlePassState.initial() => const BattlePassState();

  /// Create a copy with updated values
  BattlePassState copyWith({
    BattlePassStatus? status,
    bool? isActive,
    int? currentTier,
    int? currentXP,
    int? xpForNextTier,
    DateTime? expiryDate,
    Set<int>? claimedFreeTiers,
    Set<int>? claimedPremiumTiers,
    String? errorMessage,
    bool clearError = false,
    String? seasonName,
    BattlePassSeason? season,
  }) {
    return BattlePassState(
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      currentTier: currentTier ?? this.currentTier,
      currentXP: currentXP ?? this.currentXP,
      xpForNextTier: xpForNextTier ?? this.xpForNextTier,
      expiryDate: expiryDate ?? this.expiryDate,
      claimedFreeTiers: claimedFreeTiers ?? this.claimedFreeTiers,
      claimedPremiumTiers: claimedPremiumTiers ?? this.claimedPremiumTiers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      seasonName: seasonName ?? this.seasonName,
      season: season ?? this.season,
    );
  }

  /// Whether battle pass is expired. [expiryDate] is only populated from saved
  /// data and is frequently null (it was never derived from the season), so we
  /// fall back to the live season's end date. Without this fallback a null
  /// expiry reads as "expired", which makes [isValid] false and silently
  /// rejects every premium reward claim even though the season is live.
  bool get isExpired {
    final expiry = expiryDate ?? season?.endDate;
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  /// Whether battle pass is valid (active and not expired)
  bool get isValid => isActive && !isExpired;

  /// Progress to next tier (0.0 to 1.0)
  double get tierProgress {
    if (xpForNextTier <= 0) return 1.0;
    return (currentXP / xpForNextTier).clamp(0.0, 1.0);
  }

  /// Check if a free tier reward is claimed
  bool isFreeTierClaimed(int tier) => claimedFreeTiers.contains(tier);

  /// Check if a premium tier reward is claimed
  bool isPremiumTierClaimed(int tier) => claimedPremiumTiers.contains(tier);

  /// Maximum tier level (derived from season if available)
  int get maxTier => season?.levels.length ?? 100;

  /// XP required per tier (can be customized)
  int xpRequiredForTier(int tier) {
    // Base: 100 XP, increasing by 50 per tier
    return 100 + (tier * 50);
  }

  @override
  List<Object?> get props => [
    status,
    isActive,
    currentTier,
    currentXP,
    xpForNextTier,
    expiryDate,
    claimedFreeTiers,
    claimedPremiumTiers,
    errorMessage,
    seasonName,
    season,
  ];
}
