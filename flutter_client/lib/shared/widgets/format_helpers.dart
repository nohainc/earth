class NumberFormatHelper {
  static String percent(dynamic value) =>
      '${(double.tryParse('$value') ?? 0) * 100}%';
}

/// API payloads may represent PostgreSQL decimals as either JSON numbers or
/// strings. Keep presentation code tolerant of both representations.
double? asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

double asDoubleOr(dynamic value, double fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  final d = double.tryParse(value.toString());
  return d ?? fallback;
}

int? asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

int asIntOr(dynamic value, int fallback) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  final i = int.tryParse(value.toString());
  if (i != null) return i;
  final d = double.tryParse(value.toString());
  if (d != null) return d.toInt();
  return fallback;
}

String formatWholeNumber(dynamic value, {String fallback = '0'}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt().toString();
  final s = value.toString().trim();
  final d = double.tryParse(s);
  if (d != null) return d.toInt().toString();
  return s.isEmpty ? fallback : s;
}

String formatCreditsAmount(dynamic value) {
  return '${formatWholeNumber(value)} C';
}

String formatPercent(dynamic value) {
  final number = value is num ? value.toDouble() : 0.0;
  return '${(number.clamp(0, 1) * 100).round()}%';
}

String formatSecurityDate(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'unknown';
  return parsed
      .toLocal()
      .toIso8601String()
      .replaceFirst('T', ' ')
      .split('.')
      .first;
}

String formatProposalDeadline(Map<String, dynamic> deadline, {DateTime? now}) {
  final day = deadline['gameDay'] ?? deadline['game_day'] ?? '—';
  final minute = asInt(deadline['gameMinute'] ?? deadline['game_minute']);
  final closesAt = DateTime.tryParse(deadline['closesAt']?.toString() ??
      deadline['closes_at']?.toString() ??
      '');
  final snapshotRemaining = asInt(
      deadline['realSecondsRemaining'] ?? deadline['real_seconds_remaining']);
  final calculatedRemaining = closesAt == null
      ? null
      : closesAt.difference(now ?? DateTime.now()).inSeconds.ceil();
  final seconds =
      (calculatedRemaining ?? snapshotRemaining ?? 0).clamp(0, 365 * 86400);
  final gameDate = minute == null
      ? 'GAME DAY $day'
      : formatGameDateTime(asIntOr(day, 1), minute);
  final duration = seconds >= 86400
      ? '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h'
      : seconds >= 3600
          ? '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m'
          : '${seconds ~/ 60}m';
  return 'Closes $gameDate · in $duration real time';
}

/// Formats a World timestamp consistently with the global HUD.
/// Game days are one-based; every fifth year contains 366 days.
String formatGameDateTime(int gameDay, int gameMinute) {
  var daysLeft = gameDay <= 0 ? 0 : gameDay - 1;
  var year = 1;
  while (true) {
    final daysInYear = year % 5 == 0 ? 366 : 365;
    if (daysLeft < daysInYear) break;
    daysLeft -= daysInYear;
    year++;
  }
  final minuteOfDay = gameMinute.clamp(0, 1439);
  final hour = minuteOfDay ~/ 60;
  final minute = minuteOfDay % 60;
  return 'YEAR $year   DAY ${daysLeft + 1}   '
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Formats a duration in game minutes into a concise humanized string.
String formatGameDuration(int minutes) {
  if (minutes < 60) {
    return '$minutes min${minutes == 1 ? '' : 's'}';
  } else if (minutes < 1440) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h hr${h == 1 ? '' : 's'}' : '${h}h ${m}m';
  } else {
    final d = minutes ~/ 1440;
    final h = (minutes % 1440) ~/ 60;
    return h == 0 ? '$d day${d == 1 ? '' : 's'}' : '${d}d ${h}h';
  }
}
