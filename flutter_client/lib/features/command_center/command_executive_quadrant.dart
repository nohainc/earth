import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

class CommandExecutiveQuadrant extends StatelessWidget {
  final EarthState state;
  final ValueChanged<String>? onNavigate;

  const CommandExecutiveQuadrant({
    super.key,
    required this.state,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final activeBuildings = state.buildings.whereType<Map>().where((building) {
      return (building['status']?.toString().toLowerCase() ?? 'active') == 'active';
    }).length;
    final buildingName = activeBuildings == 0 ? 'NO ACTIVE BUILDINGS' : 'PRIVATE OPERATIONS';
    final condition = state.buildings
        .whereType<Map>()
        .map((b) => b['condition'] ?? b['health'] ?? b['integrity'])
        .whereType<num>()
        .toList();
    final averageCondition = condition.isEmpty
        ? null
        : condition.reduce((a, b) => a + b) / condition.length;
    final operations = state.json['operations'] is Map
        ? Map<String, dynamic>.from(state.json['operations'] as Map)
        : state.json['business'] is Map
            ? Map<String, dynamic>.from(state.json['business'] as Map)
            : const <String, dynamic>{};
    final profit = asDouble(operations['profit'] ?? operations['netProfit']);
    final policy = operations['policy']?.toString();

    final territoryRaw = state.residency['territory'] ?? state.institutions['territory'];
    final territory = territoryRaw is Map ? Map<String, dynamic>.from(territoryRaw) : <String, dynamic>{};
    final territoryName =
        (state.residency['territory_name'] ?? territory['name'] ?? 'NEW CARTHAGE')
            .toString()
            .toUpperCase();
    final territoryHealth = formatWholeNumber(
      territory['fiscal_health'] ?? territory['health'],
      fallback: 'UNAVAILABLE',
    );

    final marketProducts = state.market;
    String formatPrice(dynamic val) {
      if (val is Map) return formatPrice(val['price']);
      if (val is num) return val.toStringAsFixed(2);
      if (val is String && val.isNotEmpty) {
        final d = double.tryParse(val);
        if (d != null) return d.toStringAsFixed(2);
        return val;
      }
      return '—';
    }

    final rawComp = formatPrice(marketProducts['components']);
    final componentsPrice = rawComp;
    final rawEnergy = formatPrice(marketProducts['energy']);
    final energyPrice = rawEnergy;
    final rawMat = formatPrice(marketProducts['materials']);
    final materialsPrice = rawMat;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final numCols = availableWidth >= 1000
            ? 4
            : availableWidth >= 500
                ? 2
                : 1;
        final cardWidth = numCols == 1
            ? availableWidth
            : (availableWidth - (numCols - 1) * 16) / numCols;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'EXECUTIVE OVERVIEW',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                  color: mutedColor,
                ),
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                // 1. MARKET OVERVIEW CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '⌁',
                  iconColor: cyanAccentColor,
                  title: 'MARKET',
                  subtitle: 'UNIFORM BATCH SETTLEMENT',
                  infoDescription:
                      '• Spot Clearing Prices: Displays current clearing prices for key commodities (Components, Energy, Materials) settled per batch cycle.\n\n• Batch Auction Clearing: Periodic auctions aggregate discrete supply/demand curves to clear trades at a single non-arbitrage equilibrium price.\n\n• Action: Tap card to open Central Market to view full order books or submit limit orders.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Energy (NRG)', '$energyPrice C',
                          EarthResourceColors.energy),
                      const SizedBox(height: 5),
                      _rowMetric('Materials (ORE)', '$materialsPrice C',
                          EarthResourceColors.materials),
                      const SizedBox(height: 5),
                      _rowMetric('Components (MAT)', '$componentsPrice C',
                          EarthResourceColors.components),
                    ],
                  ),
                  onTap: () => onNavigate?.call('market'),
                ),

                // 2. BUSINESS & OPERATIONS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '◈',
                  iconColor: violetColor,
                  title: 'OPERATIONS',
                  subtitle: '$buildingName · $activeBuildings ACTIVE',
                  infoDescription:
                      '• Fleet Condition: Average structural integrity across all registered machinery. Drops below 50% risk severe downtime and emergency maintenance surcharges.\n\n• Projected Net P&L: Net credits earned per operating cycle after subtracting power, raw materials, and municipal taxes.\n\n• Operating Policy: Active dispatch strategy (Reliability, Margin, or Capacity) balancing output yield against wear rate.\n\n• Action: Tap card to manage unit economics, issue shares, distribute dividends, or tune policies.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                          'Building Condition',
                          averageCondition == null
                              ? 'UNAVAILABLE'
                              : '${averageCondition.toStringAsFixed(0)}%',
                          averageCondition != null && averageCondition < 50
                              ? Colors.orangeAccent
                              : cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                        'Projected Net P&L',
                        profit == null
                            ? 'UNAVAILABLE'
                            : '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(1)} C / cycle',
                        profit == null
                            ? mutedColor
                            : profit >= 0
                                ? cyanAccentColor
                                : Colors.redAccent,
                      ),
                      const SizedBox(height: 5),
                      _rowMetric('Operating Policy', policy ?? 'UNAVAILABLE', mutedColor),
                    ],
                  ),
                  onTap: () => onNavigate?.call('buildings'),
                ),

                // 3. TERRITORY COMMONS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '⊙',
                  iconColor: Colors.amberAccent,
                  title: territoryName,
                  subtitle: 'TERRITORY COMMONS · HEALTH $territoryHealth',
                  infoDescription:
                      '• Power Grid Stability: Percentage of total territorial electrical demand satisfied by local energy generation.\n\n• Housing & Slot Capacity: Available territorial lease slots preventing overcrowding.\n\n• Commons Dividend Yield: Shared territorial revenue returned to verified resident Houses.\n\n• Action: Tap card to inspect territory commons, slot leases, dividends, and residency relocation.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                          'Power Grid Stability',
                          _formatPercent(territory['power_grid_stability'] ??
                              territory['energy_coverage']),
                          cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Slot Capacity',
                          _formatPercent(territory['slot_capacity_available'] ??
                              territory['available_capacity']),
                          mutedColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Commons Dividend',
                          territory['commons_dividend']?.toString() ??
                              'UNAVAILABLE',
                          Colors.greenAccent),
                    ],
                  ),
                  onTap: () => onNavigate?.call('territory-commons'),
                ),

                // 4. FINANCE CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '§',
                  iconColor: Colors.tealAccent,
                  title: 'FINANCE',
                  subtitle: 'DOUBLE-ENTRY SETTLED LEDGER',
                  infoDescription:
                      '• Liquid Credits: Spendable funds available immediately for market orders and operating expenses.\n\n• Ledger Integrity: Real-time validation of double-entry transaction ledgers ensuring zero balance leakage.\n\n• Action: Tap card to open financial statements and transaction history.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Liquid Credits',
                          formatCreditsAmount(state.finance['balance'] ??
                              state.personalFinance['balance'] ??
                              state.human['credits']), violetColor),
                      const SizedBox(height: 5),
                      const SizedBox(height: 5),
                      _rowMetric('Ledger Integrity', 'Audited', cyanAccentColor),
                    ],
                  ),
                  onTap: () => onNavigate?.call('finance'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _rowMetric(String label, String value, Color valueColor) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: mutedColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      );

  String _formatPercent(dynamic value) {
    final parsed = asDouble(value);
    return parsed == null ? 'UNAVAILABLE' : '${parsed.toStringAsFixed(0)}%';
  }
}

class _ExecutiveCard extends StatelessWidget {
  final double width;
  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? infoDescription;
  final Widget body;
  final VoidCallback onTap;

  const _ExecutiveCard({
    required this.width,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.infoDescription,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      icon,
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: inkColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 9,
                            color: mutedColor,
                            letterSpacing: .8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (infoDescription != null)
                    IconButton(
                      icon: Icon(
                        Icons.info_outline,
                        size: 13,
                        color: mutedColor.withValues(alpha: .8),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => showEarthInfoDialog(
                        context,
                        title: '$title OVERVIEW',
                        description: infoDescription!,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 10,
                    color: mutedColor.withValues(alpha: .7),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              body,
            ],
          ),
        ),
      );
}
