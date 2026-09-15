import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class WorldConditionsPanel extends StatelessWidget {
  final EarthState state;

  const WorldConditionsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final raw = state.json['worldConditions'];
    final conditions = raw is List
        ? raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : <Map<String, dynamic>>[];

    final territoryResidency = state.residency;
    final primaryTerritory = state.membership?['territory_id']?.toString() ??
        territoryResidency['primary_territory_id']?.toString() ??
        state.house['primary_territory_id']?.toString();

    final cockpit = EarthPageCockpit(
      status: 'PLANETARY TELEMETRY',
      statusColor: context.primaryColor,
      infoTitle: 'PLANETARY CONDITIONS & BIOSPHERE TELEMETRY',
      infoDescription:
          '• Global Macro Conditions: Transparent planetary modifiers that influence production yields, transport logistics, power grid demands, and ecological stability across all territories.\n\n• Biosphere Equilibrium: Real-time environmental feedback metrics governed by collective planetary resource extraction and energy generation.\n\n• Territorial Subsidiarity: Local territories may implement mitigation programs or commons investments to buffer global environmental and grid fluctuations.',
      title: 'WORLD CONDITIONS',
      subtitle:
          'Planetary ecological balance, macro-economic modifiers, and biosphere indicators',
      metrics: [
        CockpitMetric(
          label: 'Biosphere Index',
          value: 'Not published',
          icon: Icons.eco_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Grid Capacity',
          value: 'Not published',
          icon: Icons.bolt_outlined,
          color: context.goldColor,
        ),
        CockpitMetric(
          label: 'Active Modifiers',
          value: '${conditions.length}',
          icon: Icons.tune_outlined,
          color: conditions.isNotEmpty
              ? context.warningColor
              : context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Rules Version',
          value: conditions.isNotEmpty
              ? (conditions.first['rulesVersion']?.toString() ?? '—')
              : '—',
          icon: Icons.public_outlined,
          color: context.primaryColor,
        ),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),

          // Planetary Environmental Indices
          _buildEnvironmentalIndices(context),
          const SizedBox(height: 24),

          // Active World Conditions / Modifiers
          EarthSection(
            title: 'ACTIVE MACRO CONDITIONS (${conditions.length})',
            showHeader: true,
            showSurface: false,
            child: conditions.isEmpty
                ? _buildBaselineRegimeCard(context)
                : Column(
                    children: conditions.map((condition) {
                      return _buildConditionCard(context, condition);
                    }).toList(),
                  ),
          ),

          SizedBox(height: context.spacingSection),

          // Territorial Resilience & Commons Telemetry
          _buildTerritorialResilience(context, primaryTerritory),
        ],
      ),
    );
  }

  Widget _buildEnvironmentalIndices(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, color: context.primaryColor, size: 18),
              const SizedBox(width: 8),
              Text('PLANETARY SYSTEMS STATUS', style: context.topicTitleStyle),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Only metrics published by the authoritative simulation are shown here. Environmental indices are not currently part of the V4 read model.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _telemetryStatus(context, 'Biosphere',
                      'Awaiting canonical metric', Icons.eco_outlined)),
              const SizedBox(width: 12),
              Expanded(
                  child: _telemetryStatus(context, 'Energy grid',
                      'Awaiting canonical metric', Icons.bolt_outlined)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _telemetryStatus(
      BuildContext context, String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.panelColor.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.mutedColor),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: context.captionStyle),
                Text(value, style: context.widgetFooterStyle),
              ])),
        ],
      ),
    );
  }

  Widget _buildSystemMetric(
    BuildContext context, {
    required String title,
    required String value,
    required String status,
    required double progress,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.panelColor.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: context.captionStyle
                        .copyWith(color: context.mutedColor)),
              ),
              Text(
                status,
                style: context.captionStyle.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: context.topicTitleStyle),
              Text('${(progress * 100).toInt()}%',
                  style:
                      context.captionStyle.copyWith(color: context.mutedColor)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: context.subtleBorderColor,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaselineRegimeCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: context.primaryColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'BASELINE CONSTITUTIONAL REGIME',
                style: TextStyle(
                  color: context.primaryColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              EarthBadge(
                label: 'STANDARD EQUILIBRIUM',
                customColor: context.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No anomalous environmental anomalies or extraordinary global restrictions are currently active. All production, market matching, energy routing, and logistics proceed according to standard baseline multipliers.',
            style: context.bodyStyle,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildRegimePill(context, 'Output Multiplier', '1.00x'),
              const SizedBox(width: 12),
              _buildRegimePill(context, 'Cost Multiplier', '1.00x'),
              const SizedBox(width: 12),
              _buildRegimePill(context, 'Market Trading', 'Unrestricted'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegimePill(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: context.panelColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.subtleBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.captionStyle.copyWith(fontSize: 10)),
            const SizedBox(height: 2),
            Text(value,
                style: context.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionCard(
      BuildContext context, Map<String, dynamic> condition) {
    final effect = condition['effect'] is Map
        ? Map<String, dynamic>.from(condition['effect'] as Map)
        : const <String, dynamic>{};
    final source = condition['source'] is Map
        ? Map<String, dynamic>.from(condition['source'] as Map)
        : const <String, dynamic>{};
    final exposure = condition['exposure']?.toString() ?? 'WORLDWIDE';
    final expires = condition['effectiveToGameDay'] == null
        ? 'Permanent / Indefinite'
        : 'Expires Day ${condition['effectiveToGameDay']}';
    final title = condition['title'] ?? condition['code'] ?? 'World Condition';
    final desc = condition['description'] ?? '';
    final bps = effect['modifierBps'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.warningColor.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, color: context.warningColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toString().toUpperCase(),
                  style: context.topicTitleStyle
                      .copyWith(color: context.warningColor),
                ),
              ),
              EarthBadge(
                label: exposure,
                customColor: exposure == 'WORLDWIDE'
                    ? context.primaryColor
                    : context.secondaryColor,
              ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(desc.toString(), style: context.bodyStyle),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Effect: ${effect['type'] ?? 'MODIFIER'} ($bps bps)',
                    style: context.captionStyle
                        .copyWith(fontWeight: FontWeight.w600)),
                Text('Source: ${source['type'] ?? 'SYSTEM'}',
                    style: context.captionStyle),
                Text(expires,
                    style: context.captionStyle
                        .copyWith(color: context.mutedColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTerritorialResilience(
      BuildContext context, String? primaryTerritory) {
    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  color: context.secondaryColor, size: 18),
              const SizedBox(width: 8),
              Text('TERRITORIAL RESILIENCE & COMMONS',
                  style: context.topicTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Territorial Commons provide localized resilience against planetary demand spikes and raw material volatility. Your primary residence is registered in ${primaryTerritory ?? 'no territory recorded'}.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PRIMARY TERRITORY', style: context.captionStyle),
                    const SizedBox(height: 2),
                    Text(primaryTerritory ?? 'Not recorded',
                        style: context.bodyStyle
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOCAL BUFFER RATING', style: context.captionStyle),
                    const SizedBox(height: 2),
                    Text('Not published',
                        style: context.bodyStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.primaryColor,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
