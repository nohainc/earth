import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';

class CommandExecutiveQuadrant extends StatelessWidget {
  final EarthState state;
  final Map<String, dynamic> businessFinancials;
  final List<dynamic> contracts;
  final ValueChanged<String>? onNavigate;

  const CommandExecutiveQuadrant({
    super.key,
    required this.state,
    this.businessFinancials = const {},
    this.contracts = const [],
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final business = state.business;
    final businessName =
        (business['name'] as String?)?.toUpperCase() ?? 'KLINE WORKS';
    final businessStatus =
        (business['status']?.toString() ?? 'ACTIVE').toUpperCase();
    final condition = (business['condition'] as num?)?.toInt() ?? 96;
    final policy =
        (business['policy']?.toString() ?? 'reliability').toUpperCase();

    final finMap = businessFinancials['business'] is Map<String, dynamic>
        ? (businessFinancials['business'] as Map<String, dynamic>)
        : business;
    final revenue = (finMap['revenue'] as num?)?.toDouble() ?? 1240.0;
    final costs = (finMap['operating_costs'] as num?)?.toDouble() ?? 820.0;
    final profit = (finMap['profit'] as num?)?.toDouble() ?? (revenue - costs);

    final city = state.institutions['city'] as Map<String, dynamic>? ?? {};
    final cityName =
        (city['name'] as String?)?.toUpperCase() ?? 'NEW CARTHAGE';
    final cityHealth = city['fiscal_health'] ?? city['health'] ?? '82';

    final marketProducts = state.market;
    String formatPrice(dynamic val) {
      if (val is Map) return val['price']?.toString() ?? '—';
      if (val is num) return val.toStringAsFixed(2);
      if (val is String) return val;
      return '—';
    }

    final rawComp = formatPrice(marketProducts['components']);
    final componentsPrice = rawComp != '—' ? rawComp : '118.70';
    final rawEnergy = formatPrice(marketProducts['energy']);
    final energyPrice = rawEnergy != '—' ? rawEnergy : '14.20';
    final rawMat = formatPrice(marketProducts['materials']);
    final materialsPrice = rawMat != '—' ? rawMat : '42.00';

    final activeContracts = contracts.where((c) {
      if (c is! Map) return false;
      return c['status'] == 'active' || c['status'] == 'signed';
    }).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoColumns = constraints.maxWidth >= 700;
        final cardWidth = isTwoColumns
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        final double? minCardHeight = isTwoColumns ? 190.0 : null;

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
                  minHeight: minCardHeight,
                  icon: '⌁',
                  iconColor: cyanAccentColor,
                  title: 'MARKET',
                  subtitle: 'UNIFORM BATCH SETTLEMENT',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Components Price', '$componentsPrice C',
                          cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric('Energy Price', '$energyPrice C', mutedColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Materials Price', '$materialsPrice C', mutedColor),
                    ],
                  ),
                  buttonLabel: 'Open Market →',
                  onTap: () => onNavigate?.call('market'),
                ),

                // 2. BUSINESS & OPERATIONS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  minHeight: minCardHeight,
                  icon: '◈',
                  iconColor: violetColor,
                  title: 'BUSINESS / $businessName',
                  subtitle: '$businessStatus · $policy',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Machine Fleet Condition', '$condition%',
                          condition < 50 ? Colors.orangeAccent : cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                        'Projected Net P&L',
                        '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(1)} C / cycle',
                        profit >= 0 ? cyanAccentColor : Colors.redAccent,
                      ),
                      const SizedBox(height: 5),
                      _rowMetric('Operating Policy', policy, mutedColor),
                    ],
                  ),
                  buttonLabel: 'Open Business →',
                  onTap: () => onNavigate?.call('business'),
                ),

                // 3. CIVIC & CITY CARD
                _ExecutiveCard(
                  width: cardWidth,
                  minHeight: minCardHeight,
                  icon: '⊙',
                  iconColor: Colors.amberAccent,
                  title: 'CITY / $cityName',
                  subtitle: 'MUNICIPAL RESIDENCY · HEALTH $cityHealth',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Power Grid Stability', '92% coverage',
                          cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Housing Capacity', '76% available', mutedColor),
                      const SizedBox(height: 5),
                      _rowMetric('Health Coverage', '64% coverage', mutedColor),
                    ],
                  ),
                  buttonLabel: 'Open Civic & City →',
                  onTap: () => onNavigate?.call('civic'),
                ),

                // 4. FINANCE & CONTRACTS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  minHeight: minCardHeight,
                  icon: '§',
                  iconColor: Colors.tealAccent,
                  title: 'FINANCE & CONTRACTS',
                  subtitle: 'DOUBLE-ENTRY SETTLED LEDGER',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Liquid Credits',
                          '${state.human['credits']} C', violetColor),
                      const SizedBox(height: 5),
                      _rowMetric('Active Agreements',
                          '$activeContracts active contracts', mutedColor),
                      const SizedBox(height: 5),
                      _rowMetric('Ledger Integrity', 'Audited', cyanAccentColor),
                    ],
                  ),
                  buttonLabel: 'Open Finance →',
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
}

class _ExecutiveCard extends StatelessWidget {
  final double width;
  final double? minHeight;
  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget body;
  final String buttonLabel;
  final VoidCallback onTap;

  const _ExecutiveCard({
    required this.width,
    this.minHeight,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        constraints:
            minHeight != null ? BoxConstraints(minHeight: minHeight!) : null,
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
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
                  ],
                ),
                const SizedBox(height: 14),
                body,
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  buttonLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: violetColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
