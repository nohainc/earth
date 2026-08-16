import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
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
    final businessName = (business['name'] as String?)?.toUpperCase() ?? 'KLINE WORKS';
    final status = (business['status']?.toString() ?? 'active').toLowerCase();
    final condition = (business['condition'] as num?)?.toInt() ?? 96;

    final finMap = businessFinancials['business'] is Map<String, dynamic>
        ? (businessFinancials['business'] as Map<String, dynamic>)
        : business;

    final revenue = (finMap['revenue'] as num?)?.toDouble() ?? 1240.0;
    final operatingCosts = (finMap['operating_costs'] as num?)?.toDouble() ?? 820.0;
    final profit = (finMap['profit'] as num?)?.toDouble() ?? (revenue - operatingCosts);
    final taxedRevenue = (finMap['taxed_revenue'] as num?)?.toDouble() ?? revenue;
    final lastGameDay = finMap['last_game_day'] ?? state.clock['day'] ?? 184;

    final isDistressed = status == 'distressed';
    final isInsolvent = status == 'insolvent';
    final isDissolved = status == 'dissolved';

    Color statusColor = cyanAccentColor;
    if (isDistressed) statusColor = Colors.orangeAccent;
    if (isInsolvent || isDissolved) statusColor = Colors.redAccent;

    final holders = (businessOwnership['holders'] is List ? businessOwnership['holders'] as List : []);

    return EarthPanel(
      key: panelKey,
      title: 'BUSINESS / $businessName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Policy: ${(business['policy']?.toString() ?? 'reliability').toUpperCase()} · Condition: $condition%',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Assessed Day $lastGameDay · Taxed Revenue: ${taxedRevenue.toStringAsFixed(1)} C',
                      style: const TextStyle(color: mutedColor, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Financial statement card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FINANCIAL STATEMENT (PERIOD ACTUALS)',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Text('Operating Revenue: ${revenue.toStringAsFixed(2)} C',
                    style: const TextStyle(fontSize: 11, color: mutedColor)),
                const SizedBox(height: 2),
                Text('Operating Costs: ${operatingCosts.toStringAsFixed(2)} C',
                    style: const TextStyle(fontSize: 11, color: mutedColor)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Operating Profit / Margin:',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    Text(
                      '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)} C',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: profit >= 0 ? cyanAccentColor : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isDistressed || isInsolvent) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isInsolvent ? 'CRITICAL: BUSINESS INSOLVENCY' : 'WARNING: FINANCIAL DISTRESS',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Operating costs exceed reserves. You are eligible for restructuring or authorized liquidation with machine asset preservation.',
                    style: TextStyle(fontSize: 10, color: mutedColor),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Ownership & Governance
          Text(
            'Control: ${businessOwnership['controllingHumanId'] ?? business['controlling_human_id'] ?? 'H-0044'} · ${businessOwnership['totalIssuedShares'] ?? business['total_issued_shares'] ?? 1000} issued shares',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (holders.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...holders.take(3).map((raw) {
              final holder = raw as Map<String, dynamic>;
              return Text(
                '· ${holder['display_name'] ?? holder['human_id']}: ${holder['percentage']}% (${holder['shares']} shares)',
                style: const TextStyle(fontSize: 10, color: mutedColor),
              );
            }),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showDividendDialog(context, action, businessId),
                child: const Text('DISTRIBUTE DIVIDENDS'),
              ),
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showShareTransferDialog(context, action),
                child: const Text('TRANSFER SHARES'),
              ),
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showShareIssueDialog(context, action, businessId),
                child: const Text('ISSUE SHARES'),
              ),
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showMergerDialog(context, action, businessId),
                child: const Text('PROPOSE MERGER'),
              ),
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showBusinessConstitutionDialog(context, action, business),
                child: const Text('CONSTITUTION'),
              ),
              OutlinedButton(
                onPressed: busy || isDissolved
                    ? null
                    : () => showBusinessManagerDialog(context, action, businessId),
                child: const Text('APPOINT MANAGER'),
              ),
              if (isDistressed || isInsolvent)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: busy
                      ? null
                      : () => showBusinessLiquidationDialog(context, action, businessId),
                  child: const Text('LIQUIDATE BUSINESS'),
                ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => showBusinessComposerDialog(context, action),
                child: const Text('NEW BUSINESS · 250 C'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              const Text('POLICY:', style: TextStyle(color: mutedColor, fontSize: 10, height: 2.2)),
              for (final policy in ['reliability', 'margin', 'capacity'])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    backgroundColor: (business['policy'] == policy) ? Colors.white12 : null,
                  ),
                  onPressed: busy || isDissolved
                      ? null
                      : () => action(() => const EarthApi().setPolicy(policy)),
                  child: Text(policy.toUpperCase(), style: const TextStyle(fontSize: 10)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
