import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'business_dialogs.dart';

class BusinessPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
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
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final business = state.business;
    final businessId = business['id']?.toString() ?? 'B-1048';
    final businessName =
        (business['name'] as String?)?.toUpperCase() ?? 'KLINE WORKS';
    final status = (business['status']?.toString() ?? 'active').toLowerCase();
    final condition = asIntOr(business['condition'], 96);
    final activePolicy =
        (business['policy']?.toString() ?? 'reliability').toLowerCase();

    final finMap = businessFinancials['business'] is Map<String, dynamic>
        ? (businessFinancials['business'] as Map<String, dynamic>)
        : business;

    final revenue = asDoubleOr(finMap['revenue'], 1240.0);
    final operatingCosts =
        asDoubleOr(finMap['operating_costs'] ?? finMap['costs'], 820.0);
    final profit = asDoubleOr(finMap['profit'], revenue - operatingCosts);
    final taxedRevenue = asDoubleOr(finMap['taxed_revenue'], revenue);
    final lastGameDay = finMap['last_game_day'] ?? state.clock['day'] ?? 184;

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
      infoDescription:
          '• Executive Entity Identity: Entity ID, sector classification, live corporate status (Active / Distressed / Insolvent), and machine fleet health score.\n\n• Unit Economics & Financial Statement:\n  - OPERATING REVENUE: Gross product sales from market batches and executed contracts.\n  - OPERATING COSTS: Combined raw inputs, power, maintenance reserves, and civic taxes.\n  - NET PROFIT / CYCLE: Net operating income with margin % and cost structure ratio breakdown.\n  - TAX ASSESSMENT BASE: Audited canonical taxable turnover.\n\n• Cap Table & Governance: Share distribution across equity holders, controller designation, and constitutional thresholds (Shareholder vote %, Board approval %, Dilution notice days).\n\n• Corporate Action Hub: Execute dividend distributions, equity transfers, share issuance, mergers, managerial appointments, and enterprise liquidation.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width >= 800;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                                          color: statusColor
                                              .withValues(alpha: .4)),
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
                                    : () => action(() => const EarthApi()
                                        .setPolicy(policy)),
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

              const SizedBox(height: 18),

              // 2. FINANCIAL STATEMENT & UNIT ECONOMICS
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'PERIOD FINANCIAL STATEMENT & UNIT ECONOMICS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                  ),
                ),
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
                        accent:
                            profit >= 0 ? cyanAccentColor : Colors.redAccent,
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
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // Visual Profit vs Cost Ratio Bar
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
                          'COST STRUCTURE VS PROFIT MARGIN',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                            color: mutedColor.withValues(alpha: .9),
                          ),
                        ),
                        Text(
                          '${(costRatio * 100).toStringAsFixed(0)}% Costs  ·  ${(profitRatio * 100).toStringAsFixed(0)}% Retained Profit',
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

              const SizedBox(height: 18),

              // 3. CAP TABLE & GOVERNANCE
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'CAP TABLE & CORPORATE GOVERNANCE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SHARE DISTRIBUTION ($totalShares TOTAL SHARES)',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                            color: mutedColor,
                          ),
                        ),
                        Text(
                          'CONTROLLER: $controllingId',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: cyanAccentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Multi-Shareholder Proportional Bar
                    if (holders.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
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
                      const SizedBox(height: 14),
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
                            height: 80,
                            color: Colors.white10,
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
                          const SizedBox(height: 14),
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

              const SizedBox(height: 20),

              // 4. ACTION TOOLBAR HUB
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'EXECUTIVE CORPORATE ACTIONS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: mutedColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),

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
                              : () => showShareTransferDialog(context, action),
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
                              : () => showMergerDialog(
                                  context, action, businessId),
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
                  fontWeight:
                      isController ? FontWeight.w700 : FontWeight.w500,
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
                  border:
                      Border.all(color: violetColor.withValues(alpha: .4)),
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
