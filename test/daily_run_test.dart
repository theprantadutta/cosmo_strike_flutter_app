import 'package:cosmo_strike_flutter_app/services/daily_run_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the daily seed is stable within a UTC day and changes at midnight', () {
    final a = DailyRunService.todaySeed(DateTime.utc(2026, 10, 14, 0, 0, 1));
    final b = DailyRunService.todaySeed(DateTime.utc(2026, 10, 14, 23, 59, 59));
    final c = DailyRunService.todaySeed(DateTime.utc(2026, 10, 15));
    expect(a, b);
    expect(c, a + 1);
  });
}
