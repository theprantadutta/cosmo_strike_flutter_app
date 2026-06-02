import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';

/// Status of the coins cubit
enum CoinsStatus { initial, loading, ready, error }

/// State class for CoinsCubit
class CoinsState extends Equatable {
  final CoinsStatus status;
  final CoinBalance balance;
  final List<CoinTransaction> transactions;
  // Snapshot of the current 7-day cycle. Each entry's [isCollected] /
  // [collectedAt] mirrors the Drift `daily_bonus_state.weeklyClaimsJson`
  // map — the popup grid reads this directly.
  final List<DailyLoginBonus> dailyBonuses;
  final double earningMultiplier;
  final bool hasPremiumBonus;
  final String? errorMessage;

  /// Daily earning cap tracking
  final int dailyEarnings;
  final DateTime lastEarningReset;

  /// UTC moment of the most recent daily bonus claim, ms since epoch.
  /// Null means "never claimed." Mirrored from
  /// `daily_bonus_state.lastClaimUtcMs`.
  final int? dailyBonusLastClaimUtcMs;

  /// Tz offset (minutes east of UTC) that was in effect when the most
  /// recent claim happened. Snapshotted at claim time so the gate can
  /// replay the user-local day boundary even if the device's tz has
  /// changed since.
  final int? dailyBonusLastClaimTzOffsetMinutes;

  /// Server-confirmed (or local) current streak length. Used to compute
  /// [nextClaimDay].
  final int dailyBonusCurrentStreak;

  const CoinsState({
    this.status = CoinsStatus.initial,
    required this.balance,
    this.transactions = const [],
    this.dailyBonuses = const [],
    this.earningMultiplier = 1.0,
    this.hasPremiumBonus = false,
    this.errorMessage,
    this.dailyEarnings = 0,
    required this.lastEarningReset,
    this.dailyBonusLastClaimUtcMs,
    this.dailyBonusLastClaimTzOffsetMinutes,
    this.dailyBonusCurrentStreak = 0,
  });

  /// Initial state
  factory CoinsState.initial() => CoinsState(
    balance: CoinBalance.initial,
    dailyBonuses: DailyLoginBonus.getWeeklyBonuses(),
    lastEarningReset: DateTime.now().toUtc(),
  );

  /// Create a copy with updated values
  CoinsState copyWith({
    CoinsStatus? status,
    CoinBalance? balance,
    List<CoinTransaction>? transactions,
    List<DailyLoginBonus>? dailyBonuses,
    double? earningMultiplier,
    bool? hasPremiumBonus,
    String? errorMessage,
    bool clearError = false,
    int? dailyEarnings,
    DateTime? lastEarningReset,
    // Nullable fields use a "set" + sentinel pattern via dedicated bools so
    // callers can explicitly null them; for our use we never need to null,
    // only set, so a plain optional override suffices.
    int? dailyBonusLastClaimUtcMs,
    int? dailyBonusLastClaimTzOffsetMinutes,
    int? dailyBonusCurrentStreak,
  }) {
    return CoinsState(
      status: status ?? this.status,
      balance: balance ?? this.balance,
      transactions: transactions ?? this.transactions,
      dailyBonuses: dailyBonuses ?? this.dailyBonuses,
      earningMultiplier: earningMultiplier ?? this.earningMultiplier,
      hasPremiumBonus: hasPremiumBonus ?? this.hasPremiumBonus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      dailyEarnings: dailyEarnings ?? this.dailyEarnings,
      lastEarningReset: lastEarningReset ?? this.lastEarningReset,
      dailyBonusLastClaimUtcMs:
          dailyBonusLastClaimUtcMs ?? this.dailyBonusLastClaimUtcMs,
      dailyBonusLastClaimTzOffsetMinutes: dailyBonusLastClaimTzOffsetMinutes ??
          this.dailyBonusLastClaimTzOffsetMinutes,
      dailyBonusCurrentStreak:
          dailyBonusCurrentStreak ?? this.dailyBonusCurrentStreak,
    );
  }

  /// Daily earning cap (150 for free users, 250 for premium)
  int get dailyEarningCap => hasPremiumBonus ? 250 : 150;

  /// Remaining earnings allowed today
  int get remainingDailyEarnings => (dailyEarningCap - dailyEarnings).clamp(0, dailyEarningCap);

