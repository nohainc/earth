import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

Widget _financeTopicHeading(BuildContext context, String title,
    {required String description}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Flexible(
        child: Text(title,
            style: const TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      ),
      const SizedBox(width: 5),
      IconButton(
        tooltip: 'About $title',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(Icons.info_outline,
            size: 14, color: mutedColor.withValues(alpha: .8)),
        onPressed: () => showEarthInfoDialog(context,
            title: title, description: description),
      ),
    ]),
  );
}

class FinancialOutlookPanel extends StatelessWidget {
  final EarthState state;
  final Map<String, dynamic> personalFinanceData;

  const FinancialOutlookPanel({
    super.key,
    required this.state,
    this.personalFinanceData = const {},
  });

  @override
  Widget build(BuildContext context) {
    final finState = personalFinanceData['state'] is Map
        ? Map<String, dynamic>.from(personalFinanceData['state'] as Map)
        : const <String, dynamic>{};
    final account = personalFinanceData['account'] is Map
        ? Map<String, dynamic>.from(personalFinanceData['account'] as Map)
        : const <String, dynamic>{};
    final balance = asDouble(state.human['credits'] ?? account['balance']);
    final income = asDouble(finState['income']);
    final expenses = asDouble(finState['expenses']);
    final taxes = asDouble(finState['tax_obligations']);
    final net = income != null && expenses != null && taxes != null
        ? income - expenses - taxes
        : null;
    final obligations = <String>[];
    if ((taxes ?? 0) > 0) {
      obligations.add('Tax assessment: ${formatWholeNumber(taxes!)} C');
    }
    final goals = personalFinanceData['goals'] is List
        ? (personalFinanceData['goals'] as List)
            .whereType<Map>()
            .map(
                (goal) => goal['name']?.toString() ?? goal['title']?.toString())
            .whereType<String>()
            .toList()
        : const <String>[];
    final assets = personalFinanceData['assets'] is List
        ? (personalFinanceData['assets'] as List)
            .whereType<Map>()
            .map((asset) =>
                asset['name']?.toString() ?? asset['title']?.toString())
            .whereType<String>()
            .toList()
        : const <String>[];
    final incomeSources = personalFinanceData['incomeSources'] is List
        ? (personalFinanceData['incomeSources'] as List)
            .whereType<Map>()
            .map((item) =>
                item['name']?.toString() ?? item['source']?.toString())
            .whereType<String>()
            .toList()
        : const <String>[];
    final liabilities = personalFinanceData['liabilities'] is List
        ? (personalFinanceData['liabilities'] as List)
            .whereType<Map>()
            .map(
                (item) => item['name']?.toString() ?? item['title']?.toString())
            .whereType<String>()
            .toList()
        : const <String>[];
    final reserveTarget = asDouble(
        finState['reserve_target'] ?? finState['emergency_reserve_target']);
    final forecast = net == null
        ? 'Future risk is unavailable until current income and expense data are reported.'
        : net < 0
            ? 'Cash flow is negative. Reduce outflow, add income, or review obligations.'
            : reserveTarget != null &&
                    balance != null &&
                    balance < reserveTarget
                ? 'Cash flow is positive, but the balance is below the reserve target.'
                : 'Cash flow is positive. Decide how much to save, invest, or support.';

    return EarthPanel(
      title: 'FINANCIAL OUTLOOK',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• This view connects money to decisions: obligations, goals, assets, and financial risk.\n\n• Trade & Supplies handles resources and market orders; Personal Finance handles credits and commitments.\n\n• Values are shown only when current financial data is available.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _outlookTile(
              'AVAILABLE CREDITS',
              balance == null
                  ? 'UNAVAILABLE'
                  : '${formatWholeNumber(balance)} C',
              Icons.account_balance_wallet_outlined,
              EarthResourceColors.credits),
          _outlookTile(
              'NET DAILY CHANGE',
              net == null
                  ? 'UNAVAILABLE'
                  : '${net >= 0 ? '+' : ''}${formatWholeNumber(net)} C',
              Icons.trending_up_outlined,
              net == null || net >= 0
                  ? Colors.tealAccent
                  : Colors.orangeAccent),
          _outlookTile(
              'UPCOMING OBLIGATIONS',
              obligations.isEmpty ? 'None recorded' : obligations.join(' · '),
              Icons.receipt_long_outlined,
              Colors.orangeAccent),
        ]),
        const SizedBox(height: 12),
        Text(
            goals.isEmpty
                ? 'No financial goal is recorded yet. Consider an emergency reserve, business investment, family support, or financial independence goal.'
                : 'Goals: ${goals.join(' · ')}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 6),
        Text(
            assets.isEmpty
                ? 'Assets and investments are not itemized in the current financial record.'
                : 'Assets: ${assets.join(' · ')}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 10),
        Text(
            incomeSources.isEmpty
                ? 'Income sources are not itemized in the current financial record.'
                : 'Income: ${incomeSources.join(' · ')}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 6),
        Text(
            liabilities.isEmpty
                ? 'No liabilities are recorded.'
                : 'Liabilities: ${liabilities.join(' · ')}',
            style: const TextStyle(color: mutedColor, fontSize: 10.5)),
        const SizedBox(height: 10),
        Text('OUTLOOK: $forecast',
            style: TextStyle(
                color: net != null && net < 0 ? Colors.orangeAccent : inkColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
            'Plan before acting: save · invest · pay · borrow · transfer · support family.',
            style: TextStyle(
                color: inkColor, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _outlookTile(String label, String value, IconData icon, Color color) {
    return Container(
        width: 170,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: .28))),
        child: Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        color: mutedColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800))
              ]))
        ]));
  }
}

class PersonalFinancePanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> personalFinanceData;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const PersonalFinancePanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    this.personalFinanceData = const {},
    required this.action,
  });

  @override
  State<PersonalFinancePanel> createState() => _PersonalFinancePanelState();
}

class _PersonalFinancePanelState extends State<PersonalFinancePanel> {
  String? _localStatusMessage;
  bool _localBusy = false;

  Future<void> _settleTax(BuildContext context) async {
    final controller = TextEditingController(text: '1000');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: cyanAccentColor),
            SizedBox(width: 8),
            Text(
              'Settle Tax Obligations',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: inkColor),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tax calculations are canonically assessed by the municipal authority. Settle assessed dues to maintain civic standing and avoid penalty surcharges:',
              style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 13, color: inkColor),
              decoration: InputDecoration(
                labelText: 'Assessed Amount to Pay (C)',
                labelStyle: const TextStyle(fontSize: 11, color: mutedColor),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: cyanAccentColor),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL',
                style: TextStyle(color: mutedColor, fontSize: 11)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cyanAccentColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CONFIRM SETTLEMENT',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final val = double.tryParse(controller.text.trim()) ?? 1000.0;
      setState(() => _localBusy = true);
      try {
        await widget.action(() => const EarthApi().settlePersonalTax(val));
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage =
                'Tax obligations settled successfully through central authority.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Settlement failed: $e';
          });
        }
      }
    }
  }

  Future<void> _declareInsolvency(BuildContext context) async {
    final reasonController =
        TextEditingController(text: 'Liquidity deficit restructuring');
    final otpController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.redAccent),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              'Declare Personal Insolvency',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: inkColor),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sovereign insolvency restructuring reorganizes liabilities. Statutory protection guarantees your 100 Credit minimum reserve and basic service robot immunity against liquidation.',
              style: TextStyle(fontSize: 11.5, color: mutedColor, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              style: const TextStyle(fontSize: 13, color: inkColor),
              decoration: InputDecoration(
                labelText: 'Restructuring Reason',
                labelStyle: const TextStyle(fontSize: 11, color: mutedColor),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 13, color: inkColor),
              decoration: InputDecoration(
                labelText: 'MFA Authenticator Code (if enabled)',
                labelStyle: const TextStyle(fontSize: 11, color: mutedColor),
                filled: true,
                fillColor: Colors.white.withValues(alpha: .04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL',
                style: TextStyle(color: mutedColor, fontSize: 11)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('EXECUTE RESTRUCTURING',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _localBusy = true);
      try {
        await widget
            .action(() => const EarthApi().declareInsolvencyRestructuring(
                  reason: reasonController.text,
                  otp: otpController.text.isEmpty ? null : otpController.text,
                ));
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage =
                'Personal insolvency restructuring processed and registered.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Restructuring request failed: $e';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.personalFinanceData;
    final account = data['account'] as Map<String, dynamic>?;
    final finState = data['state'] as Map<String, dynamic>?;
    final protected = data['protectedMinimum'] as Map<String, dynamic>?;

    final balanceNum =
        widget.state.human['credits'] ?? account?['balance'] ?? 0;
    final balance = asDoubleOr(balanceNum, 0.0);
    final income = asDoubleOr(finState?['income'], 760.0);
    final expenses = asDoubleOr(finState?['expenses'], 240.0);
    final taxObligations = asDoubleOr(finState?['tax_obligations'], 48.0);
    final netAccumulation = income - expenses - taxObligations;
    final accumulationMargin =
        income > 0 ? (netAccumulation / income) * 100 : 0.0;

    final rawLiquidity =
        (finState?['liquidity_status'] ?? (balance > 500 ? 'healthy' : 'tight'))
            .toString()
            .toLowerCase();
    final insolvencyStatus = (finState?['insolvency_status'] ??
            finState?['status'] ??
            (balance >= 100 ? 'SOLVENT' : 'INSOLVENT'))
        .toString()
        .toUpperCase();
    final protectedCredits = asIntOr(protected?['credits'], 100);

    final isTight = rawLiquidity == 'tight';
    final isAtRisk =
        rawLiquidity == 'at_risk' || insolvencyStatus == 'INSOLVENT';

    Color statusColor = cyanAccentColor;
    String statusText = 'HEALTHY LIQUIDITY';
    if (isTight) {
      statusColor = Colors.orangeAccent;
      statusText = 'TIGHT LIQUIDITY';
    } else if (isAtRisk) {
      statusColor = Colors.redAccent;
      statusText = 'AT RISK · INSOLVENT';
    }

    final expenseRatio =
        income > 0 ? (expenses / income).clamp(0.0, 1.0) : 0.35;
    final taxRatio =
        income > 0 ? (taxObligations / income).clamp(0.0, 1.0) : 0.08;
    final retainedRatio = (1.0 - expenseRatio - taxRatio).clamp(0.0, 1.0);

    final isBusy = widget.busy || _localBusy;

    return EarthPanel(
      key: widget.panelKey,
      title: 'MONEY TODAY / PERSONAL FINANCE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Keep enough Credits for daily life, taxes, and unexpected problems.\n\n• Use surplus to improve businesses, support your family, or build a reserve.\n\n• This page covers personal money and commitments; resources and market orders belong in Trade & Supplies.\n\n• Detailed income and expense breakdowns remain available when you need to investigate a problem.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _financeTopicHeading(
                context,
                'MONEY TODAY / PERSONAL FINANCE',
                description:
                    '• Personal Wealth & Solvency Cockpit: Real-time liquid credit balance, solvency classification, and immutable statutory asset protection guarantees.',
              ),
              // 1. EXECUTIVE WEALTH & SOLVENCY HEADER
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color:
                              EarthResourceColors.credits.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: EarthResourceColors.credits
                                  .withValues(alpha: .4)),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          size: 22,
                          color: EarthResourceColors.credits,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        formatWholeNumber(balance),
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: inkColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'C',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: inkColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                        color:
                                            statusColor.withValues(alpha: .4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: .8,
                                          color: statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ACCOUNT: ${widget.state.human['id'] ?? 'H-0044'}  ·  AUDIT STATUS: AUDITED DOUBLE-ENTRY  ·  SOLVENCY: $insolvencyStatus',
                              style: const TextStyle(
                                fontSize: 10,
                                color: mutedColor,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Statutory Asset Protection Shield
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined,
                            size: 16, color: violetColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'STATUTORY PROTECTION SHIELD · Guaranteed minimum reserve: $protectedCredits C (Basic Service Robot protected from forfeiture)',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: inkColor,
                              letterSpacing: .4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 34),

              // 2. CASH FLOW & PERSONAL UNIT ECONOMICS
              _financeTopicHeading(
                context,
                'CASH FLOW / WHERE MONEY COMES FROM AND GOES',
                description:
                    '• Decide whether today\'s money should cover life, taxes, family, business investment, or savings.',
              ),
              const SizedBox(height: 8),

              LayoutBuilder(
                builder: (context, finConstraints) {
                  final finWidth = finConstraints.maxWidth;
                  final numCols = finWidth >= 900
                      ? 4
                      : finWidth >= 500
                          ? 2
                          : 1;
                  final itemWidth = numCols == 1
                      ? finWidth
                      : (finWidth - (numCols - 1) * 12) / numCols;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _financeMetricBox(
                        width: itemWidth,
                        title: 'DAILY INFLOW',
                        value: '${formatWholeNumber(income)} C',
                        subtext:
                            'Income stream: ${formatWholeNumber(income)} C / day',
                        accent: Colors.tealAccent,
                        icon: Icons.trending_up_rounded,
                      ),
                      _financeMetricBox(
                        width: itemWidth,
                        title: 'BASELINE OUTFLOW',
                        value: '${formatWholeNumber(expenses)} C',
                        subtext:
                            'Estimated baseline expenses: ${formatWholeNumber(expenses)} C / day',
                        accent: Colors.orangeAccent,
                        icon: Icons.trending_down_rounded,
                      ),
                      _financeMetricBox(
                        width: itemWidth,
                        title: 'NET DAILY ACCUMULATION',
                        value:
                            '${netAccumulation >= 0 ? '+' : ''}${formatWholeNumber(netAccumulation)} C',
                        subtext:
                            'Savings Margin: ${accumulationMargin.toStringAsFixed(1)}%',
                        accent: netAccumulation >= 0
                            ? cyanAccentColor
                            : Colors.redAccent,
                        icon: Icons.savings_outlined,
                      ),
                      _financeMetricBox(
                        width: itemWidth,
                        title: 'ASSESSED TAX DUES',
                        value: '${formatWholeNumber(taxObligations)} C',
                        subtext:
                            'Assessed tax obligations: ${formatWholeNumber(taxObligations)} C',
                        accent: violetColor,
                        icon: Icons.receipt_long_outlined,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Visual Cash Flow Allocation Bar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'INCOME ALLOCATION BREAKDOWN',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                            color: mutedColor.withValues(alpha: .9),
                          ),
                        ),
                        Text(
                          '${(expenseRatio * 100).toStringAsFixed(0)}% Living  ·  ${(taxRatio * 100).toStringAsFixed(0)}% Tax  ·  ${(retainedRatio * 100).toStringAsFixed(0)}% Retained',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 8,
                        child: Row(
                          children: [
                            Expanded(
                              flex: (expenseRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color:
                                    Colors.orangeAccent.withValues(alpha: .8),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              flex: (taxRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color: violetColor.withValues(alpha: .8),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              flex: (retainedRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color: netAccumulation >= 0
                                    ? cyanAccentColor
                                    : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_localStatusMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: violetColor.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: violetColor.withValues(alpha: .3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: violetColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _localStatusMessage!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: inkColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 34),

              // 3. COMPLIANCE & LEGAL ACTION HUB
              _financeTopicHeading(
                context,
                'COMPLIANCE & SOVEREIGN ACTIONS',
                description:
                    '• Settle tax dues immediately to preserve civic standing, or invoke sovereign restructuring when facing severe deficits.',
              ),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cyanAccentColor,
                      side: BorderSide(
                          color: cyanAccentColor.withValues(alpha: .3)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: isBusy ? null : () => _settleTax(context),
                    icon: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: const Text(
                      'SETTLE TAXES',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(
                          color: Colors.redAccent.withValues(alpha: .3)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed:
                        isBusy ? null : () => _declareInsolvency(context),
                    icon: const Icon(Icons.warning_amber_rounded, size: 15),
                    label: const Text(
                      'INSOLVENCY RESTRUCTURING',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _financeMetricBox({
    required double width,
    required String title,
    required String value,
    required String subtext,
    required Color accent,
    required IconData icon,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .9,
                  color: mutedColor,
                ),
              ),
              Icon(icon, size: 14, color: accent),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(
              fontSize: 9.5,
              color: mutedColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
