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
      return (building['status']?.toString().toLowerCase() ?? 'active') ==
          'active';
    }).length;

    final territoryRaw =
        state.residency['territory'] ?? state.institutions['territory'];
    final territory = territoryRaw is Map
        ? Map<String, dynamic>.from(territoryRaw)
        : <String, dynamic>{};
    final territoryName =
        (state.residency['territory_name'] ?? territory['name'])
                ?.toString()
                .toUpperCase() ??
            'TERRITORY UNAVAILABLE';

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
                  subtitle: 'LAST CLEARING PRICE',
                  infoDescription:
                      'Verified prices from the latest market clearing. Open Market for the full book and order actions.',
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

                // 2. CURRENT BUILDINGS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '◈',
                  iconColor: violetColor,
                  title: 'OPERATIONS',
                  subtitle:
                      '$activeBuildings ACTIVE · ${state.buildings.length} TOTAL',
                  infoDescription:
                      'Current building inventory and lifecycle state. Open Buildings for construction, maintenance, and production controls.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Active buildings', '$activeBuildings',
                          cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Other lifecycle states',
                          '${state.buildings.length - activeBuildings}',
                          mutedColor),
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
                  subtitle: 'CURRENT RESIDENCY',
                  infoDescription:
                      'Current physical capacity-container facts available to this House. Open the overview to inspect capacity and residency context.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                          'Energy coverage',
                          _formatPercent(territory['power_grid_stability'] ??
                              territory['energy_coverage']),
                          cyanAccentColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Available capacity',
                          _formatPercent(territory['slot_capacity_available'] ??
                              territory['available_capacity']),
                          mutedColor),
                      const SizedBox(height: 5),
                      _rowMetric(
                          'Commons dividend',
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
                  subtitle: 'CURRENT BALANCE',
                  infoDescription:
                      'Spendable balance currently reported for this House. Open Finance for statements and obligations.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                          'Liquid Credits',
                          formatCreditsAmount(state.finance['balance'] ??
                              state.personalFinance['balance'] ??
                              state.human['credits']),
                          violetColor),
                      const SizedBox(height: 5),
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
