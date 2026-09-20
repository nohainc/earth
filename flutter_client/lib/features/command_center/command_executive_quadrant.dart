import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/building_models.dart';
import '../../core/models/command_overview.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

class CommandExecutiveQuadrant extends StatelessWidget {
  final CommandOverview? overview;
  final List<BuildingAsset> houseAssets;
  final ValueChanged<String>? onNavigate;

  const CommandExecutiveQuadrant({
    super.key,
    this.overview,
    this.houseAssets = const [],
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOverview = overview;
    if (effectiveOverview == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Executive overview is temporarily unavailable.'),
      );
    }
    final activeBuildings = houseAssets
        .where((asset) => asset.status.toUpperCase() == 'ACTIVE')
        .length;
    final totalBuildings = houseAssets.length;
    final otherBuildings = houseAssets
        .where((asset) => asset.status.toUpperCase() != 'ACTIVE')
        .length;

    String formatMarketPrice(String val) {
      if (val.isEmpty || val == '0' || val == '—') return '—';
      final n = num.tryParse(val);
      if (n != null) {
        return formatCreditUnits(val);
      }
      return val;
    }

    final marketRows = [...effectiveOverview.market.products]
      ..sort((a, b) => a.product.compareTo(b.product));
    final resourceColors = <String, Color>{
      'energy': EarthResourceColors.energy,
      'food': EarthResourceColors.food,
      'material': EarthResourceColors.materials,
      'components': EarthResourceColors.components,
      'compute': EarthResourceColors.compute,
    };

    String quantity(String? value) =>
        value == null || value.isEmpty ? 'UNAVAILABLE' : value;

    BigInt? parseQuantity(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      final text = value.trim();
      final negative = text.startsWith('-');
      final unsigned =
          (negative || text.startsWith('+')) ? text.substring(1) : text;
      final parts = unsigned.split('.');
      if (parts.length > 2) return null;
      final whole = BigInt.tryParse(parts.first);
      if (whole == null) return null;
      final fraction = parts.length == 2 ? parts[1] : '';
      if (!RegExp(r'^\d*$').hasMatch(fraction) || fraction.length > 6) {
        return null;
      }
      final scaledFraction =
          BigInt.tryParse(fraction.padRight(6, '0')) ?? BigInt.zero;
      final magnitude = whole * BigInt.from(1000000) + scaledFraction;
      return negative ? -magnitude : magnitude;
    }

    String formatRunway(OverviewMarketProduct product) {
      final balance = parseQuantity(product.closingBalance);
      final net = parseQuantity(product.netFlow);
      if (balance == null || net == null) return 'UNAVAILABLE';
      if (net >= BigInt.zero) return '—';
      final deficit = net.abs();
      final days = (balance + deficit - BigInt.one) ~/ deficit;
      return '$days game day${days == BigInt.one ? '' : 's'}';
    }

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
                  subtitle: 'LAST SETTLEMENT · OPEN INTEREST',
                  infoDescription:
                      'Verified prices from the latest market clearing. Open Market for the full book and order actions.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: marketRows.isEmpty
                        ? [
                            _rowMetric('Resource flow', 'UNAVAILABLE',
                                context.mutedColor),
                          ]
                        : [
                            for (var i = 0; i < marketRows.length; i++) ...[
                              _rowMetric(
                                EarthResourceMeta.forCommodity(
                                        marketRows[i].product)
                                    .label,
                                formatMarketPrice(marketRows[i].priceUnits),
                                resourceColors[marketRows[i].product] ??
                                    context.primaryColor,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'SETTLED DAY ${marketRows[i].latestSettledGameDay ?? '—'} · Produced ${quantity(marketRows[i].production)} · Consumed ${quantity(marketRows[i].consumption)} · Net ${quantity(marketRows[i].netFlow)} / game day',
                                style: const TextStyle(
                                    fontSize: 9, color: mutedColor),
                              ),
                              Text(
                                'Runway ${formatRunway(marketRows[i])} · OPEN BUY ${quantity(marketRows[i].openBuyUnits)} · OPEN SELL ${quantity(marketRows[i].openSellUnits)}',
                                style: const TextStyle(
                                    fontSize: 9, color: mutedColor),
                              ),
                              if (marketRows[i].shortage != null &&
                                  marketRows[i].shortage != '0.000000')
                                Text(
                                  'SHORTFALL ${quantity(marketRows[i].shortage)}',
                                  style: const TextStyle(
                                      fontSize: 9, color: Colors.orangeAccent),
                                ),
                              if (i < marketRows.length - 1)
                                const SizedBox(height: 7),
                            ],
                          ],
                  ),
                  onTap: () => onNavigate?.call('market'),
                ),

                // 2. CURRENT BUILDINGS CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '◈',
                  iconColor: context.secondaryColor,
                  title: 'BUILDINGS',
                  subtitle: '$activeBuildings ACTIVE · $totalBuildings TOTAL',
                  infoDescription:
                      'Current building inventory and lifecycle state. Open Buildings for construction, maintenance, and production controls.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric('Active buildings', '$activeBuildings',
                          context.primaryColor),
                      const SizedBox(height: 5),
                      _rowMetric('Other lifecycle states', '$otherBuildings',
                          context.mutedColor),
                    ],
                  ),
                  onTap: () => onNavigate?.call('buildings'),
                ),

                // 3. FINANCE CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '§',
                  iconColor: context.successColor,
                  title: 'FINANCE',
                  subtitle: 'CURRENT BALANCE',
                  infoDescription:
                      'Spendable balance currently reported for this House. Open Finance for statements and obligations.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                          'Liquid Credits',
                          formatCreditUnits(
                              effectiveOverview.finance.availableWalletUnits),
                          context.goldColor),
                      const SizedBox(height: 5),
                    ],
                  ),
                  onTap: () => onNavigate?.call('finance'),
                ),

                // 4. PHYSICAL CAPACITY CARD
                _ExecutiveCard(
                  width: cardWidth,
                  icon: '▦',
                  iconColor: context.primaryColor,
                  title: 'CAPACITY',
                  subtitle: effectiveOverview.capacity?.delinquencyStatus ??
                      'UNAVAILABLE',
                  infoDescription:
                      'Authoritative House capacity allocation and current standing. Open Buildings for asset-level capacity and rent details.',
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rowMetric(
                        'Allocated capacity',
                        effectiveOverview.capacity == null
                            ? 'UNAVAILABLE'
                            : '${effectiveOverview.capacity!.totalUnits} units',
                        context.primaryColor,
                      ),
                      const SizedBox(height: 5),
                      _rowMetric(
                        'Building capacity',
                        effectiveOverview.capacity == null
                            ? 'UNAVAILABLE'
                            : '${effectiveOverview.capacity!.buildingUnits} units',
                        context.mutedColor,
                      ),
                    ],
                  ),
                  onTap: () => onNavigate?.call('buildings'),
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
