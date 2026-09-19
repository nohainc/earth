import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/house_finance_models.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

BigInt? _creditUnits(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  return BigInt.tryParse(raw);
}

String _creditText(dynamic value, {String fallback = 'UNAVAILABLE'}) =>
    formatCreditUnits(value, fallback: fallback);

String _signedCreditText(BigInt value) {
  final sign = value > BigInt.zero ? '+' : value < BigInt.zero ? '-' : '';
  return '$sign${formatCreditUnits(value.abs())}';
}

BigInt? _parseCreditInput(String value) {
  final raw = value.trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(raw);
  if (match == null) return null;
  final whole = BigInt.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * BigInt.from(100) + BigInt.parse(fraction.isEmpty ? '0' : fraction);
}

String _creditDecimal(BigInt units) {
  final absolute = units.abs();
  final whole = absolute ~/ BigInt.from(100);
  final cents = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  return '${units.isNegative ? '-' : ''}$whole.$cents';
}

BigInt? _forecastCategoryUnits(Map<String, dynamic> forecast, String category) {
  final rows = forecast['items'];
  if (rows is! List) return null;
  var total = BigInt.zero;
  var found = false;
  for (final raw in rows.whereType<Map>()) {
    if (raw['category']?.toString() != category) continue;
    final units = _creditUnits(raw['amountUnits']);
    if (units == null) continue;
    total += units;
    found = true;
  }
  return found ? total : BigInt.zero;
}

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
    final finance = HouseFinanceOverview.fromJson(personalFinanceData);
    final obligations = finance.obligations;
    final maintenance = obligations.dailyNeeds;
    final nextSettlement = finance.cashflow.nextSettlement;
    final projectedIncome = _creditUnits(nextSettlement['inflowsUnits']);
    final projectedTax = _forecastCategoryUnits(nextSettlement, 'TAX');
    final grossCredits = projectedIncome;
    final incomeTax = projectedTax;
    final foodShortfall = _creditUnits(maintenance['food_shortfall_units']) ?? BigInt.zero;
    final needsAttention = foodShortfall > BigInt.zero;

    final serverAvailableToSpend = finance.liquidity.availableToSpendUnits;
    final availableToSpend = serverAvailableToSpend ?? BigInt.zero;
    final availableToSpendKnown = serverAvailableToSpend != null;
    final netDailyCredits = _creditUnits(nextSettlement['netCashflowUnits']);

    final rawClock = state.clock;
    final parsedDay = asInt(rawClock['day']) ??
        asInt(rawClock['game_day']) ??
        asInt(rawClock['current_day']);
    final parsedMinute = asInt(rawClock['minute']) ??
        asInt(rawClock['game_minute']) ??
        asInt(rawClock['current_minute']);

    final currentDay = parsedDay;
    final currentMinute = parsedMinute;

    final cockpit = EarthPageCockpit(
      status: needsAttention ? 'NEEDS ATTENTION' : 'ON TRACK',
      statusColor: needsAttention ? context.warningColor : context.successColor,
      infoTitle: 'HOUSE FINANCE & TREASURY',
      infoDescription:
          'Manage House liquidity, the next settlement, obligations, savings and borrowing.',
      title: 'HOUSE FINANCE',
      subtitle: 'Liquidity, obligations, savings and borrowing for your House',
      metrics: [
        CockpitMetric(
          label: 'Available to Spend',
          value: availableToSpendKnown
              ? _creditText(availableToSpend)
              : 'UNAVAILABLE',
          icon: Icons.account_balance_wallet_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Next Settlement',
          value: netDailyCredits == null
              ? 'UNAVAILABLE'
              : _signedCreditText(netDailyCredits),
          icon: Icons.trending_up_outlined,
          color: netDailyCredits != null && netDailyCredits >= BigInt.zero
              ? context.successColor
              : context.warningColor,
        ),
        CockpitMetric(
          label: 'Next Tax',
          value: incomeTax == null ? 'UNAVAILABLE' : _creditText(incomeTax),
          icon: Icons.receipt_long_outlined,
          color: context.secondaryColor,
        ),
      ],
    );

    return EarthPanel(
      key: panelKey,
      title: 'HOUSE FINANCE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          'A clear daily statement of your personal income, tax, essential resources, and resulting change.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cockpit,
        const SizedBox(height: 28),
        const Text('NEXT SETTLEMENT', style: _sectionStyle),
        const SizedBox(height: 12),
        if (finance.liquidity.nextSettlementGameDay != null)
          Text('Scheduled game day ${finance.liquidity.nextSettlementGameDay}',
              style: context.widgetFooterStyle),
        if (finance.liquidity.nextSettlementGameDay != null)
          const SizedBox(height: 8),
        if (netDailyCredits == null)
          const Text('The next settlement forecast is unavailable.',
              style: TextStyle(color: mutedColor, fontSize: 11))
        else
          _creditStatementLine(netDailyCredits, emphasize: true),
        const SizedBox(height: 24),
        _CreditIncomeSummaryCard(
          nextSettlement: nextSettlement,
        ),
        const SizedBox(height: 24),
        _ObligationsCard(obligations: obligations, action: action),
        const SizedBox(height: 24),
        _BankSummaryCard(bank: finance.bank),
        const SizedBox(height: 24),
        _BankDepositsCard(
          deposits: finance.bank.deposits,
          liquidCredits: availableToSpend,
          currentDay: currentDay ?? 0,
          currentMinute: currentMinute ?? 0,
          action: action,
        ),
        const SizedBox(height: 24),
        _BankCreditCard(action: action, availableToSpend: availableToSpend, currentDay: currentDay ?? 0),
        const SizedBox(height: 24),
        if (needsAttention) ...[
          _notice(Icons.warning_amber_rounded, Colors.orangeAccent,
              '${formatAssetQuantity('FOOD', foodShortfall)} of required food was not consumed at the last settlement.'),
          const SizedBox(height: 24),
        ],
        _FinanceActivityCard(
            transactions:
                finance.cashflow.recentTransactions),
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
  static Widget _creditStatementLine(BigInt value, {bool emphasize = false}) {
    return Center(
      child: Text('${_signedCreditText(value)} recorded net ledger flow',
          style: TextStyle(
              color: value < BigInt.zero ? Colors.redAccent : Colors.tealAccent,
              fontSize: emphasize ? 14 : 12,
              fontWeight: FontWeight.w800)),
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
                    '${value > 0 ? '+' : value < 0 ? '-' : ''}${value.toStringAsFixed(2)}',
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

class _ObligationsCard extends StatelessWidget {
  final HouseObligations obligations;
  final Future<void> Function(Future<EarthState> Function()) action;

  const _ObligationsCard({required this.obligations, required this.action});

  @override
  Widget build(BuildContext context) {
    final sections = <({String title, HouseObligationSection data})>[
      (title: 'CAPACITY OBLIGATION', data: obligations.capacity),
      (title: 'TAXES', data: obligations.taxes),
      (title: 'LOAN SCHEDULES', data: obligations.loans),
      (title: 'OTHER MANDATORY CLAIMS', data: obligations.other),
    ];
    return EarthSection(
      title: 'OBLIGATIONS',
      showSurface: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Authoritative House claims and their settlement status.',
              style: TextStyle(color: mutedColor, fontSize: 11)),
          const SizedBox(height: 12),
          for (final section in sections)
            _obligationRow(context, section.title, section.data),
          if (obligations.capacity.status == 'ARREARS' || obligations.capacity.status == 'DELINQUENT') ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.warningColor.withValues(alpha: .10),
                border: Border.all(color: context.warningColor.withValues(alpha: .35)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: context.warningColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Capacity distress is ${obligations.capacity.status}. Use the V5 resolution flow to review available remedies.',
                      style: const TextStyle(fontSize: 11, height: 1.35),
                    ),
                  ),
                  EarthButton(
                    label: 'OPEN RESOLUTION',
                    icon: Icons.support_agent_outlined,
                    onPressed: () => action(() => const EarthApi()
                        .openCapacityResolution(reason: 'Finance review requested')
                        .then((_) => const EarthApi().world())),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _obligationRow(BuildContext context, String title, HouseObligationSection data) {
    final status = data.status;
    final remaining = _creditText(data.totalRemainingUnits);
    final statusColor = switch (status) {
      'CURRENT' => context.successColor,
      'DUE' => context.secondaryColor,
      'ARREARS' || 'DELINQUENT' => context.warningColor,
      _ => mutedColor,
    };
    final claims = data.claims.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(child: Text('$title · $claims claim${claims == 1 ? '' : 's'}')),
          Text(remaining, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          _statusPill(status, statusColor),
        ],
      ),
    );
  }

  Widget _statusPill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          border: Border.all(color: color.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
      );

}

class _BankSummaryCard extends StatelessWidget {
  final HouseBankSummary bank;
  const _BankSummaryCard({required this.bank});

  @override
  Widget build(BuildContext context) => EarthSection(
        title: 'BANKING SUMMARY',
        showSurface: true,
        child: Row(
          children: [
            Expanded(child: _metric(context, 'Deposits', bank.depositPrincipalUnits, Icons.savings_outlined)),
            const SizedBox(width: 12),
            Expanded(child: _metric(context, 'Outstanding debt', bank.loanOutstandingUnits, Icons.account_balance_outlined)),
          ],
        ),
      );

  Widget _metric(BuildContext context, String label, BigInt units, IconData icon) =>
      Row(children: [
        Icon(icon, size: 18, color: context.primaryColor),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: context.widgetFooterStyle),
          Text(formatCreditUnits(units), style: context.widgetTitleStyle),
        ])),
      ]);
}

