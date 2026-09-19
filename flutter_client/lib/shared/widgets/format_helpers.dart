class NumberFormatHelper {
  static String percent(dynamic value) =>
      '${(double.tryParse('$value') ?? 0) * 100}%';
}

/// Formats values from the canonical V5 Constitution read model.
///
/// Constitution values are typed by the server. In particular, rates are
/// basis points and monetary values are atomic CREDIT units; neither should
/// be passed through a generic percentage or number formatter.
class ConstitutionValueFormatter {
  static String format(dynamic value, dynamic valueType,
      {String fallback = 'UNAVAILABLE'}) {
    if (value == null) return fallback;
    final type = valueType?.toString().trim().toUpperCase();
    switch (type) {
      case 'RATE_BPS':
        return _formatBasisPoints(value, fallback);
      case 'CREDIT_UNITS':
        return formatCreditUnits(value, fallback: fallback);
      case 'GAME_DAYS':
        final days = _integer(value);
        if (days == null) return fallback;
        return '$days game day${days == '1' ? '' : 's'}';
      case 'ENUM':
        return _humanize(value.toString());
      case 'BOOLEAN':
        if (value is bool) return value ? 'ON' : 'OFF';
        return value.toString().toLowerCase() == 'true' ? 'ON' : 'OFF';
      case 'PROGRESSIVE_SCHEDULE_REF':
        return 'SCHEDULE PUBLISHED';
      case 'INTEGER':
      case 'RESOURCE_UNITS':
        return _integer(value) ?? fallback;
      default:
        if (value is Map || value is List) return 'SCHEDULE PUBLISHED';
        return value.toString();
    }
  }

  static String _formatBasisPoints(dynamic value, String fallback) {
    final bps = _bigInt(value);
    if (bps == null) return fallback;
    final negative = bps.isNegative;
    final absolute = bps.abs();
    final whole = absolute ~/ BigInt.from(100);
    final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
    return '${negative ? '-' : ''}$whole.$fraction%';
  }

  static BigInt? _bigInt(dynamic value) {
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return BigInt.tryParse(raw);
  }

  static String? _integer(dynamic value) => _bigInt(value)?.toString();

  static String _humanize(String value) => value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) =>
          '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
      .join(' ');
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

/// Formats an atomic CREDIT balance where 100 units equal 1.00 C.
///
/// Monetary API values must remain integers/strings all the way to the
/// presentation boundary. This avoids losing precision when balances exceed
/// the exact integer range of a JavaScript number or are represented by a
/// PostgreSQL BIGINT string.
String formatCreditUnits(dynamic value, {String fallback = 'UNAVAILABLE'}) {
  if (value == null) return fallback;
  final raw = value.toString().trim();
  if (raw.isEmpty) return fallback;
  final negative = raw.startsWith('-');
  final unsigned =
      (raw.startsWith('-') || raw.startsWith('+')) ? raw.substring(1) : raw;
  final units = BigInt.tryParse(unsigned);
  if (units == null) return fallback;
  final absolute = units.abs();
  final whole = absolute ~/ BigInt.from(100);
  final cents = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$cents C';
}

/// Formats an exact quantity according to its authoritative asset kind.
/// CREDIT values are atomic cents; resources are integer quantity units.
/// Neither path converts through double.
String formatAssetQuantity(String assetCode, dynamic value,
    {String fallback = 'UNAVAILABLE'}) {
  if (assetCode.toUpperCase() == 'CREDIT') {
    return formatCreditUnits(value, fallback: fallback);
  }
  if (value == null) return fallback;
  final raw = value.toString().trim();
  final units = BigInt.tryParse(raw);
  if (units == null) return fallback;
  return units.toString();
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
  final calculatedRemaining =
      closesAt?.difference(now ?? DateTime.now()).inSeconds.ceil();
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

/// Converts a real-world UTC/ISO date into an in-game simulated timestamp:
/// Epoch start: 2026-01-01 00:00:00 UTC (1 real second = 1 game minute).
String formatRealToGameDateTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'unknown';
  final epochStart = DateTime.utc(2026, 1, 1, 0, 0, 0);
  final diffMs =
      parsed.toUtc().millisecondsSinceEpoch - epochStart.millisecondsSinceEpoch;
  final totalGameMinutes = diffMs > 0 ? (diffMs ~/ 1000) : 0;
  final gameDay = (totalGameMinutes ~/ 1440) + 1;
  final gameMinute = totalGameMinutes % 1440;
  return formatGameDateTime(gameDay, gameMinute);
}
