import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

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
        (business['name']?.toString() ?? 'KLINE WORKS').toUpperCase();
    final businessStatus =
        (business['status']?.toString() ?? 'ACTIVE').toUpperCase();
    final condition = asIntOr(business['condition'], 96);
    final policy =
        (business['policy']?.toString() ?? 'reliability').toUpperCase();

    final finMap = businessFinancials['business'] is Map
        ? Map<String, dynamic>.from(businessFinancials['business'] as Map)
        : business;
    final revenue = asDoubleOr(finMap['revenue'], 1240.0);
    final costs = asDoubleOr(finMap['operating_costs'] ?? finMap['costs'], 820.0);
    final profit = asDoubleOr(finMap['profit'], revenue - costs);

    final cityRaw = state.institutions['city'];
    final city = cityRaw is Map ? Map<String, dynamic>.from(cityRaw) : <String, dynamic>{};
    final cityName =
        (city['name']?.toString() ?? 'NEW CARTHAGE').toUpperCase();
    final cityHealth = formatWholeNumber(city['fiscal_health'] ?? city['health'], fallback: '82');

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
    final componentsPrice = rawComp != '—' ? rawComp : '118.70';
    final rawEnergy = formatPrice(marketProducts['energy']);
    final energyPrice = rawEnergy != '—' ? rawEnergy : '14.20';
    final rawMat = formatPrice(marketProducts['materials']);
    final materialsPrice = rawMat != '—' ? rawMat : '42.00';

    final activeContracts = contracts.where((c) {
      if (c is! Map) return false;
      final s = c['status']?.toString();
      return s == 'active' || s == 'signed';
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
                  onInfoTap: () => showEarthInfoDialog(
                    context,
                    title: 'CENTRAL MARKET OVERVIEW',
                    subtitle: 'Batch auction clearing & spot commodity pricing',
                    items: [
                      {
                        'label': 'Components Price ($componentsPrice C)',
                        'description':
                            'Uniform clearing price per unit of manufactured Components in the latest market settlement batch.',
                      },
                      {
                        'label': 'Energy Price ($energyPrice C)',
                        'description':
                            'Spot cost per power unit required to run machinery and maintain city operations.',
                      },
                      {
                        'label': 'Materials Price ($materialsPrice C)',
                        'description':
                            'Raw physical feedstock price utilized by businesses during manufacturing.',
                      },
                    ],
                  ),
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
                  title: 'BUSINESS',
                  subtitle: '$businessName · $businessStatus',
                  onInfoTap: () => showEarthInfoDialog(
                    context,
                    title: 'BUSINESS OPERATIONS',
                    subtitle: 'Fleet health, production strategy, and revenue',
                    items: [
                      {
                        'label': 'Machine Fleet Condition ($condition%)',
                        'description':
                            'Average operational condition of all active production machines. When condition drops below 50%, maintenance is urgently required.',
                      },
                      {
                        'label': 'Projected Net P&L (${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(1)} C)',
                        'description':
                            'Estimated net profit generated per cycle after deducting operating costs, input commodities, and taxes.',
                      },
                      {
                        'label': 'Operating Policy ($policy)',
                        'description':
                            'Current operational mode: Reliability (protected condition), Margin (higher yield/risk), or Capacity (maximum output/rapid wear).',
                      },
                    ],
                  ),
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
                  title: cityName,
                  subtitle: 'MUNICIPAL RESIDENCY · HEALTH $cityHealth',
                  onInfoTap: () => showEarthInfoDialog(
                    context,
                    title: 'MUNICIPAL CITY STATUS',
                    subtitle: 'Infrastructure coverage and civic health',
                    items: [
                      {
                        'label': 'Power Grid Stability (92%)',
                        'description':
                            'City-wide electrical power distribution. Grid failures disrupt machine throughput.',
                      },
                      {
                        'label': 'Housing Capacity (76%)',
                        'description':
                            'Available residential capacity for human citizens within the city jurisdiction.',
                      },
                      {
                        'label': 'Health Coverage (64%)',
                        'description':
                            'Municipal healthcare and medical coverage mitigating human biological aging penalties.',
                      },
                    ],
                  ),
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
                  buttonLabel: 'Open Civic →',
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
                  onInfoTap: () => showEarthInfoDialog(
                    context,
                    title: 'FINANCE & COMMERCIAL AGREEMENTS',
                    subtitle: 'Treasury liquidity and binding supply contracts',
                    items: [
                      {
                        'label':
                            'Liquid Credits (${formatCreditsAmount(state.human['credits'])})',
                        'description':
                            'Cash reserves instantly available for orders, equipment acquisition, and dividend distributions.',
                      },
                      {
                        'label': 'Active Agreements ($activeContracts)',
                        'description':
                            'Enforceable commercial supply contracts ensuring fixed-price commodity deliveries.',
                      },
                      {
                        'label': 'Ledger Integrity (Audited)',
                        'description':
                            'Every credit is double-entry verified against the authoritative database ledger.',
                      },
                    ],
                  ),
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Liquid Credits',
                          formatCreditsAmount(state.human['credits']), violetColor),
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
  final VoidCallback? onInfoTap;

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
    this.onInfoTap,
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
                    if (onInfoTap != null)
                      IconButton(
                        icon: Icon(
                          Icons.info_outline,
                          size: 13,
                          color: mutedColor.withValues(alpha: .7),
                        ),
                        tooltip: 'Details',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onInfoTap,
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