class _BankCreditCard extends StatefulWidget {
  final Future<void> Function(Future<EarthState> Function()) action;
  final BigInt availableToSpend;
  final int currentDay;
  const _BankCreditCard({required this.action, required this.availableToSpend, required this.currentDay});

  @override
  State<_BankCreditCard> createState() => _BankCreditCardState();
}

class _BankCreditCardState extends State<_BankCreditCard> {
  bool _loading = true;
  String? _error;
  List<HouseLoan> _loans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([const EarthApi().bankLoans()]);
      if (!mounted) return;
      final rawLoans = results[0]['loans'];
      setState(() {
        _loans = rawLoans is List
            ? rawLoans
                .whereType<Map>()
                .map((r) => HouseLoan.fromJson(Map<String, dynamic>.from(r)))
                .toList()
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _borrow() async {
    final result = await showDialog<Map<String, String>>(
        context: context, builder: (_) => const _LoanDialog());
    if (result == null || !mounted) return;
    try {
      final quote = await const EarthApi().bankLoanQuote(
          amount: result['amount']!,
          termDays: int.parse(result['term']!));
      final quoteData = quote['quote'] is Map
          ? Map<String, dynamic>.from(quote['quote'] as Map)
          : const <String, dynamic>{};
      if (quoteData['eligible'] != true) {
        throw Exception(
            quoteData['reason'] ?? 'The bank declined this request');
      }
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => _LoanOfferDialog(quote: quoteData),
      );
      if (accepted != true || !mounted) return;
      await widget.action(() => const EarthApi()
          .originateBankLoan(
              amount: result['amount']!,
              termDays: int.parse(result['term']!))
          .then((_) => const EarthApi().world()));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _repay(HouseLoan loan) async {
    final principal = loan.outstandingPrincipalUnits;
    final interest = loan.accruedInterestUnits;
    final total = principal + interest;
    final amount = await showDialog<String>(
      context: context,
      builder: (_) => _LoanRepaymentDialog(
          totalDue: total, availableToSpend: widget.availableToSpend),
    );
    if (amount == null || !mounted) return;
    try {
      await widget.action(() => const EarthApi()
          .repayBankLoan(loan.id, amount: amount)
          .then((_) => const EarthApi().world()));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => EarthSection(
        title: 'BANK CREDIT',
        showSurface: true,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              'Borrow against eligible House cashflow and collateral. Review the bank offer before accepting.',
              style: context.widgetFooterStyle),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Bank service is temporarily unavailable. Please try again.',
                style: TextStyle(color: context.warningColor)),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _loans.isEmpty)
            const Text('No active loans. Request a quote before borrowing.',
                style: TextStyle(color: mutedColor)),
          for (final loan in _loans)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Text(
                              '${loan.status} · principal ${_creditText(loan.outstandingPrincipalUnits)}\nInterest ${_creditText(loan.accruedInterestUnits)} · ${_countdown(loan.nextPaymentGameDay ?? loan.maturityGameDay, widget.currentDay)}')),
                      TextButton(
                          onPressed: loan.status == 'PAID'
                              ? null
                              : () => _repay(loan),
                          child: const Text('REPAY'))
                    ])),
          const SizedBox(height: 10),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: EarthButton(
                  label: 'REQUEST LOAN QUOTE',
                  icon: Icons.request_quote_outlined,
                  onPressed: _loading ? null : _borrow)),
        ]),
      );

  String _countdown(int? dueDay, int currentDay) {
    if (dueDay == null) return 'payment date unavailable';
    if (dueDay <= currentDay) return 'DUE NOW';
    return 'due in ${dueDay - currentDay} game day${dueDay - currentDay == 1 ? '' : 's'}';
  }
}

