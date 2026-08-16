class NumberFormatHelper {
  static String percent(dynamic value) =>
      '${(double.tryParse('$value') ?? 0) * 100}%';
}

/// API payloads may represent PostgreSQL decimals as either JSON numbers or
/// strings. Keep presentation code tolerant of both representations.
double? asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

int? asInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

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

String formatProposalDeadline(Map<String, dynamic> deadline) {
  final day = deadline['gameDay'] ?? deadline['game_day'] ?? '—';
  final minute = asInt(deadline['gameMinute'] ?? deadline['game_minute']);
  final remaining = asInt(
      deadline['realSecondsRemaining'] ?? deadline['real_seconds_remaining']);
  final clock = minute == null
      ? '—'
      : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  final seconds = remaining ?? 0;
  final duration = seconds >= 86400
      ? '${seconds ~/ 86400}d ${(seconds % 86400) ~/ 3600}h'
      : seconds >= 3600
          ? '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m'
          : '${seconds ~/ 60}m';
  return 'Closes game day $day at $clock · in $duration real time';
}
