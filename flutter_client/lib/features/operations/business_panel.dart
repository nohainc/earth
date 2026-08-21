import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'business_dialogs.dart';

class BusinessManagerOverviewPanel extends StatelessWidget {
  final EarthState state;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final Map<String, dynamic>? activeBusiness;

  const BusinessManagerOverviewPanel(
      {super.key,
      required this.state,
      this.businessFinancials = const {},
      this.businessProfile = const {},
      this.activeBusiness});

  @override
  Widget build(BuildContext context) {
    final business = activeBusiness ?? state.business;
    final businessId = business['id']?.toString();
    final fin = businessFinancials['business'] is Map
        ? Map<String, dynamic>.from(businessFinancials['business'] as Map)
        : businessFinancials;
    final name =
        (business['name'] ?? businessProfile['name'] ?? 'Business').toString();
    final status = (business['status'] ?? 'active').toString().toUpperCase();
    final revenue = asDouble(fin['revenue']);
    final costs = asDouble(fin['operating_costs'] ?? fin['costs']);
    final profit = asDouble(fin['profit']) ??
        (revenue != null && costs != null ? revenue - costs : null);
    final cash = asDouble(fin['cash'] ?? fin['balance'] ?? business['cash']);
    final payroll = asDouble(fin['payroll']);
    final workforce = state.json['workforce'] is List
        ? (state.json['workforce'] as List)
            .whereType<Map>()
            .where((item) => item['status']?.toString() == 'active' && (businessId == null || item['business_id'] == null || item['business_id']?.toString() == businessId))
            .length
        : 0;
    final machineCount = state.machines.whereType<Map>().where((item) => businessId == null || item['business_id'] == null || item['business_id']?.toString() == businessId).length;
    final policy = (business['policy'] ??
            businessProfile['policy'] ??
            'No operating direction chosen')
        .toString();
    final bottlenecks = <String>[];
    if (workforce == 0) bottlenecks.add('staffing');
    if (machineCount == 0) bottlenecks.add('machine capacity');
    if (profit != null && profit < 0) bottlenecks.add('cost control');

    return EarthPanel(
        title: 'MANAGER\'S BRIEF / $name',
        showSurface: false,
        contentPadding: EdgeInsets.zero,
        helpAfterTitle: true,
        titleColor: mutedColor,
        infoDescription:
            '• The decision view for running this business: strategy, people, capacity, cash, and risks.\n\n• Detailed machine controls, AI settings, and production history remain in specialist views.\n\n• Values are shown only when current business data is available.',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              status == 'ACTIVE'
                  ? 'The operation is active. Choose the next investment or protect the current margin.'
                  : 'The operation needs attention before it can safely expand.',
              style: TextStyle(
                  color: status == 'ACTIVE'
                      ? Colors.tealAccent
                      : Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric(
                'PROFIT / CYCLE',
                profit == null
                    ? 'UNAVAILABLE'
                    : '${formatWholeNumber(profit)} C',
                Icons.trending_up_outlined,
                profit == null || profit >= 0
                    ? Colors.tealAccent
                    : Colors.orangeAccent),
            _metric(
                'CASH RUNWAY',
                cash == null || payroll == null || payroll <= 0
                    ? 'UNAVAILABLE'
                    : '${(cash / payroll).floor()} cycles',
                Icons.account_balance_wallet_outlined,
                cyanAccentColor),
            _metric('ACTIVE STAFF', '$workforce', Icons.groups_outlined,
                violetColor),
            _metric('MACHINE CAPACITY', '$machineCount',
                Icons.precision_manufacturing_outlined, Colors.amberAccent),
          ]),
          const SizedBox(height: 10),
          Text('STRATEGY: $policy',
              style: const TextStyle(
                  color: inkColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
              bottlenecks.isEmpty
                  ? 'No obvious bottleneck is recorded. Consider expansion, staff development, technology adoption, or a stronger contract.'
                  : 'Needs attention: ${bottlenecks.join(' · ')}',
              style: TextStyle(
                  color: bottlenecks.isEmpty ? mutedColor : Colors.orangeAccent,
                  fontSize: 10.5)),
          const SizedBox(height: 8),
          const Text(
              'Next decisions: hire · train · repair · buy supplies · accept work · adopt technology · expand · conserve cash.',
              style: TextStyle(color: mutedColor, fontSize: 10.5)),
        ]));
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Container(
          width: 150,
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

Widget _businessTopicHeading(BuildContext context, String title,
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

class BusinessPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final Map<String, dynamic>? activeBusiness;
  final ValueChanged<String>? onSelectBusiness;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const BusinessPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.businessOwnership,
    required this.businessFinancials,
    required this.businessProfile,
    this.activeBusiness,
    this.onSelectBusiness,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final business = activeBusiness ?? state.business;
    final businessId = business['id']?.toString() ?? 'B-1048';
    final businessName =
        (business['name'] as String?)?.toUpperCase() ?? 'KLINE WORKS';
    final status = (business['status']?.toString() ?? 'active').toLowerCase();
    final condition = asIntOr(business['condition'], 96);
    final activePolicy =
        (business['policy']?.toString() ?? 'reliability').toLowerCase();
    final portfolio = state.businesses;

    final finMap = businessFinancials['business'] is Map<String, dynamic>
        ? (businessFinancials['business'] as Map<String, dynamic>)
        : business;

    final revenue = asDoubleOr(finMap['revenue'], 1240.0);
    final operatingCosts =
        asDoubleOr(finMap['operating_costs'] ?? finMap['costs'], 820.0);
    final profit = asDoubleOr(finMap['profit'], revenue - operatingCosts);
    final taxedRevenue = asDoubleOr(finMap['taxed_revenue'], revenue);
    final lastGameDay = finMap['last_game_day'] ?? state.clock['day'] ?? 184;
    final managerName = business['manager_name']?.toString() ?? 'You';
    final managerId = business['manager_id']?.toString();
    final workforce = (state.json['workforce'] is List
            ? state.json['workforce'] as List
            : const [])
        .whereType<Map>()
        .where((employee) => employee['status']?.toString() == 'active' && (businessId == null || employee['business_id'] == null || employee['business_id']?.toString() == businessId))
        .toList();
    final payroll = workforce.fold<double>(
        0, (sum, employee) => sum + asDoubleOr(employee['wage'], 0));

    final profitMargin = revenue > 0 ? (profit / revenue) * 100 : 0.0;
    final costRatio =
        revenue > 0 ? (operatingCosts / revenue).clamp(0.0, 1.0) : 0.66;
    final profitRatio = (1.0 - costRatio).clamp(0.0, 1.0);

    final isDistressed = status == 'distressed';
    final isInsolvent = status == 'insolvent';
    final isDissolved = status == 'dissolved';

    Color statusColor = cyanAccentColor;
    if (isDistressed) statusColor = Colors.orangeAccent;
    if (isInsolvent || isDissolved) statusColor = Colors.redAccent;

    final holders = (businessOwnership['holders'] is List
        ? businessOwnership['holders'] as List
        : []);
    final totalShares = asIntOr(
        businessOwnership['totalIssuedShares'] ??
            business['total_issued_shares'],
        1000);
    final controllingId = businessOwnership['controllingHumanId']?.toString() ??
        business['controlling_human_id']?.toString() ??
        'H-0044';

    final shareholderThreshold =
        asDoubleOr(business['shareholder_vote_threshold'], 0.5);
    final boardThreshold =
        asDoubleOr(business['board_approval_threshold'], 0.5);
    final dilutionNoticeDays = asIntOr(business['dilution_notice_days'], 3);

    return EarthPanel(
      key: panelKey,
      title: 'ENTERPRISE OPERATIONS / $businessName',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Executive Entity Identity: Entity ID, sector classification, live corporate status (Active / Distressed / Insolvent), and machine fleet health score.\n\n• Unit Economics & Financial Statement:\n  - OPERATING REVENUE: Gross product sales from market batches and executed contracts.\n  - OPERATING COSTS: Combined raw inputs, power, maintenance reserves, and civic taxes.\n  - NET PROFIT / CYCLE: Net operating income with margin % and cost structure ratio breakdown.\n  - TAX ASSESSMENT BASE: Audited canonical taxable turnover.\n\n• Cap Table & Governance: Share distribution across equity holders, controller designation, and constitutional thresholds (Shareholder vote %, Board approval %, Dilution notice days).\n\n• Corporate Action Hub: Execute dividend distributions, equity transfers, share issuance, mergers, managerial appointments, and enterprise liquidation.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width >= 800;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _businessTopicHeading(
                context,
                'ENTERPRISE OPERATIONS / $businessName',
                description:
                    '• Executive Entity Identity: Entity ID, sector classification, live corporate status (Active / Distressed / Insolvent), and machine fleet health score.',
              ),
              if (portfolio.length > 1) ...[
                _businessPortfolio(portfolio),
                const SizedBox(height: 12),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      violetColor.withValues(alpha: .18),
                      surfaceColor.withValues(alpha: .72),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: violetColor.withValues(alpha: .35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag_outlined, color: cyanAccentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MANAGER\'S BRIEF',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: cyanAccentColor,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            profit >= 0
                                ? 'The operation is generating value. Protect its margin, then decide where the next credit should go.'
                                : 'The operation is losing value. Stabilize costs and capacity before expanding.',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Manager: $managerName${managerId == null ? '' : ' · $managerId'} · Last settled cycle: Day $lastGameDay',
                            style: const TextStyle(
                                fontSize: 10, color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _businessTopicHeading(
                context,
                'WORKFORCE / OPERATING CAPACITY',
                description:
                    '• Staff are part of the business, not abstract analytics. Their skills and morale affect the organization\'s ability to deliver work.\n• Payroll is a recurring operating cost.\n• Hire for a role, train valuable staff, or dismiss underperformers as the business changes.',
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${workforce.length} active staff',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                            Text(
                                '${formatCreditsAmount(payroll)} / cycle payroll',
                                style: const TextStyle(
                                    fontSize: 10, color: mutedColor)),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => showHireEmployeeDialog(
                                  context, action, businessId),
                          icon: const Icon(Icons.person_add_alt_1, size: 14),
                          label: const Text('HIRE',
                              style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (workforce.isEmpty)
                      const Text(
                        'No staff are assigned yet. The operation is currently machine-led.',
                        style: TextStyle(fontSize: 11, color: mutedColor),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: workforce.map((employee) {
                          final role = employee['role']?.toString() ?? 'Staff';
                          final name =
                              employee['name']?.toString() ?? 'Employee';
                          final employeeId = employee['id']?.toString() ?? '';
                          final skill =
                              (asDouble(employee['skill']) ?? 0) * 100;
                          final morale =
                              (asDouble(employee['morale']) ?? 0) * 100;
                          return Container(
                            width: 210,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .035),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(role,
                                    style: const TextStyle(
                                        fontSize: 10, color: mutedColor)),
                                const SizedBox(height: 7),
                                Text(
                                    'Skill ${skill.toStringAsFixed(0)}% · Morale ${morale.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        fontSize: 9.5, color: cyanAccentColor)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    TextButton(
                                      onPressed: busy || employeeId.isEmpty
                                          ? null
                                          : () => action(() => const EarthApi()
                                              .trainEmployee(
                                                  businessId, employeeId)),
                                      style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact),
                                      child: const Text('TRAIN',
                                          style: TextStyle(fontSize: 9)),
                                    ),
                                    TextButton(
                                      onPressed: busy || employeeId.isEmpty
                                          ? null
                                          : () => action(() => const EarthApi()
                                              .dismissEmployee(
                                                  businessId, employeeId)),
                                      style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: Colors.orangeAccent),
                                      child: const Text('DISMISS',
                                          style: TextStyle(fontSize: 9)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 34),

              // 1. EXECUTIVE ENTERPRISE HEADER CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: violetColor.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: violetColor.withValues(alpha: .4)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.domain_rounded,
                            size: 22,
                            color: cyanAccentColor,
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
                                    child: Text(
                                      businessName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                        color: inkColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: .15),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                          color: statusColor.withValues(
                                              alpha: .4)),
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
                                          status.toUpperCase(),
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
                                'ENTITY ID: $businessId  ·  SECTOR: ${(business['sector']?.toString() ?? 'MAINTENANCE').toUpperCase()}  ·  ASSESSED DAY $lastGameDay',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: mutedColor,
                                  letterSpacing: .5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Fleet condition & Policy Selector Row
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        // Fleet Health Meter
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'FLEET HEALTH:',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                                color: mutedColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (condition / 100.0).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    condition > 75
                                        ? cyanAccentColor
                                        : condition > 40
                                            ? Colors.orangeAccent
                                            : Colors.redAccent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$condition%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: condition > 75
                                    ? cyanAccentColor
                                    : condition > 40
                                        ? Colors.orangeAccent
                                        : Colors.redAccent,
                              ),
                            ),
                          ],
                        ),

                        // Operating Policy Selector
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'OPERATING POLICY:',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                                color: mutedColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            for (final policy in [
                              'reliability',
                              'margin',
                              'capacity'
                            ]) ...[
                              InkWell(
                                onTap: busy || isDissolved
                                    ? null
                                    : () => action(() =>
                                        const EarthApi().setPolicy(policy,
                                            businessId: businessId)),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4.5),
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: activePolicy == policy
                                        ? violetColor.withValues(alpha: .25)
                                        : Colors.white.withValues(alpha: .04),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: activePolicy == policy
                                          ? violetColor
                                          : Colors.white10,
                                    ),
                                  ),
                                  child: Text(
                                    policy.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: activePolicy == policy
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: activePolicy == policy
                                          ? inkColor
                                          : mutedColor,
                                      letterSpacing: .6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Distress / Insolvency Warning Banner (Conditional)
              if (isDistressed || isInsolvent) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: .4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isInsolvent
                                  ? 'CRITICAL: ENTERPRISE INSOLVENCY'
                                  : 'WARNING: FINANCIAL DISTRESS',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: .8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Operating expenditures exceed reserves. You are eligible for sovereign restructuring or authorized liquidation with machine asset recovery.',
                              style:
                                  TextStyle(fontSize: 10.5, color: mutedColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: busy
                            ? null
                            : () => showBusinessLiquidationDialog(
                                context, action, businessId),
                        child: const Text('LIQUIDATE',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 34),

              // 2. FINANCIAL STATEMENT & UNIT ECONOMICS
              _businessTopicHeading(
                context,
                'PERIOD FINANCIAL STATEMENT & UNIT ECONOMICS',
                description:
                    '• OPERATING REVENUE: Gross product sales from market batches and executed contracts.\n• OPERATING COSTS: Combined raw inputs, power, maintenance reserves, and civic taxes.\n• NET PROFIT / CYCLE: Net operating income with margin % and cost structure ratio breakdown.\n• TAX ASSESSMENT BASE: Audited canonical taxable turnover.',
              ),

              LayoutBuilder(
                builder: (context, finConstraints) {
                  final finWidth = finConstraints.maxWidth;
                  final is4Col = finWidth >= 900;
                  final is2Col = finWidth >= 500;
                  final itemWidth = is4Col
                      ? (finWidth - 36) / 4
                      : is2Col
                          ? (finWidth - 12) / 2
                          : finWidth;

                  final metrics = [
                    _metricBox(
                      width: itemWidth,
                      title: 'OPERATING REVENUE',
                      value: formatCreditsAmount(revenue),
                      subtext: 'Market sales & contracts',
                      accent: Colors.tealAccent,
                      icon: Icons.trending_up_rounded,
                    ),
                    _metricBox(
                      width: itemWidth,
                      title: 'OPERATING COSTS',
                      value: formatCreditsAmount(operatingCosts),
                      subtext: 'Inputs, maint & taxes',
                      accent: Colors.orangeAccent,
                      icon: Icons.trending_down_rounded,
                    ),
                    _metricBox(
                      width: itemWidth,
                      title: 'NET PROFIT / CYCLE',
                      value:
                          '${profit >= 0 ? '+' : ''}${formatCreditsAmount(profit)}',
                      subtext: 'Margin: ${profitMargin.toStringAsFixed(1)}%',
                      accent: profit >= 0 ? cyanAccentColor : Colors.redAccent,
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    _metricBox(
                      width: itemWidth,
                      title: 'TAX ASSESSMENT BASE',
                      value: formatCreditsAmount(taxedRevenue),
                      subtext: 'Audited canonical base',
                      accent: violetColor,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ];

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: metrics,
                  );
                },
              ),

              const SizedBox(height: 12),

              // Visual Profit vs Cost Ratio Bar
              Container(
                padding: const EdgeInsets.all(12),
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
                        const Text(
                          'MARGIN VS COST STRUCTURE',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                            color: mutedColor,
                          ),
                        ),
                        Text(
                          'OPERATING MARGIN: ${profitMargin.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: profit >= 0
                                ? cyanAccentColor
                                : Colors.redAccent,
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
                              flex: (costRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color:
                                    Colors.orangeAccent.withValues(alpha: .8),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              flex: (profitRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color: profit >= 0
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

              const SizedBox(height: 34),

              // 3. CAP TABLE & GOVERNANCE
              _businessTopicHeading(
                context,
                'CAP TABLE & CORPORATE GOVERNANCE',
                description:
                    '• Share distribution across equity holders, controller designation, and constitutional thresholds (Shareholder vote %, Board approval %, Dilution notice days).',
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pie_chart_outline,
                                size: 16, color: violetColor),
                            const SizedBox(width: 8),
                            Text(
                              'EQUITY DISTRIBUTION ($totalShares TOTAL SHARES)',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: .8,
                                color: inkColor,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: cyanAccentColor.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                color: cyanAccentColor.withValues(alpha: .3)),
                          ),
                          child: Text(
                            'CONTROLLER: $controllingId',
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .8,
                              color: cyanAccentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Multi-Shareholder Proportional Bar
                    if (holders.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          height: 10,
                          child: Row(
                            children: holders.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final holder =
                                  entry.value as Map<String, dynamic>;
                              final pct =
                                  asDoubleOr(holder['percentage'], 50.0);
                              final color = idx == 0
                                  ? violetColor
                                  : idx == 1
                                      ? cyanAccentColor
                                      : Colors.amberAccent;
                              return Expanded(
                                flex: pct.toInt().clamp(1, 100),
                                child: Container(
                                  margin: EdgeInsets.only(
                                      right: idx < holders.length - 1 ? 2 : 0),
                                  color: color,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Shareholders List & Governance Thresholds side by side or stacked
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _buildShareholderItems(
                                  holders, controllingId),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Container(
                            width: 1,
                            height: 100,
                            color: Colors.white12,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: _buildGovernanceRulesCard(
                              shareholderThreshold,
                              boardThreshold,
                              dilutionNoticeDays,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ..._buildShareholderItems(holders, controllingId),
                          const SizedBox(height: 16),
                          _buildGovernanceRulesCard(
                            shareholderThreshold,
                            boardThreshold,
                            dilutionNoticeDays,
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 34),

              // 4. ACTION TOOLBAR HUB
              _businessTopicHeading(
                context,
                'EXECUTIVE CORPORATE ACTIONS',
                description:
                    '• Execute dividend distributions, equity transfers, share issuance, mergers, managerial appointments, and enterprise liquidation.',
              ),

              // Categorized Action Groups
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. Capital & Equity Actions
                    _actionGroupTitle('CAPITAL & EQUITY'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionButton(
                          label: 'DISTRIBUTE DIVIDENDS',
                          icon: Icons.paid_outlined,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showDividendDialog(
                                  context, action, businessId),
                        ),
                        _actionButton(
                          label: 'TRANSFER SHARES',
                          icon: Icons.swap_horiz_rounded,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showShareTransferDialog(
                                  context, action, businessId),
                        ),
                        _actionButton(
                          label: 'ISSUE SHARES',
                          icon: Icons.add_circle_outline_rounded,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showShareIssueDialog(
                                  context, action, businessId),
                        ),
                        _actionButton(
                          label: 'PROPOSE MERGER',
                          icon: Icons.handshake_outlined,
                          onPressed: busy || isDissolved
                              ? null
                              : () =>
                                  showMergerDialog(context, action, businessId),
                        ),
                        _actionButton(
                          label: 'SHAREHOLDER RESOLUTION (>66.7%)',
                          icon: Icons.how_to_vote_outlined,
                          accentColor: violetColor,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showShareholderResolutionDialog(
                                  context, action, businessId),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // B. Governance & Control
                    _actionGroupTitle('GOVERNANCE & MANAGEMENT'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionButton(
                          label: 'CONSTITUTION & THRESHOLDS',
                          icon: Icons.gavel_outlined,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showBusinessConstitutionDialog(
                                  context, action, business),
                        ),
                        _actionButton(
                          label: 'APPOINT MANAGER',
                          icon: Icons.badge_outlined,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showBusinessManagerDialog(
                                  context, action, businessId),
                        ),
                        _actionButton(
                          label: 'AI OPERATIONAL ASSISTANT',
                          icon: Icons.smart_toy_outlined,
                          accentColor: cyanAccentColor,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showAiAssistantConfigDialog(
                                  context, action, businessId),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // C. Lifecycle Management
                    _actionGroupTitle('ENTERPRISE LIFECYCLE'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionButton(
                          label: 'NEW ENTERPRISE · 250 C',
                          icon: Icons.add_business_outlined,
                          accentColor: cyanAccentColor,
                          onPressed: busy
                              ? null
                              : () =>
                                  showBusinessComposerDialog(context, action),
                        ),
                        _actionButton(
                          label: 'RECEIVERSHIP & WORKOUT',
                          icon: Icons.account_balance_outlined,
                          accentColor: Colors.orangeAccent,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showReceivershipRestructuringDialog(
                                  context, action, businessId),
                        ),
                        _actionButton(
                          label: 'LIQUIDATE ENTERPRISE',
                          icon: Icons.delete_forever_outlined,
                          accentColor: Colors.redAccent,
                          onPressed: busy || isDissolved
                              ? null
                              : () => showBusinessLiquidationDialog(
                                  context, action, businessId),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildShareholderItems(
      List<dynamic> holders, String controllingId) {
    if (holders.isEmpty) {
      return [
        const Text('Single-member sole proprietorship.',
            style: TextStyle(fontSize: 11, color: mutedColor))
      ];
    }

    return holders.map((raw) {
      final holder = raw as Map<String, dynamic>;
      final humanId = holder['human_id']?.toString() ?? '';
      final name = holder['display_name']?.toString() ??
          (humanId.isNotEmpty ? humanId : 'Shareholder');
      final label =
          humanId.isNotEmpty && name != humanId ? '$name ($humanId)' : name;
      final shares = asIntOr(holder['shares'], 0);
      final percentage = asDoubleOr(holder['percentage'], 0.0);
      final isController = humanId.isNotEmpty && humanId == controllingId;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isController ? violetColor : cyanAccentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isController ? FontWeight.w700 : FontWeight.w500,
                  color: inkColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isController) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: violetColor.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: violetColor.withValues(alpha: .4)),
                ),
                child: const Text(
                  'CONTROLLER',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: violetColor,
                    letterSpacing: .6,
                  ),
                ),
              ),
            ],
            Text(
              '$shares shares  ·  ${percentage.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGovernanceRulesCard(
      double shareholderThreshold, double boardThreshold, int dilutionDays) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CONSTITUTIONAL THRESHOLDS',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
            color: mutedColor,
          ),
        ),
        const SizedBox(height: 6),
        _govRuleRow(
            'Shareholder Vote:', '${(shareholderThreshold * 100).toInt()}%'),
        const SizedBox(height: 3),
        _govRuleRow('Board Approval:', '${(boardThreshold * 100).toInt()}%'),
        const SizedBox(height: 3),
        _govRuleRow('Dilution Notice:', '$dilutionDays days'),
      ],
    );
  }

  Widget _govRuleRow(String label, String val) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: mutedColor)),
          Text(val,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: inkColor)),
        ],
      );

  Widget _metricBox({
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

  Widget _businessPortfolio(List<dynamic> businesses) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cyanAccentColor.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BUSINESS PORTFOLIO · ${businesses.length} OPERATIONS',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cyanAccentColor)),
        const SizedBox(height: 7),
        ...businesses.whereType<Map>().map((item) {
          final name = item['name']?.toString() ?? 'Unnamed operation';
          final status = (item['status']?.toString() ?? 'active').toUpperCase();
          final profit = item['profit'];
          final businessId = item['id']?.toString();
          return InkWell(
            onTap: businessId == null || onSelectBusiness == null ? null : () => onSelectBusiness!(businessId),
            child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              Icon(item['id']?.toString() == activeBusiness?['id']?.toString() ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 12, color: cyanAccentColor),
              const SizedBox(width: 5),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 10))),
              Text(status, style: const TextStyle(fontSize: 9, color: mutedColor)),
              if (profit != null) ...[
                const SizedBox(width: 8),
                Text('${formatWholeNumber(asDoubleOr(profit, 0))} C', style: const TextStyle(fontSize: 10, color: Colors.tealAccent)),
              ],
            ]),
          ));
        }),
      ]),
    );
  }

  Widget _actionGroupTitle(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: mutedColor.withValues(alpha: .85),
        ),
      );

  Widget _actionButton({
    required String label,
    required IconData icon,
    Color? accentColor,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor ?? inkColor,
        side: BorderSide(
            color: (accentColor ?? Colors.white).withValues(alpha: .2)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: accentColor ?? cyanAccentColor),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: .6,
          color: accentColor ?? inkColor,
        ),
      ),
    );
  }
}