class _LoanDialog extends StatefulWidget {
  const _LoanDialog();
  @override
  State<_LoanDialog> createState() => _LoanDialogState();
}

class _LoanDialogState extends State<_LoanDialog> {
  final _amount = TextEditingController();
  final _term = TextEditingController(text: '30');
  @override
  void dispose() {
    _amount.dispose();
    _term.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('REQUEST BANK LOAN'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Requested amount (CREDIT)')),
          TextField(
              controller: _term,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Term in game days'))
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () {
                if (RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(_amount.text.trim()) &&
                    RegExp(r'^\d+$').hasMatch(_term.text.trim())) {
                  Navigator.pop(context, {
                    'amount': _amount.text.trim(),
                    'term': _term.text.trim()
                  });
                }
              },
              child: const Text('GET QUOTE'))
        ],
      );
}

class _LoanOfferDialog extends StatelessWidget {
  final Map<String, dynamic> quote;
  const _LoanOfferDialog({required this.quote});

  @override
  Widget build(BuildContext context) {
    final requested = quote['requestedUnits'] ?? '0';
    final interest = quote['estimatedInterestUnits'] ?? '—';
    final total = quote['estimatedTotalRepaymentUnits'] ?? '—';
    final rate = quote['rateBps'] ?? '—';
    return AlertDialog(
      title: const Text('LOAN OFFER'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _offerRow('You receive', _creditText(requested)),
        _offerRow('Estimated financing cost', _creditText(interest)),
        _offerRow('Estimated total repayment', _creditText(total)),
        _offerRow('Rate', '$rate bps'),
        _offerRow('Term', '${quote['termDays'] ?? '—'} game days'),
        _offerRow('Maturity', 'Day ${quote['maturityGameDay'] ?? '—'}'),
        const SizedBox(height: 12),
        const Text(
            'The loan is created only after you explicitly accept this offer.',
            style: TextStyle(fontSize: 12)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ACCEPT LOAN')),
      ],
    );
  }

  Widget _offerRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _LoanRepaymentDialog extends StatefulWidget {
  final BigInt totalDue;
  final BigInt availableToSpend;
  const _LoanRepaymentDialog(
      {required this.totalDue, required this.availableToSpend});

  @override
  State<_LoanRepaymentDialog> createState() => _LoanRepaymentDialogState();
}

class _LoanRepaymentDialogState extends State<_LoanRepaymentDialog> {
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _creditDecimal(widget.totalDue));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _parseCreditInput(_amount.text.trim());
    final valid = value != null && value > BigInt.zero &&
        value <= widget.totalDue &&
        value <= widget.availableToSpend;
    return AlertDialog(
      title: const Text('REPAY LOAN'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
            'Available to spend: ${formatCreditUnits(widget.availableToSpend)}'),
        Text('Total due: ${formatCreditUnits(widget.totalDue)}'),
        TextField(
          controller: _amount,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Payment amount (CREDIT)'),
        ),
        if (!valid)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Enter an amount within the available balance and total due.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: valid
                ? () => Navigator.pop(context, _creditDecimal(value!))
                : null,
            child: const Text('CONFIRM PAYMENT')),
      ],
    );
  }
}