  /// Whether daily cap has been reached
  bool get dailyCapReached => dailyEarnings >= dailyEarningCap;

  /// Whether the coins system is ready
  bool get isReady => status == CoinsStatus.ready;

  /// Total coin balance
  int get total => balance.total;

  /// Recent transactions (last 50)
  List<CoinTransaction> get recentTransactions =>
      transactions.take(50).toList();

  /// Today's earnings
  int get todaysEarnings {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return transactions
        .where((t) => t.isEarned && t.timestamp.isAfter(startOfDay))
        .fold(0, (sum, t) => sum + t.amount);
  }

  /// Whether the daily bonus was already claimed today in the user's
  /// local-tz day. Both the gate (here) and the claim path (DAO) use
  /// the same `userLocalDay(utc, tzMin)` math contract, so this stays
  /// in lock-step with what's persisted.
  bool get wasDailyBonusClaimedToday {
    final claimMs = dailyBonusLastClaimUtcMs;
    if (claimMs == null) return false;
    final lastUtc = DateTime.fromMillisecondsSinceEpoch(claimMs, isUtc: true);
    final lastLocal = _userLocalDay(
      lastUtc,
      dailyBonusLastClaimTzOffsetMinutes ?? 0,
    );
    final nowTzMin = DateTime.now().timeZoneOffset.inMinutes;
    final todayLocal = _userLocalDay(DateTime.now().toUtc(), nowTzMin);
    return lastLocal == todayLocal;
  }

  /// Check if user can collect daily login bonus
  bool get canCollectDailyBonus => !wasDailyBonusClaimedToday;

  /// Day of the 7-day cycle (1-7) the next claim would land on.
  /// - First-ever claim → 1.
  /// - Yesterday's claim → currentStreak + 1, wrapping every 7.
  /// - Older / never claimed → resets to 1 (gap broke the streak).
  /// - Already claimed today → unused (gated by [canCollectDailyBonus]).
  int get nextClaimDay {
    final claimMs = dailyBonusLastClaimUtcMs;
    if (claimMs == null) return 1;
    final lastUtc = DateTime.fromMillisecondsSinceEpoch(claimMs, isUtc: true);
    final lastLocal = _userLocalDay(
      lastUtc,
      dailyBonusLastClaimTzOffsetMinutes ?? 0,
    );
    final nowTzMin = DateTime.now().timeZoneOffset.inMinutes;
    final todayLocal = _userLocalDay(DateTime.now().toUtc(), nowTzMin);
    final yesterdayLocal = _addDaysToIsoDate(todayLocal, -1);
    if (lastLocal == yesterdayLocal) {
      final newStreak = dailyBonusCurrentStreak + 1;
      return ((newStreak - 1) % 7) + 1;
    }
    return 1;
  }

  /// Get available daily bonus — the row that would be claimed if the
  /// user taps Claim now. Returns null when [canCollectDailyBonus] is
  /// false.
  DailyLoginBonus? get availableDailyBonus {
    if (wasDailyBonusClaimedToday) return null;
    final templates = DailyLoginBonus.getWeeklyBonuses();
    final dayIndex = nextClaimDay - 1;
    if (dayIndex < 0 || dayIndex >= templates.length) return null;
    final t = templates[dayIndex];
    return DailyLoginBonus(
      day: t.day,
      coins: t.coins,
      bonusItem: t.bonusItem,
      isCollected: false,
    );
  }

  /// Check if user can afford a specific amount
  bool canAfford(int amount) => balance.total >= amount;

  /// Shared math contract with the DAO + backend handler.
  static String _userLocalDay(DateTime utc, int tzOffsetMinutes) {
    final local = utc.add(Duration(minutes: tzOffsetMinutes));
    return local.toIso8601String().substring(0, 10);
  }

  static String _addDaysToIsoDate(String isoDate, int days) {
    final dt = DateTime.parse(isoDate);
    return dt.add(Duration(days: days)).toIso8601String().substring(0, 10);
  }

  @override
  List<Object?> get props => [
    status,
    balance,
    transactions,
    dailyBonuses,
    earningMultiplier,
    hasPremiumBonus,
    errorMessage,
    dailyEarnings,
    lastEarningReset,
    dailyBonusLastClaimUtcMs,
    dailyBonusLastClaimTzOffsetMinutes,
    dailyBonusCurrentStreak,
  ];
}
