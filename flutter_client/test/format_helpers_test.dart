import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  test('formatPercent formats decimal values and clamps bounds', () {
    expect(formatPercent(0.5), '50%');
    expect(formatPercent(1.0), '100%');
    expect(formatPercent(0), '0%');
    expect(formatPercent(1.5), '100%');
    expect(formatPercent(-0.2), '0%');
    expect(formatPercent('invalid'), '0%');
  });

  test('formatSecurityDate converts timestamps to local ISO string', () {
    expect(formatSecurityDate(null), 'unknown');
    expect(formatSecurityDate('invalid-date'), 'unknown');
    final formatted = formatSecurityDate('2026-08-16T12:00:00.000Z');
    expect(formatted.contains('2026-08-16'), true);
  });

  test('formatProposalDeadline formats game day, minute, and real-time durations', () {
    final deadlineDays = {
      'gameDay': 185,
      'gameMinute': 720,
      'realSecondsRemaining': 90000,
    };
    expect(formatProposalDeadline(deadlineDays).contains('Closes game day 185 at 12:00'), true);
    expect(formatProposalDeadline(deadlineDays).contains('1d 1h'), true);

    final deadlineHours = {
      'game_day': 186,
      'game_minute': 60,
      'real_seconds_remaining': 7200,
    };
    expect(formatProposalDeadline(deadlineHours).contains('Closes game day 186 at 01:00'), true);
    expect(formatProposalDeadline(deadlineHours).contains('2h 0m'), true);

    final deadlineMinutes = {
      'gameDay': 187,
      'gameMinute': 0,
      'realSecondsRemaining': 600,
    };
    expect(formatProposalDeadline(deadlineMinutes).contains('10m'), true);
  });

  test('NumberFormatHelper formats percent strings', () {
    expect(NumberFormatHelper.percent(0.25), '25.0%');
    expect(NumberFormatHelper.percent('invalid'), '0.0%');
  });
}