class _FinanceActivityCard extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  const _FinanceActivityCard({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return EarthSection(
      title: 'HISTORICAL CASHFLOW',
      showSurface: true,
      child: transactions.isEmpty
          ? const Text('No recorded House transactions yet.',
              style: TextStyle(color: mutedColor))
          : Column(
              children: transactions.take(20).map((tx) {
                final delta = _creditUnits(tx['delta_units']);
                final display = delta == null
                    ? '—'
                    : _signedCreditText(delta);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(tx['transaction_kind']?.toString() ?? 'Transaction'),
                  subtitle: Text('Day ${tx['game_day'] ?? '—'}'),
                  trailing: Text(display,
                      style: TextStyle(
                          color: delta != null && delta < BigInt.zero
                              ? Colors.redAccent
                              : Colors.tealAccent)),
                );
              }).toList(),
            ),
    );
  }
}

class _BankDepositsCard extends StatefulWidget {
  final List<HouseDeposit> deposits;
  final BigInt liquidCredits;
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
  static const List<int> _terms = [1, 7, 30, 90];

  final TextEditingController _amountController =
      TextEditingController(text: '100');
  int _selectedTermDays = 30;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  BigInt? get _enteredAmount => _parseCreditInput(_amountController.text);
  Future<void> _showDepositReviewDialog(BuildContext context) async {
    final amount = _enteredAmount;
    if (amount == null || amount <= BigInt.zero) return;
    final termDays = _selectedTermDays;
    Map<String, dynamic> quote = const {};
    try {
      final response = await const EarthApi().bankDepositQuote(
          amount: _creditDecimal(amount), termDays: termDays);
      quote = response['quote'] is Map
          ? Map<String, dynamic>.from(response['quote'] as Map)
          : const <String, dynamic>{};
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The bank could not provide an authoritative quote.')));
      }
      return;
    }
    final maturityDay = widget.currentDay + termDays;
    final remainingCredits = amount == null ? null : widget.liquidCredits - amount;
    final isAffordable = amount != null && amount > BigInt.zero && remainingCredits! >= BigInt.zero;
    final deficit = amount == null ? BigInt.zero : amount - widget.liquidCredits;

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
              const Icon(Icons.account_balance_outlined,
                  color: EarthResourceColors.credits, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Confirm Bank Deposit',
                    style: context.topicTitleStyle
                        .copyWith(color: context.inkColor)),
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
                _reviewRow(dialogContext, 'Estimated interest',
                    quote['estimatedInterest']?.toString() ?? 'UNAVAILABLE'),
                _reviewRow(dialogContext, 'Estimated payout',
                    quote['estimatedPayout']?.toString() ?? 'UNAVAILABLE',
                    isBold: true),
                _reviewRow(dialogContext, 'Rate',
                    '${quote['rateBps'] ?? 'UNAVAILABLE'} bps'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    children: [
                      _reviewRow(dialogContext, 'Deposit amount',
                          _creditText(amount),
                          isBold: true),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Available after deposit',
                          _creditText(remainingCredits == null || remainingCredits < BigInt.zero ? BigInt.zero : remainingCredits),
                          color: remainingCredits != null && remainingCredits < BigInt.zero
                              ? context.errorColor
                              : context.inkColor),
                      const SizedBox(height: 8),
                      _reviewRow(
                          dialogContext, 'Lock-up term', '$termDays game days'),
                      const SizedBox(height: 8),
                      _reviewRow(
                          dialogContext,
                          'Current game time',
                          formatGameDateTime(
                              widget.currentDay, widget.currentMinute)),
                      const SizedBox(height: 8),
                      _reviewRow(
                          dialogContext,
                          'Maturity',
                          formatGameDateTime(
                              maturityDay, widget.currentMinute)),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Interest',
                          'Variable; realized at maturity',
                          color: context.successColor),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!isAffordable) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.errorColor.withValues(alpha: .12),
                      borderRadius:
                          BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                          color: context.errorColor.withValues(alpha: .3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 16, color: context.errorColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            amount == null || amount <= BigInt.zero
                                ? 'Please enter a valid deposit amount greater than 0.'
                                : 'Insufficient available CREDIT. You need ${_creditText(deficit)} more.',
                            style: context.captionStyle
                                .copyWith(color: context.errorColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Returns depend on realized bank income and settlement. The bank records the realized amount when the deposit matures.',
                  style: context.captionStyle
                      .copyWith(color: context.mutedColor, height: 1.35),
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

    if (confirmed == true && amount != null) {
      await _executeDeposit(amount, termDays);
    }
  }

  Future<void> _executeDeposit(BigInt amount, int termDays) async {
    setState(() => _submitting = true);
    try {
      EarthAudioEngine.instance.playCash();
      await widget.action(() async {
        await const EarthApi().createBankDeposit(
            amount: _creditDecimal(amount), termDays: termDays);
        return const EarthApi().world();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Successfully deposited ${_creditText(amount)} for $termDays days.'),
            backgroundColor: context.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Deposit failed. Please try again.'),
            backgroundColor: context.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _promptWithdraw(HouseDeposit deposit) async {
    final depositId = deposit.id;
    final principal = deposit.principalUnits;
    final interest = deposit.accruedInterestUnits;
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
              const Icon(Icons.download_done_rounded,
                  color: Colors.tealAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Withdraw Matured Deposit',
                    style: context.topicTitleStyle
                        .copyWith(color: context.inkColor)),
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
                      _reviewRow(dialogContext, 'Principal return',
                          _creditText(principal)),
                      const SizedBox(height: 8),
                      _reviewRow(dialogContext, 'Realized interest',
                          _signedCreditText(interest),
                          color: context.successColor),
                      const Divider(height: 18, color: Colors.white10),
                      _reviewRow(
                        dialogContext,
                        'Total Liquid Credit Payout',
                        _creditText(totalPayout),
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
              content: Text(
                  'Successfully withdrawn ${_creditText(totalPayout)} to your liquid balance.'),
              backgroundColor: context.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Withdrawal failed. Please try again.'),
              backgroundColor: context.errorColor,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    }
  }

  Widget _reviewRow(BuildContext ctx, String label, String value,
      {bool isBold = false, Color? color}) {
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
      final status = d.status.toLowerCase();
      final maturityDay = d.maturityGameDay ?? widget.currentDay + 1;
      return status == 'active' && widget.currentDay < maturityDay;
    }).toList();
    final activePrincipal = activeDeposits.fold<BigInt>(
        BigInt.zero, (sum, d) => sum + d.principalUnits);
    final activeAccruedInterest = activeDeposits.fold<BigInt>(
        BigInt.zero, (sum, d) => sum + d.accruedInterestUnits);
    final maturedAwaitingWithdrawal = widget.deposits.where((d) {
      return d.status.toLowerCase() == 'matured';
    }).fold<BigInt>(BigInt.zero, (sum, d) => sum + d.principalUnits);

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
            totalPrincipal: activePrincipal,
            accruedInterest: activeAccruedInterest,
            maturedAwaitingWithdrawal: maturedAwaitingWithdrawal,
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
    required BigInt liquidCredits,
    required BigInt totalPrincipal,
    required BigInt accruedInterest,
    required BigInt maturedAwaitingWithdrawal,
    required int activeDepositCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('OVERVIEW',
                style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
            const EarthBadge(
              label: 'SAVINGS',
              variant: EarthBadgeVariant.neutral,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            final tiles = [
              _metricBox(
                  context,
                  'Available to spend',
                  _creditText(liquidCredits),
                  Icons.account_balance_wallet_outlined,
                  EarthResourceColors.credits),
              _metricBox(
                  context,
                  'Active principal',
                  _creditText(totalPrincipal),
                  Icons.lock_clock_outlined,
                  context.primaryColor),
              _metricBox(
                  context,
                  'Active accrued interest',
                  _signedCreditText(accruedInterest),
                  Icons.trending_up,
                  context.successColor),
              _metricBox(
                  context,
                  'Matured awaiting withdrawal',
                  _creditText(maturedAwaitingWithdrawal),
                  Icons.download_done_outlined,
                  context.secondaryColor),
              _metricBox(context, 'Active deposits', '$activeDepositCount',
                  Icons.receipt_long_outlined, context.secondaryColor),
            ];

            if (isNarrow) {
              return Column(
                children: [
                  Row(children: [
                    Expanded(child: tiles[0]),
                    const SizedBox(width: 10),
                    Expanded(child: tiles[1])
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: tiles[2]),
                    const SizedBox(width: 10),
                    Expanded(child: tiles[3])
                  ]),
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
                  style: context.captionStyle
                      .copyWith(color: context.mutedColor, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricBox(BuildContext context, String label, String value,
      IconData icon, Color color) {
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
                  style: context.captionStyle
                      .copyWith(color: context.mutedColor, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.widgetTitleStyle
                .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositFundsSection(BuildContext context) {
    final amount = _enteredAmount;
    final termDays = _selectedTermDays;
    final maturityDay = widget.currentDay + termDays;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DEPOSIT FUNDS',
            style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
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
                                Text('Yield: ',
                                    style: context.bodyStyle.copyWith(
                                        color: context.mutedColor,
                                        fontSize: 12)),
                                Text(
                                  'Variable; realized at maturity',
                                  style: context.bodyStyle.copyWith(
                                      color: context.successColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Maturity: Game Day $maturityDay · Returns depend on realized bank income and settlement.',
                              style: context.captionStyle.copyWith(
                                  color: context.mutedColor, fontSize: 10.5),
                            ),
                            const SizedBox(height: 12),
                            EarthButton(
                              label: 'MAKE DEPOSIT',
                              icon: Icons.add_circle_outline,
                              variant: EarthButtonVariant.primary,
                              isLoading: _submitting,
                              onPressed: _submitting || amount == null || amount <= BigInt.zero
                                  ? null
                                  : () => _showDepositReviewDialog(context),
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
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text('Yield: ',
                                          style: context.bodyStyle.copyWith(
                                              color: context.mutedColor,
                                              fontSize: 12)),
                                      Text(
                                        'Variable; realized at maturity',
                                        style: context.bodyStyle.copyWith(
                                            color: context.successColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Maturity: Game Day $maturityDay · Returns depend on realized bank income and settlement.',
                                    style: context.captionStyle.copyWith(
                                        color: context.mutedColor,
                                        fontSize: 10.5),
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
                              onPressed: _submitting || amount == null || amount <= BigInt.zero
                                  ? null
                                  : () => _showDepositReviewDialog(context),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Deposited credits cannot be withdrawn before maturity.',
                        style: context.captionStyle
                            .copyWith(color: Colors.orangeAccent, fontSize: 11),
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
        Text('Deposit Amount (Credits)',
            style: context.captionStyle.copyWith(color: context.mutedColor)),
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
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: EarthResourceColors.credits),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style:
                      context.bodyStyle.copyWith(fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Enter amount...',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text('C',
                  style: context.bodyStyle.copyWith(
                      color: context.mutedColor, fontWeight: FontWeight.bold)),
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
        Text('Term Length (Game Days)',
            style: context.captionStyle.copyWith(color: context.mutedColor)),
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
                      color: isSelected
                          ? context.primaryColor.withValues(alpha: .15)
                          : context.surfaceColor,
                      borderRadius:
                          BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                        color: isSelected
                            ? context.primaryColor
                            : context.subtleBorderColor,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '$term d',
                      style: context.bodyStyle.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? context.primaryColor
                            : context.mutedColor,
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
            Text('MY DEPOSITS',
                style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
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
                Icon(Icons.savings_outlined,
                    size: 28, color: context.mutedColor),
                const SizedBox(height: 8),
                Text(
                  'No active deposits. Deposit credits to earn potential interest over a selected term.',
                  textAlign: TextAlign.center,
                  style: context.bodyStyle
                      .copyWith(color: context.mutedColor, fontSize: 12),
                ),
              ],
            ),
          )
        else
          Column(
            children: deposits
                .map((deposit) => _buildDepositRow(context, deposit))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildDepositRow(BuildContext context, HouseDeposit deposit) {
    final principal = deposit.principalUnits;
    final interest = deposit.accruedInterestUnits;
    final startDay = deposit.startGameDay ?? 1;
    final startMinute = deposit.startGameMinute ?? 0;
    final maturityDay = deposit.maturityGameDay ?? startDay + 1;
    final maturityMinute = deposit.maturityGameMinute ?? startMinute;
    final rawStatus = deposit.status.toLowerCase();

    final isMaturedByTime =
        (widget.currentDay - 1) * 1440 + widget.currentMinute >=
            (maturityDay - 1) * 1440 + maturityMinute;
    final isWithdrawn = rawStatus == 'withdrawn';
    final isCancelled = rawStatus == 'cancelled';
    final isMatured = rawStatus == 'matured' ||
        (!isWithdrawn && !isCancelled && isMaturedByTime);

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
    final progress =
        isWithdrawn ? 1.0 : (elapsedDays / totalDays).clamp(0.0, 1.0);

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
              const Icon(Icons.account_balance_outlined,
                  size: 18, color: EarthResourceColors.credits),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _creditText(principal),
                      style: context.widgetTitleStyle
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text.rich(
                      TextSpan(
                        text: 'Accrued interest: ',
                        style: context.captionStyle
                            .copyWith(color: context.mutedColor, fontSize: 11),
                        children: [
                          TextSpan(
                            text:
                                _signedCreditText(interest),
                            style: context.captionStyle.copyWith(
                                color: context.successColor, fontSize: 11),
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
                key: ValueKey('deposit-progress-${deposit.id}'),
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
                  style: context.captionStyle
                      .copyWith(color: context.mutedColor, fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatGameDateTime(maturityDay, maturityMinute),
                  textAlign: TextAlign.end,
                  style: context.captionStyle.copyWith(
                    color: isMatured && !isWithdrawn
                        ? context.successColor
                        : context.mutedColor,
                    fontWeight: isMatured && !isWithdrawn
                        ? FontWeight.bold
                        : FontWeight.normal,
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
  final Map<String, dynamic> nextSettlement;

  const _CreditIncomeSummaryCard({
    required this.nextSettlement,
  });

  @override
  Widget build(BuildContext context) {
    final rows = (nextSettlement['items'] as List? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();
    final inflow = _creditUnits(nextSettlement['inflowsUnits']);
    final outflow = _creditUnits(nextSettlement['outflowsUnits']);
    final net = _creditUnits(nextSettlement['netCashflowUnits']);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEXT SETTLEMENT FORECAST', style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
        const SizedBox(height: 12),
        _row(context, 'Predictable inflows', inflow),
        ...rows.where((row) => row['direction'] == 'INFLOW').map((row) => _row(
              context,
              _label(row['category']),
              _creditUnits(row['amountUnits']),
              detail: true,
            )),
        _row(context, 'Known outflows', outflow, negative: true),
        ...rows.where((row) => row['direction'] == 'OUTFLOW').map((row) => _row(
              context,
              _label(row['category']),
              _creditUnits(row['amountUnits']),
              detail: true,
              negative: true,
            )),
        const Divider(height: 20),
        _row(context, 'Net', net, bold: true),
      ]),
    );
  }

  String _label(dynamic value) => switch (value?.toString()) {
        'TAX' => 'Taxes',
        'CAPACITY_RENT' => 'Capacity rent',
        'BUILDING_OPERATING_EXPENSE' => 'Building operations',
        'DEBT_SERVICE' => 'Debt service',
        'BANK_INTEREST' => 'Bank interest',
        'LICENSE' => 'Licenses',
        _ => value?.toString() ?? 'Scheduled item',
      };

  Widget _row(BuildContext context, String label, BigInt? value,
      {bool detail = false, bool negative = false, bool bold = false}) {
    final display = value == null
        ? 'UNAVAILABLE'
        : '${negative ? '-' : ''}${formatCreditUnits(value.abs())}';
    return Padding(
      padding: EdgeInsets.only(bottom: detail ? 6 : 8),
      child: Row(children: [
        Expanded(child: Text(label, style: context.bodyStyle.copyWith(
          color: detail ? context.mutedColor : context.inkColor,
          fontSize: detail ? 11 : 13,
          fontWeight: bold || !detail ? FontWeight.w800 : FontWeight.w600,
        ))),
        Text(display, style: context.bodyStyle.copyWith(
          color: negative ? context.errorColor : context.inkColor,
          fontWeight: FontWeight.w800,
        )),
      ]),
    );
  }
}
