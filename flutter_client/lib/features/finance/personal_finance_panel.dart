import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
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
            building['status']?.toString() == 'active')
        .map((building) => Map<String, dynamic>.from(building))
        .toList();
    const investmentDividend = 0.0;
    final buildingChange = _buildingResourceChange(privateBuildings);
    final preparedBuildingChange = buildingChange;
    final basicRule = taxRules
        .where((rule) => rule['category']?.toString() == 'basic_income')
        .firstOrNull;
    final basicRate = asDoubleOr(basicRule?['rate'], 0);
    final grossCredits = preparedBuildingChange['credits']!;
    final incomeTax = grossCredits > 0 ? grossCredits * basicRate : 0.0;
    final finalChange = _addChanges(
        preparedBuildingChange,
        {'credits': -incomeTax});
    final unpaid = asDoubleOr(maintenance['unpaidTotal'], 0);
    final protected = asDoubleOr(
        _map(personalFinanceData['protectedMinimum'])['credits'], 100);
    final statusColor = unpaid > 0 ? Colors.orangeAccent : cyanAccentColor;
    final bank = _map(personalFinanceData['bank']);
    final bankDeposits = (bank['deposits'] as List? ?? const [])
        .whereType<Map>()
        .map((deposit) => Map<String, dynamic>.from(deposit))
        .toList();

    final liquidCredits = asDouble(state.human['credits']) ?? 0.0;
    final netDailyCredits = grossCredits - incomeTax;
    final netSign = netDailyCredits >= 0 ? '+' : '';

    final rawClock = state.clock;
    final rawServerTime = rawClock['serverCurrentTime'];
    final int serverMs = rawServerTime is num
        ? rawServerTime.toInt()
        : (rawServerTime is String ? int.tryParse(rawServerTime) : null) ??
            DateTime.now().toUtc().millisecondsSinceEpoch;
    final epochStartMs = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
    final diffMs = serverMs - epochStartMs;
    final totalSimMinutes = diffMs > 0 ? (diffMs ~/ 1000) : 0;
    final fallbackDay = (totalSimMinutes ~/ 1440) + 1;
    final fallbackMinute = totalSimMinutes % 1440;

    final parsedDay = asInt(rawClock['day']) ??
        asInt(rawClock['game_day']) ??
        asInt(rawClock['current_day']);
    final parsedMinute = asInt(rawClock['minute']) ??
        asInt(rawClock['game_minute']) ??
        asInt(rawClock['current_minute']);

    final currentDay = (parsedDay != null && parsedDay > 0) ? parsedDay : fallbackDay;
    final currentMinute = (parsedMinute != null && parsedMinute >= 0) ? parsedMinute : fallbackMinute;

    final cockpit = EarthPageCockpit(
      status: unpaid > 0 ? 'NEEDS ATTENTION' : 'ON TRACK',
      statusColor: unpaid > 0 ? context.warningColor : context.successColor,
      infoTitle: 'PERSONAL FINANCE & TREASURY ARCHITECTURE',
      infoDescription:
          '• Liquid Balances & Daily Income: Citizen liquid credits derived from private real estate, enterprise holdings, and public municipal investments.\n\n• Constitutional Basic Tax: Daily basic income levy governed by planetary and municipal statutes within constitutional limits.\n\n• Protected Citizen Reserve: Guaranteed credit reserve baseline shielded by Earth law to preserve core solvency.',
      title: 'PERSONAL FINANCE',
      subtitle:
          'Liquid balances, daily cashflow, and tax schedule across Earth',
      metrics: [
        CockpitMetric(
          label: 'Liquid Cash',
          value: formatWholeNumber(liquidCredits),
          icon: Icons.account_balance_wallet_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Daily Cashflow',
          value: '$netSign${formatWholeNumber(netDailyCredits)}',
          icon: Icons.trending_up_outlined,
          color: netDailyCredits >= 0 ? context.successColor : context.warningColor,
        ),
        CockpitMetric(
          label: 'Daily Tax',
          value: '${formatWholeNumber(incomeTax)} (${(basicRate * 100).toStringAsFixed(0)}%)',
          icon: Icons.receipt_long_outlined,
          color: context.secondaryColor,
        ),
      ],
    );

    return EarthPanel(
      key: panelKey,
      title: 'PERSONAL FINANCE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          'A clear daily statement of your personal income, tax, essential resources, and resulting change.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cockpit,
        const SizedBox(height: 28),
        const Text('DAILY INCOME', style: _sectionStyle),
        const SizedBox(height: 12),
        _allResourcesLine(finalChange, emphasize: true),
        const SizedBox(height: 24),
        _CreditIncomeSummaryCard(
          buildingCredits: preparedBuildingChange['credits']!,
          investmentDividend: investmentDividend,
          grossCredits: grossCredits,
          taxRate: basicRate,
          taxAmount: incomeTax,
          netCredits: grossCredits - incomeTax,
        ),
        const SizedBox(height: 24),
        _BankDepositsCard(
          deposits: bankDeposits,
          liquidCredits: liquidCredits,
          currentDay: currentDay,
          currentMinute: currentMinute,
          action: action,
        ),
        const SizedBox(height: 24),
        if (unpaid > 0) ...[
          _notice(Icons.warning_amber_rounded, Colors.orangeAccent,
              '${_credits(unpaid)} of essential costs remain unpaid.'),
          const SizedBox(height: 24),
        ],
        _notice(Icons.shield_outlined, violetColor,
            'Protected reserve: ${_credits(protected)}. Essential shortfalls are recorded; they do not remove you from the game.'),
      ]),
    );
  }

  static const _sectionStyle = TextStyle(
      color: mutedColor,
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: .6);
  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};
  static Map<String, double> _profileChange(Map<String, dynamic> profile) => {
        'credits': asDoubleOr(profile['credits_delta'] ?? profile['credits'], 0),
        'energy': asDoubleOr(profile['energy_delta'] ?? profile['energy'], 0),
        'food': asDoubleOr(profile['food_delta'] ?? profile['food'], 0),
        'materials': asDoubleOr(profile['materials_delta'] ?? profile['materials'], 0),
        'components': asDoubleOr(profile['components_delta'] ?? profile['components'], 0),
        'compute': asDoubleOr(profile['compute_delta'] ?? profile['compute'], 0),
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
    double rounded(double value) => (value * 10).ceil() / 10;
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

      for (final key in ['credits', 'energy', 'food', 'materials', 'components', 'compute']) {
        double outVal = asDoubleOr(building['output_$key'], 0);
        if (outVal == 0 && building['resource_output_type']?.toString() == key) {
          outVal = asDoubleOr(building['resource_output_amount'], 0);
        } else if (outVal == 0 && key == 'credits' && (building['resource_output_type']?.toString() == 'credits' || building['resource_output_type'] == null)) {
          outVal = asDoubleOr(building['resource_output_amount'], 0);
        }

        double upkeepVal = asDoubleOr(building['upkeep_$key'], 0);
        double opVal = asDoubleOr(building['operating_$key'], 0);
        if (key == 'credits' && opVal == 0) {
          opVal = asDoubleOr(building['daily_operating_credits'], 0);
        }

        final net = (outVal * outputMultiplier) - ((upkeepVal + opVal) * costMultiplier);
        changes[key] = (changes[key] ?? 0) +
            (key == 'credits' ? net : rounded(net));
      }
    }
    return changes;
  }

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
      final gross =
          asDoubleOr(building['resource_output_amount'], 0) * yieldMultiplier;
      final cost = asDoubleOr(building['daily_operating_credits'], 0) *
          costMultiplier;
      total += (gross - cost).clamp(0, double.infinity) *
          asDoubleOr(holding['shares_owned'], 0) /
          asDoubleOr(holding['total_shares_issued'], 1000)
              .clamp(1, double.infinity);
    }
    return total;
  }

  static Widget _allResourcesLine(Map<String, double> changes,
      {bool emphasize = false}) {
    final icons = {
      'credits': Icons.account_balance_wallet_outlined,
      'energy': Icons.bolt_rounded,
      'food': Icons.eco_outlined,
      'materials': Icons.terrain_outlined,
      'components': Icons.precision_manufacturing_outlined,
      'compute': Icons.memory_rounded
    };
    const order = ['credits', 'energy', 'food', 'materials', 'components', 'compute'];
    return Center(
      child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: order.map((key) {
            final value = changes[key] ?? 0.0;
            final color = value < 0
                ? Colors.redAccent
                : value > 0
                    ? Colors.tealAccent
                    : mutedColor;
            return SizedBox(
                width: 62,
                child: Column(children: [
                  Icon(icons[key],
                      size: emphasize ? 18 : 16,
                      color: EarthResourceMeta.forCommodity(key).color),
                  Text(
                      '${value > 0 ? '+' : value < 0 ? '-' : ''}${_number(value)}',
                      style: TextStyle(
                          color: color,
                          fontSize: emphasize ? 13 : 12,
                          fontWeight: FontWeight.w800)),
                ]));
          }).toList()),
    );
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

