import 'package:cosmo_strike_flutter_app/services/comeback_reminder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComebackReminder.fireTime', () {
    test('daytime session fires 20 h later when that is outside quiet hours', () {
      // 15:00 + 20 h = 11:00 next day.
      final fire = ComebackReminder.fireTime(DateTime(2026, 6, 10, 15, 30));
      expect(fire, DateTime(2026, 6, 11, 11, 30));
    });

    test('a fire time in the late evening rolls to 10:00 the next morning', () {
      // 03:00 + 20 h = 23:00 -> 10:00 the following day.
      final fire = ComebackReminder.fireTime(DateTime(2026, 6, 10, 3));
      expect(fire, DateTime(2026, 6, 11, 10));
    });

    test('quiet window starts exactly at 22:00', () {
      // 02:00 + 20 h = 22:00 -> next morning.
      expect(ComebackReminder.fireTime(DateTime(2026, 6, 10, 2)),
          DateTime(2026, 6, 11, 10));
      // 01:59 + 20 h = 21:59 -> unchanged.
      expect(ComebackReminder.fireTime(DateTime(2026, 6, 10, 1, 59)),
          DateTime(2026, 6, 10, 21, 59));
    });

    test('a fire time in the small hours moves to 10:00 the same morning', () {
      // 10:00 + 20 h = 06:00 next day -> 10:00 that day.
      final fire = ComebackReminder.fireTime(DateTime(2026, 6, 10, 10));
      expect(fire, DateTime(2026, 6, 11, 10));
    });

    test('quiet window ends at 09:00', () {
      // 12:59 + 20 h = 08:59 -> 10:00.
      expect(ComebackReminder.fireTime(DateTime(2026, 6, 10, 12, 59)),
          DateTime(2026, 6, 11, 10));
      // 13:00 + 20 h = 09:00 -> unchanged.
      expect(ComebackReminder.fireTime(DateTime(2026, 6, 10, 13)),
          DateTime(2026, 6, 11, 9));
    });

    test('rolls over month and year ends', () {
      // 04:00 Dec 31 + 20 h = 00:00 Jan 1 -> 10:00 Jan 1.
      expect(ComebackReminder.fireTime(DateTime(2026, 12, 31, 4)),
          DateTime(2027, 1, 1, 10));
      // 03:00 Jan 31 + 20 h = 23:00 Jan 31 -> 10:00 Feb 1.
      expect(ComebackReminder.fireTime(DateTime(2027, 1, 31, 3)),
          DateTime(2027, 2, 1, 10));
    });

    test('never fires inside quiet hours and never sooner than 11 h', () {
      final start = DateTime(2026, 6, 1);
      for (var m = 0; m < 24 * 60; m += 7) {
        final from = start.add(Duration(minutes: m));
        final fire = ComebackReminder.fireTime(from);
        expect(fire.hour >= ComebackReminder.quietEndHour, isTrue, reason: '$from');
        expect(fire.hour < ComebackReminder.quietStartHour, isTrue, reason: '$from');
        expect(fire.difference(from) >= const Duration(hours: 11), isTrue,
            reason: '$from');
      }
    });
  });

  group('ComebackReminder copy', () {
    test('quotes the best score with digit grouping', () {
      expect(ComebackReminder.body(12480),
          'Best run on file: 12,480. Launch and top it.');
      expect(ComebackReminder.groupDigits(999), '999');
      expect(ComebackReminder.groupDigits(1000000), '1,000,000');
    });

    test('falls back to the Daily Run line without a score', () {
      expect(ComebackReminder.body(0), "Today's Daily Run is live. Launch when ready.");
    });

    test('follows the 3.2 copy rules (no emoji, no Snake vocabulary)', () {
      final all = '${ComebackReminder.title} ${ComebackReminder.body(5)} '
              '${ComebackReminder.body(0)}'
          .toLowerCase();
      for (final banned in ['snake', 'food', 'eat', 'coins', 'trophies']) {
        expect(all.contains(banned), isFalse, reason: banned);
      }
      expect(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true).hasMatch(all),
          isFalse);
    });
  });
}
