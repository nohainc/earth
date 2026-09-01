import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

class PersonalFinancePanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> personalFinanceData;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const PersonalFinancePanel(
      {super.key,
      this.panelKey,
      required this.state,
      required this.busy,
      this.personalFinanceData = const {},
      required this.action});

  @override
  Widget build(BuildContext context) {
    final maintenance = _map(personalFinanceData['lifeMaintenance']);
    final dailyProfile = _map(personalFinanceData['dailyProfile']);
    final lastSettlement = _map(maintenance['lastSettlement']);
    final taxes = _map(personalFinanceData['taxes']);
    final taxRules = (taxes['rules'] as List? ?? const [])
        .whereType<Map>()
        .map((rule) => Map<String, dynamic>.from(rule))
        .toList();
    final viewerId = state.human['id']?.toString();
    final privateBuildings = state.buildings
        .whereType<Map>()
        .where((building) =>
            building['ownership_class']?.toString() == 'private' &&
            building['owner_id']?.toString() == viewerId &&
            building['status']?.toString() != 'closed')
        .map((building) => Map<String, dynamic>.from(building))
        .toList();
    final publicBuildings = state.buildings
        .whereType<Map>()
        .where((building) =>
            building['ownership_class']?.toString() == 'public_investment' &&
            building['status']?.toString() != 'closed')
        .map((building) => Map<String, dynamic>.from(building))
        .toList();
    final investmentDividend = _investmentDividend(
        publicBuildings,
        state.investmentShares
            .whereType<Map>()
            .map((share) => Map<String, dynamic>.from(share))
            .toList());
    final buildingChange = _buildingResourceChange(privateBuildings);
    final preparedBuildingChange = dailyProfile['status'] == 'clean'
        ? _profileChange(dailyProfile)
        : buildingChange;
    final basicRule = taxRules
        .where((rule) => rule['category']?.toString() == 'basic_income')
        .firstOrNull;
    final basicRate = asDoubleOr(basicRule?['rate'], 0);
    final grossCredits =
        preparedBuildingChange['credits']! + investmentDividend;
    final incomeTax = grossCredits > 0 ? grossCredits * basicRate : 0.0;
    final maintenanceChange = _maintenanceResourceChange(lastSettlement);
    final finalChange = _addChanges(
        _addChanges(preparedBuildingChange, {'credits': investmentDividend}),
        _addChanges(maintenanceChange, {'credits': -incomeTax}));
    final unpaid = asDoubleOr(maintenance['unpaidTotal'], 0);
    final protected = asDoubleOr(
        _map(personalFinanceData['protectedMinimum'])['credits'], 100);
    final statusColor = unpaid > 0 ? Colors.orangeAccent : cyanAccentColor;

    return EarthPanel(
      key: panelKey,
      title: 'PERSONAL FINANCE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          'A clear daily statement of your personal income, tax, essential resources, and resulting change.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('PERSONAL FINANCE', style: _headingStyle),
          const Spacer(),
          _statusPill(unpaid > 0 ? 'NEEDS ATTENTION' : 'ON TRACK', statusColor)
        ]),
        const SizedBox(height: 22),
        const Text('DAILY INCOME', style: _sectionStyle),
        const SizedBox(height: 8),
        _creditRow('Private buildings', preparedBuildingChange['credits']!,
            positive: true),
        _creditRow('Investment dividend', investmentDividend,
            positive: true, displayAsWhole: true),
        _creditRow('Gross credit income', grossCredits,
            positive: true, emphasis: true),
        const SizedBox(height: 20),
        const Text('ESTIMATED TAX ON THIS INCOME', style: _sectionStyle),
        const SizedBox(height: 8),
        _taxRow(basicRate, incomeTax),
        const SizedBox(height: 7),
        _creditRow('Net credit income', grossCredits - incomeTax,
            positive: grossCredits - incomeTax > 0, emphasis: true),
        const SizedBox(height: 24),
        if (privateBuildings.isNotEmpty) ...[
          const Text('FROM PRIVATE BUILDINGS', style: _sectionStyle),
          const SizedBox(height: 8),
          _resourceLine(_withoutZeroes(
              Map<String, double>.from(preparedBuildingChange)
                ..remove('credits'))),
          const SizedBox(height: 24),
        ],
        const Text('LIFE MAINTENANCE', style: _sectionStyle),
        const SizedBox(height: 8),
        _resourceLine(_withoutZeroes(maintenanceChange)),
        if (unpaid > 0) ...[
          const SizedBox(height: 10),
          _notice(Icons.warning_amber_rounded, Colors.orangeAccent,
              '${_credits(unpaid)} of essential costs remain unpaid.'),
        ],
        const SizedBox(height: 24),
        const Text('YOUR DAILY RESULT', style: _sectionStyle),
        const SizedBox(height: 8),
        _resourceLine(_withoutZeroes(finalChange), emphasize: true),
        const SizedBox(height: 24),
        _notice(Icons.shield_outlined, violetColor,
            'Protected reserve: ${_credits(protected)}. Essential shortfalls are recorded; they do not remove you from the game.'),
      ]),
    );
  }

  static const _headingStyle = TextStyle(
      color: mutedColor,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1);
  static const _sectionStyle = TextStyle(
      color: mutedColor,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .6);
  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  static Map<String, double> _profileChange(Map<String, dynamic> profile) => {
        'credits': asDoubleOr(profile['credits_delta'], 0),
        'energy': asDoubleOr(profile['energy_delta'], 0),
        'food': asDoubleOr(profile['food_delta'], 0),
        'materials': asDoubleOr(profile['materials_delta'], 0),
        'components': asDoubleOr(profile['components_delta'], 0),
        'compute': asDoubleOr(profile['compute_delta'], 0),
      };
  static String _number(double value) => value.abs() >= 100
      ? value.abs().toStringAsFixed(0)
      : value
          .abs()
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  static String _credits(double value) => '${_number(value)} C';

  static Widget _creditRow(String label, double value,
          {required bool positive,
          bool emphasis = false,
          bool displayAsWhole = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: emphasis ? inkColor : mutedColor,
                      fontSize: emphasis ? 13 : 11,
                      fontWeight:
                          emphasis ? FontWeight.w800 : FontWeight.w600))),
          Icon(Icons.account_balance_wallet_outlined,
              size: emphasis ? 17 : 15, color: EarthResourceColors.credits),
          const SizedBox(width: 5),
          Text(
              '${positive && value > 0 ? '+' : value < 0 ? '-' : ''}${displayAsWhole ? value.abs().round() : _number(value)} C',
              style: TextStyle(
                  color: value < 0
                      ? Colors.redAccent
                      : value > 0
                          ? Colors.tealAccent
                          : mutedColor,
                  fontSize: emphasis ? 14 : 12,
                  fontWeight: FontWeight.w800)),
        ]),
      );

  static Widget _taxRow(double rate, double amount) => Row(children: [
        const Expanded(
            child: Text('Basic income tax',
                style: TextStyle(color: mutedColor, fontSize: 11))),
        Text('${(rate * 100).toStringAsFixed(2)}%',
            style: const TextStyle(color: mutedColor, fontSize: 11)),
        const SizedBox(width: 14),
        Text('−${_credits(amount)}',
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w800)),
      ]);

  static Map<String, double> _emptyChanges() => {
        'credits': 0,
        'energy': 0,
        'food': 0,
        'materials': 0,
        'components': 0,
        'compute': 0
      };
  static Map<String, double> _addChanges(
      Map<String, double> left, Map<String, double> right) {
    final result = _emptyChanges();
    for (final key in result.keys) {
      result[key] = (left[key] ?? 0) + (right[key] ?? 0);
    }
    return result;
  }

  static Map<String, double> _withoutZeroes(Map<String, double> values) =>
      Map.fromEntries(values.entries.where((entry) => entry.value != 0));

  static Map<String, double> _buildingResourceChange(
      List<Map<String, dynamic>> buildings) {
    final changes = _emptyChanges();
    for (final building in buildings) {
      final policy = building['operating_policy']?.toString() ?? 'balanced';
      final outputMultiplier = policy == 'high_output'
          ? 1.3
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? .75
              : 1.0;
      final costMultiplier = policy == 'high_output'
          ? 1.4
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? .7
              : 1.0;
      final output =
          asDoubleOr(building['resource_output_amount'], 0) * outputMultiplier;
      final outputType =
          building['resource_output_type']?.toString() ?? 'credits';
      changes[outputType] = (changes[outputType] ?? 0) + output;
      changes['credits'] = changes['credits']! -
          asDoubleOr(building['daily_operating_credits'], 0) * costMultiplier;
      final condition = asDoubleOr(building['condition'], 100);
      final conditionCostMultiplier = condition >= 80
          ? 1.0
          : condition >= 50
              ? 1.15
              : condition >= 20
                  ? 1.4
                  : 2.0;
      final autoRepair = building['auto_repair_enabled'] == true ||
          building['auto_repair_enabled']?.toString() == 'true';
      final repairResource = building['ownership_class']?.toString() == 'civic'
          ? 'materials'
          : 'components';
      for (final key in [
        'energy',
        'food',
        'materials',
        'components',
        'compute'
      ]) {
        changes[key] = changes[key]! -
            asDoubleOr(building['upkeep_$key'], 0) *
                costMultiplier *
                conditionCostMultiplier -
            (autoRepair && key == repairResource ? 1 : 0);
      }
    }
    return changes;
  }

  static Map<String, double> _maintenanceResourceChange(
          Map<String, dynamic> settlement) =>
      {
        'credits': -asDoubleOr(settlement['credits_for_resources'], 0),
        'energy':
            -asDoubleOr(settlement['energy_used'], settlement.isEmpty ? 1 : 0),
        'food':
            -asDoubleOr(settlement['food_used'], settlement.isEmpty ? 1 : 0),
        'compute': -asDoubleOr(
            settlement['compute_used'], settlement.isEmpty ? .25 : 0),
      };

  static double _investmentDividend(
      List<Map<String, dynamic>> buildings, List<Map<String, dynamic>> shares) {
    var total = 0.0;
    for (final building in buildings) {
      final holding = shares
          .where((share) =>
              share['building_id']?.toString() == building['id']?.toString())
          .firstOrNull;
      if (holding == null) continue;
      final policy = building['operating_policy']?.toString() ?? 'balanced';
      final yieldMultiplier = policy == 'high_output'
          ? 1.3
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? .75
              : 1.0;
      final costMultiplier = policy == 'high_output'
          ? 1.4
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? .7
              : 1.0;
      final condition = asDoubleOr(building['condition'], 100);
      final conditionCostMultiplier = condition >= 80
          ? 1.0
          : condition >= 50
              ? 1.15
              : condition >= 20
                  ? 1.4
                  : 2.0;
      final gross =
          asDoubleOr(building['resource_output_amount'], 0) * yieldMultiplier;
      final cost = asDoubleOr(building['daily_operating_credits'], 0) *
          costMultiplier *
          conditionCostMultiplier;
      total += (gross - cost).clamp(0, double.infinity) *
          asDoubleOr(holding['shares_owned'], 0) /
          asDoubleOr(holding['total_shares_issued'], 1000)
              .clamp(1, double.infinity);
    }
    return total;
  }

  static Widget _resourceLine(Map<String, double> changes,
      {bool emphasize = false}) {
    if (changes.isEmpty) {
      return const Text('No daily resource change',
          style: TextStyle(color: mutedColor, fontSize: 11));
    }
    final icons = {
      'credits': Icons.account_balance_wallet_outlined,
      'energy': Icons.bolt_rounded,
      'food': Icons.eco_outlined,
      'materials': Icons.terrain_outlined,
      'components': Icons.precision_manufacturing_outlined,
      'compute': Icons.memory_rounded
    };
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: changes.entries.map((entry) {
          final value = entry.value;
          final color = value < 0
              ? Colors.redAccent
              : value > 0
                  ? Colors.tealAccent
                  : mutedColor;
          return SizedBox(
              width: 62,
              child: Column(children: [
                Icon(icons[entry.key],
                    size: emphasize ? 18 : 16,
                    color: EarthResourceMeta.forCommodity(entry.key).color),
                Text(
                    '${value > 0 ? '+' : value < 0 ? '-' : ''}${_number(value)}',
                    style: TextStyle(
                        color: color,
                        fontSize: emphasize ? 13 : 12,
                        fontWeight: FontWeight.w800)),
              ]));
        }).toList());
  }

  static Widget _statusPill(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .6)));
  static Widget _notice(IconData icon, Color color, String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          border: Border.all(color: color.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 9),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: inkColor, fontSize: 10.5, height: 1.35)))
      ]));
}