class _BankDepositsCard extends StatefulWidget {
  final List<Map<String, dynamic>> deposits;
  final double liquidCredits;
  final int currentDay;
  final int currentMinute;
  final Future<void> Function(Future<EarthState> Function()) action;

  const _BankDepositsCard({
    required this.deposits,
    required this.liquidCredits,
    required this.currentDay,
    required this.currentMinute,
    required this.action,
  });

  @override
  State<_BankDepositsCard> createState() => _BankDepositsCardState();
}

class _BankDepositsCardState extends State<_BankDepositsCard> {
  static const double _dailyRate = 0.001; // 0.1% per game day baseline
  static const List<int> _terms = [1, 7, 30, 90];

  final TextEditingController _amountController = TextEditingController(text: '100');
  int _selectedTermDays = 30;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _enteredAmount => double.tryParse(_amountController.text.trim()) ?? 0.0;
  double get _estimatedInterest => _enteredAmount * _dailyRate * _selectedTermDays;

  Future<void> _showDepositReviewDialog(BuildContext context) async {
    final amount = _enteredAmount;
    final termDays = _selectedTermDays;
    final maturityDay = widget.currentDay + termDays;
    final remainingCredits = widget.liquidCredits - amount;
    final isAffordable = widget.liquidCredits >= amount && amount > 0;
    final deficit = amount - widget.liquidCredits;
    final estInterest = amount * _dailyRate * termDays;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusCard),
            side: BorderSide(color: context.subtleBorderColor),
          ),
          title: Row(
            children: [
              const Icon(Icons.account_balance_outlined, color: EarthResourceColors.credits, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Confirm Bank Deposit', style: context.topicTitleStyle.copyWith(color: context.inkColor)),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review your deposit terms carefully. Deposited credits cannot be withdrawn before maturity.',
                  style: context.bodyStyle.copyWith(color: context.mutedColor),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    children: [
                      _reviewRow(dialogContext, 'Deposit amount', '${formatWholeNumber(amount)} C', isBold: true),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Remaining liquid credits', '${formatWholeNumber(remainingCredits < 0 ? 0 : remainingCredits)} C',
                          color: remainingCredits < 0 ? context.errorColor : context.inkColor),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Lock-up term', '$termDays game days'),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Current game time', formatGameDateTime(widget.currentDay, widget.currentMinute)),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Maturity', formatGameDateTime(maturityDay, widget.currentMinute)),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Estimated interest', '~${estInterest.toStringAsFixed(2)} C', color: context.successColor),
                      const Divider(height: 18, color: Colors.white10),
                      _reviewRow(
                        dialogContext,
                        'Expected payout (est.)',
                        '~${(amount + estInterest).toStringAsFixed(2)} C',
                        isBold: true,
                        color: EarthResourceColors.credits,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!isAffordable) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.errorColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(color: context.errorColor.withValues(alpha: .3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: context.errorColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            amount <= 0
                                ? 'Please enter a valid deposit amount greater than 0.'
                                : 'Insufficient Liquid credits. You need ${formatWholeNumber(deficit)} more Credits.',
                            style: context.captionStyle.copyWith(color: context.errorColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  '• Variable yield: returns depend on realized bank income and settlement.\n• Idempotent execution: unique correlation token attached to transaction.',
                  style: context.captionStyle.copyWith(color: context.mutedColor, height: 1.35),
                ),
              ],
            ),
          ),
          actions: [
            EarthButton(
              label: 'CANCEL',
              variant: EarthButtonVariant.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            EarthButton(
              label: 'CONFIRM DEPOSIT',
              icon: Icons.check_circle_outline,
              variant: EarthButtonVariant.primary,
              onPressed: isAffordable
                  ? () {
                      EarthAudioEngine.instance.playClick();
                      Navigator.of(dialogContext).pop(true);
                    }
                  : null,
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _executeDeposit(amount, termDays);
    }
  }

  Future<void> _executeDeposit(double amount, int termDays) async {
    setState(() => _submitting = true);
    try {
      EarthAudioEngine.instance.playCash();
      await widget.action(() async {
        await const EarthApi().createBankDeposit(amount: amount, termDays: termDays);
        return const EarthApi().world();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully deposited ${formatWholeNumber(amount)} C for $termDays days.'),
            backgroundColor: context.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deposit failed: $e'),
            backgroundColor: context.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _promptWithdraw(Map<String, dynamic> deposit) async {
    final depositId = deposit['id']?.toString() ?? '';
    final principal = asDoubleOr(deposit['principal'], 0);
    final interest = asDoubleOr(deposit['accrued_interest'], 0);
    final totalPayout = principal + interest;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusCard),
            side: BorderSide(color: context.subtleBorderColor),
          ),
          title: Row(
            children: [
              const Icon(Icons.download_done_rounded, color: Colors.tealAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Withdraw Matured Deposit', style: context.topicTitleStyle.copyWith(color: context.inkColor)),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your deposit has reached maturity. Confirm withdrawal to credit principal and realized interest to your liquid balance.',
                  style: context.bodyStyle.copyWith(color: context.mutedColor),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    children: [
                      _reviewRow(dialogContext, 'Deposit ID', depositId),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Principal return', '${formatWholeNumber(principal)} C'),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Realized interest', '${interest.toStringAsFixed(2)} C', color: context.successColor),
                      const Divider(height: 18, color: Colors.white10),
                      _reviewRow(
                        dialogContext,
                        'Total Liquid Credit Payout',
                        '${totalPayout.toStringAsFixed(2)} C',
                        isBold: true,
                        color: EarthResourceColors.credits,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            EarthButton(
              label: 'CANCEL',
              variant: EarthButtonVariant.neutral,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            EarthButton(
              label: 'WITHDRAW FUNDS',
              icon: Icons.account_balance_wallet_outlined,
              variant: EarthButtonVariant.primary,
              onPressed: () {
                EarthAudioEngine.instance.playClick();
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() => _submitting = true);
      try {
        EarthAudioEngine.instance.playCash();
        await widget.action(() async {
          await const EarthApi().withdrawBankDeposit(depositId);
          return const EarthApi().world();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully withdrawn ${totalPayout.toStringAsFixed(2)} C to your liquid balance.'),
              backgroundColor: context.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Withdrawal failed: $e'),
              backgroundColor: context.errorColor,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }
  }

  Widget _reviewRow(BuildContext ctx, String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: ctx.bodyStyle.copyWith(color: ctx.mutedColor)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: ctx.bodyStyle.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? ctx.inkColor,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDeposits = widget.deposits.where((d) {
      final status = d['status']?.toString().toLowerCase() ?? '';
      final maturityDay = asIntOr(d['maturity_game_day'], widget.currentDay + 1);
      return status == 'active' && widget.currentDay < maturityDay;
    }).toList();
    final totalPrincipal = widget.deposits.fold<double>(0.0, (sum, d) => sum + asDoubleOr(d['principal'], 0));
    final totalAccruedInterest = widget.deposits.fold<double>(0.0, (sum, d) => sum + asDoubleOr(d['accrued_interest'], 0));

    return EarthPanel(
      title: 'GLOBAL CORPORATE BANK',
      showTitle: true,
      infoDescription:
          'Global Corporate Bank allows citizens to deposit liquid credits for fixed terms. Deposited credits generate variable interest from corporate loan settlement and cannot be withdrawn prior to maturity. Returns are variable and not guaranteed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Overview
          _buildOverviewSection(
            context,
            liquidCredits: widget.liquidCredits,
            totalPrincipal: totalPrincipal,
            accruedInterest: totalAccruedInterest,
            activeDepositCount: activeDeposits.length,
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 20),

          // Section 2: Deposit Funds
          _buildDepositFundsSection(context),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 20),

          // Section 3: My Deposits
          _buildMyDepositsSection(context),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(
    BuildContext context, {
    required double liquidCredits,
    required double totalPrincipal,
    required double accruedInterest,
    required int activeDepositCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('OVERVIEW', style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
            const EarthBadge(
              label: 'GLOBAL BANK v1',
              variant: EarthBadgeVariant.neutral,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            final tiles = [
              _metricBox(context, 'Liquid credits', '${formatWholeNumber(liquidCredits)} C', Icons.account_balance_wallet_outlined, EarthResourceColors.credits),
              _metricBox(context, 'Deposited principal', '${formatWholeNumber(totalPrincipal)} C', Icons.lock_clock_outlined, context.primaryColor),
              _metricBox(context, 'Accrued interest', '${accruedInterest >= 0 ? '+' : ''}${accruedInterest.toStringAsFixed(2)} C', Icons.trending_up, context.successColor),
              _metricBox(context, 'Active deposits', '$activeDepositCount', Icons.receipt_long_outlined, context.secondaryColor),
            ];

            if (isNarrow) {
              return Column(
                children: [
                  Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 10), Expanded(child: tiles[1])]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 10), Expanded(child: tiles[3])]),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 10),
                Expanded(child: tiles[1]),
                const SizedBox(width: 10),
                Expanded(child: tiles[2]),
                const SizedBox(width: 10),
                Expanded(child: tiles[3]),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .03),
            borderRadius: BorderRadius.circular(context.radiusControl),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: context.mutedColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Credit deposits earn variable interest from realized bank income. Returns are variable and not guaranteed.',
                  style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricBox(BuildContext context, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.widgetTitleStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositFundsSection(BuildContext context) {
    final amount = _enteredAmount;
    final termDays = _selectedTermDays;
    final estReturn = amount * _dailyRate * termDays;
    final maturityDay = widget.currentDay + termDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEPOSIT FUNDS', style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 640;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNarrow) ...[
                  _buildAmountInput(context),
                  const SizedBox(height: 12),
                  _buildTermSelector(context),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildAmountInput(context)),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: _buildTermSelector(context)),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                // Estimation & Action banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .03),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: isNarrow
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Estimated interest: ', style: context.bodyStyle.copyWith(color: context.mutedColor, fontSize: 12)),
                                Text(
                                  '+${estReturn.toStringAsFixed(2)} C (~0.1%/day)',
                                  style: context.bodyStyle.copyWith(color: context.successColor, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Maturity: Game Day $maturityDay · Returns depend on realized bank income and settlement.',
                              style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 10.5),
                            ),
                            const SizedBox(height: 12),
                            EarthButton(
                              label: 'MAKE DEPOSIT',
                              icon: Icons.add_circle_outline,
                              variant: EarthButtonVariant.primary,
                              isLoading: _submitting,
                              onPressed: _submitting || amount <= 0 ? null : () => _showDepositReviewDialog(context),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text('Estimated interest: ', style: context.bodyStyle.copyWith(color: context.mutedColor, fontSize: 12)),
                                      Text(
                                        '+${estReturn.toStringAsFixed(2)} C (~0.1%/day)',
                                        style: context.bodyStyle.copyWith(color: context.successColor, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Maturity: Game Day $maturityDay · Returns depend on realized bank income and settlement.',
                                    style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            EarthButton(
                              label: 'MAKE DEPOSIT',
                              icon: Icons.add_circle_outline,
                              variant: EarthButtonVariant.primary,
                              isLoading: _submitting,
                              onPressed: _submitting || amount <= 0 ? null : () => _showDepositReviewDialog(context),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Deposited credits cannot be withdrawn before maturity.',
                        style: context.captionStyle.copyWith(color: Colors.orangeAccent, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAmountInput(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Deposit Amount (Credits)', style: context.captionStyle.copyWith(color: context.mutedColor)),
        const SizedBox(height: 6),
        Container(
          height: context.inputHeight,
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusControl),
            border: Border.all(color: context.subtleBorderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 16, color: EarthResourceColors.credits),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: context.bodyStyle.copyWith(fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter amount...',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text('C', style: context.bodyStyle.copyWith(color: context.mutedColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Term Length (Game Days)', style: context.captionStyle.copyWith(color: context.mutedColor)),
        const SizedBox(height: 6),
        Row(
          children: _terms.map((term) {
            final isSelected = _selectedTermDays == term;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: term == _terms.last ? 0 : 6),
                child: InkWell(
                  onTap: () {
                    EarthAudioEngine.instance.playClick();
                    setState(() => _selectedTermDays = term);
                  },
                  borderRadius: BorderRadius.circular(context.radiusControl),
                  child: Container(
                    height: context.inputHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? context.primaryColor.withValues(alpha: .15) : context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                        color: isSelected ? context.primaryColor : context.subtleBorderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '$term d',
                      style: context.bodyStyle.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? context.primaryColor : context.mutedColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMyDepositsSection(BuildContext context) {
    final deposits = widget.deposits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MY DEPOSITS', style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
            Text(
              '${deposits.length} ${deposits.length == 1 ? 'record' : 'records'}',
              style: context.widgetFooterStyle,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (deposits.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .02),
              borderRadius: BorderRadius.circular(context.radiusControl),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Column(
              children: [
                Icon(Icons.savings_outlined, size: 28, color: context.mutedColor),
                const SizedBox(height: 8),
                Text(
                  'No active deposits. Deposit credits to earn potential interest over a selected term.',
                  textAlign: TextAlign.center,
                  style: context.bodyStyle.copyWith(color: context.mutedColor, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Column(
            children: deposits.map((deposit) => _buildDepositRow(context, deposit)).toList(),
          ),
      ],
    );
  }

  Widget _buildDepositRow(BuildContext context, Map<String, dynamic> deposit) {
    final principal = asDoubleOr(deposit['principal'], 0);
    final interest = asDoubleOr(deposit['accrued_interest'], 0);
    final startDay = asIntOr(deposit['start_game_day'], 1);
    final startMinute = asIntOr(deposit['start_game_minute'], 0);
    final maturityDay = asIntOr(deposit['maturity_game_day'], startDay + 1);
    final maturityMinute = asIntOr(deposit['maturity_game_minute'], startMinute);
    final rawStatus = deposit['status']?.toString().toLowerCase() ?? 'active';

    final isMaturedByTime = (widget.currentDay - 1) * 1440 + widget.currentMinute >=
        (maturityDay - 1) * 1440 + maturityMinute;
    final isWithdrawn = rawStatus == 'withdrawn';
    final isCancelled = rawStatus == 'cancelled';
    final isMatured = rawStatus == 'matured' || (!isWithdrawn && !isCancelled && isMaturedByTime);

    final statusText = isWithdrawn
        ? 'Withdrawn'
        : isCancelled
            ? 'Cancelled'
            : isMatured
                ? 'Matured'
                : 'Active';

    final EarthBadgeVariant badgeVariant = isWithdrawn
        ? EarthBadgeVariant.neutral
        : isCancelled
            ? EarthBadgeVariant.error
            : isMatured
                ? EarthBadgeVariant.success
                : EarthBadgeVariant.primary;

    // Term progress: clamped 0.0 to 1.0
    final totalDays = (maturityDay - startDay).clamp(1, 9999);
    final elapsedDays = (widget.currentDay - startDay).clamp(0, totalDays);
    final progress = isWithdrawn ? 1.0 : (elapsedDays / totalDays).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined, size: 18, color: EarthResourceColors.credits),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatWholeNumber(principal)} C',
                      style: context.widgetTitleStyle.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text.rich(
                      TextSpan(
                        text: 'Accrued interest: ',
                        style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 11),
                        children: [
                          TextSpan(
                            text: '${interest >= 0 ? '+' : ''}${interest.toStringAsFixed(2)} C',
                            style: context.captionStyle.copyWith(color: context.successColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              EarthBadge(
                label: statusText,
                variant: badgeVariant,
              ),
              if (!isWithdrawn && !isCancelled) ...[
                const SizedBox(width: 12),
                EarthButton(
                  label: 'WITHDRAW',
                  icon: Icons.download_outlined,
                  variant: EarthButtonVariant.secondary,
                  height: 32,
                  isLoading: _submitting,
                  onPressed: (isMatured && !_submitting)
                      ? () => _promptWithdraw(deposit)
                      : null,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!isWithdrawn) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isMatured ? context.successColor : context.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  formatGameDateTime(startDay, startMinute),
                  style: context.captionStyle.copyWith(color: context.mutedColor, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatGameDateTime(maturityDay, maturityMinute),
                  textAlign: TextAlign.end,
                  style: context.captionStyle.copyWith(
                    color: isMatured && !isWithdrawn ? context.successColor : context.mutedColor,
                    fontWeight: isMatured && !isWithdrawn ? FontWeight.bold : FontWeight.normal,
                    fontSize: 10.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditIncomeSummaryCard extends StatelessWidget {
  final double buildingCredits;
  final double investmentDividend;
  final double grossCredits;
  final double taxRate;
  final double taxAmount;
  final double netCredits;

  const _CreditIncomeSummaryCard({
    required this.buildingCredits,
    required this.investmentDividend,
    required this.grossCredits,
    required this.taxRate,
    required this.taxAmount,
    required this.netCredits,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildGrossColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GROSS CREDIT INCOME',
                style: context.widgetTitleStyle.copyWith(
                  letterSpacing: .8,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: EarthResourceColors.credits,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${grossCredits > 0 ? '+' : grossCredits < 0 ? '-' : ''}${PersonalFinancePanel._number(grossCredits)} C',
                    style: TextStyle(
                      color: grossCredits < 0
                          ? Colors.redAccent
                          : grossCredits > 0
                              ? Colors.tealAccent
                              : context.mutedColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 12),
          PersonalFinancePanel._creditRow(
            'Private buildings',
            buildingCredits,
            positive: true,
          ),
          PersonalFinancePanel._creditRow(
            'Investment dividend',
            investmentDividend,
            positive: true,
            displayAsWhole: true,
          ),
        ],
      );
    }

    Widget buildNetColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NET CREDIT INCOME',
                style: context.widgetTitleStyle.copyWith(
                  letterSpacing: .8,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: EarthResourceColors.credits,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${netCredits > 0 ? '+' : netCredits < 0 ? '-' : ''}${PersonalFinancePanel._number(netCredits)} C',
                    style: TextStyle(
                      color: netCredits < 0
                          ? Colors.redAccent
                          : netCredits > 0
                              ? Colors.tealAccent
                              : context.mutedColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 12),
          PersonalFinancePanel._taxRow(taxRate, taxAmount),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildGrossColumn(),
                const SizedBox(height: 20),
                Divider(height: 1, color: context.subtleBorderColor),
                const SizedBox(height: 20),
                buildNetColumn(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildGrossColumn()),
              const SizedBox(width: 24),
              Container(
                width: 1,
                height: 110,
                color: context.subtleBorderColor,
              ),
              const SizedBox(width: 24),
              Expanded(child: buildNetColumn()),
            ],
          );
        },
      ),
    );
  }
}
