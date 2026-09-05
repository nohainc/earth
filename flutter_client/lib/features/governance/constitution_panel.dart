import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';


class ConstitutionPanel extends StatelessWidget {
  final EarthState state;

  const ConstitutionPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final constitutionalRules = state.json['constitutionalRules'] is List
        ? (state.json['constitutionalRules'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList()
        : const <Map<String, dynamic>>[];
    final constitutionalChanges = state.history['events'] is List
        ? (state.history['events'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .where((event) {
              final type = event['event_type']?.toString().toLowerCase() ?? '';
              return type.contains('rule') ||
                  type.contains('charter') ||
                  type.contains('tax') ||
                  type.contains('constitution');
            })
            .take(12)
            .toList()
        : const <Map<String, dynamic>>[];
    final cockpit = EarthPageCockpit(
      status: 'SUPREME LAW',
      statusColor: context.primaryColor,
      infoTitle: 'PLANETARY CONSTITUTION & LEGAL ORDER',
      infoDescription:
          '• Supreme Law: The highest legal baseline across Earth. All municipal charters and corporate policies must conform to constitutional invariants.\n\n• 3-Tier Governance Hierarchy:\n  1. Earth Baseline (Supreme global statutes & unalienable citizen rights)\n  2. Corporation Policy (Intermediate organizational rules & dividends)\n  3. City Charter (Final permitted local overrides, municipal taxation, & zoning)\n\n• Precedence: A later permitted local override modifies the tier before it, provided it does not violate a global constitutional constraint.',
      title: 'PLANETARY CONSTITUTION',
      subtitle: 'Supreme legal architecture and governance override hierarchy across Earth',
      metrics: [
        CockpitMetric(
          label: 'Statutes',
          value: constitutionalRules.isNotEmpty ? '${constitutionalRules.length}' : '0',
          icon: Icons.gavel_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Hierarchy',
          value: '3',
          icon: Icons.account_tree_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Amendments',
          value: '${constitutionalChanges.length}',
          icon: Icons.history_outlined,
          color: context.warningColor,
        ),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),
          _buildTierFlow(context),

          SizedBox(height: context.spacingSection),

          // Constitution Code
          EarthSection(
            title: 'CONSTITUTION CODE',
            showHeader: false,
            showSurface: false,
            child: constitutionalRules.isEmpty
                ? const EarthEmptyState(
                    message: 'Constitutional rules are unavailable until the rule registry is applied.',
                    icon: Icons.gavel_outlined,
                  )
                : _buildCodeFromRules(context, constitutionalRules),
          ),

          SizedBox(height: context.spacingSection),

          EarthSection(
            title: 'CONSTITUTIONAL HISTORY',
            showSurface: false,
            child: constitutionalChanges.isEmpty
                ? const EarthEmptyState(
                    message: 'No constitutional or charter changes have been recorded yet.',
                    icon: Icons.history_outlined,
                  )
                : EarthDataList(
                    children: constitutionalChanges.indexed.map((indexed) {
                      final event = indexed.$2;
                      return EarthDataRow(
                        title: event['title']?.toString() ?? 'Rule change',
                        subtitle: 'Game day ${event['game_day'] ?? '—'} · ${event['event_type'] ?? 'governance'}',
                        leading: Icon(
                          Icons.history_outlined,
                          size: context.iconSize,
                          color: context.secondaryColor,
                        ),
                        showDivider: indexed.$1 != constitutionalChanges.length - 1,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyCard(
    BuildContext context, {
    required String tier,
    required String title,
    required String scope,
    required Color color,
    required IconData icon,
    required List<String> rules,
    required bool overridable,
    String? parentConstraint,
  }) {
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(context.radiusControl),
                ),
                child: Icon(icon, size: context.iconSize, color: color),
              ),
              SizedBox(width: context.spacingTitleOffset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier, style: context.captionStyle.copyWith(color: color, fontWeight: FontWeight.w700)),
                    Text(title, style: context.widgetValueStyle),
                    Text(scope, style: context.widgetFooterStyle),
                  ],
                ),
              ),
              EarthBadge(
                label: overridable ? 'OVERRIDES ALLOWED' : 'BASELINE',
                customColor: overridable ? context.secondaryColor : context.primaryColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingInline),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  Expanded(child: Text(r, style: context.bodyStyle)),
                ],
              ),
            ),
          ),
          if (parentConstraint != null) ...[
            const SizedBox(height: 4),
            Text(
              '⚠️ $parentConstraint',
              style: context.captionStyle.copyWith(color: context.warningColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTierFlow(BuildContext context) {
    Widget tier(IconData icon, String label, String detail, Color color) => Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: context.iconSize + 4),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, style: context.widgetValueStyle),
              const SizedBox(height: 2),
              Text(detail, textAlign: TextAlign.center, style: context.captionStyle),
            ],
          ),
        );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        children: [
          Text('A later permitted override replaces the value before it.', style: context.widgetFooterStyle),
          const SizedBox(height: 14),
          Row(
            children: [
              tier(Icons.public_outlined, 'EARTH', 'Complete baseline', context.primaryColor),
              Icon(Icons.arrow_forward_rounded, color: context.mutedColor),
              tier(Icons.apartment_outlined, 'CORPORATION', 'Permitted override', context.secondaryColor),
              Icon(Icons.arrow_forward_rounded, color: context.mutedColor),
              tier(Icons.location_city_outlined, 'CITY', 'Final permitted override', context.warningColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionArrow(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: context.subtleBorderColor)),
          const SizedBox(width: 8),
          Icon(Icons.arrow_downward_rounded, size: 16, color: context.mutedColor),
          const SizedBox(width: 8),
          Text(label, style: context.captionStyle),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: context.subtleBorderColor)),
        ],
      ),
    );
  }

  Widget _buildStatuteRow(
    BuildContext context, {
    required String code,
    required String title,
    required String category,
    required String status,
    required bool isImmutable,
    required String summary,
    required bool showDivider,
  }) {
    final values = switch (code) {
      '1.1' => ('Earth baseline', 'Earth, Corporation, or City source'),
      '1.2' => ('Rule-specific authority', 'Only the levels named by that rule'),
      '2.1' => ('Earth income levy', '0–50%'),
      '2.2' => ('Earth sales levy', '0–25%'),
      '2.3' => ('Earth business levy', '0–50%'),
      '2.4' => ('Earth property baseline', '0–30%'),
      '3.1' => ('Active, politically eligible member or resident', null),
      '3.2' => ('25% quorum · 50% approval', 'Active governance-rule version'),
      '3.3' => ('1 game-day implementation delay', null),
      '4.1' => ('Open admission', 'Open or approval'),
      _ => (category, status),
    };
    return EarthDataRow(
      title: title,
      subtitle: summary,
      secondarySubtitle: values.$2 == null
          ? 'Default: ${values.$1}'
          : 'Default: ${values.$1} · Permitted values: ${values.$2}',
      leading: SizedBox(
        width: 30,
        child: Text(
          code,
          style: context.topicTitleStyle.copyWith(color: context.primaryColor),
        ),
      ),
      showDivider: showDivider,
    );
  }

  Widget _buildCodePart(
    BuildContext context,
    String title,
    List<Widget> rules,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacingTopic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.topicTitleStyle),
          const SizedBox(height: 8),
          EarthDataList(children: rules),
        ],
      ),
    );
  }

  Widget _buildCodeFromRules(BuildContext context, List<Map<String, dynamic>> rules) {
    const partTitles = {
      1: 'PART 1 · REVENUE',
      2: 'PART 2 · GOVERNANCE',
      3: 'PART 3 · MEMBERSHIP',
      4: 'PART 4 · SUCCESSION',
    };
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final rule in rules) {
      final part = int.tryParse(rule['part_number']?.toString() ?? '') ?? 0;
      grouped.putIfAbsent(part, () => []).add(rule);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final rows = entry.value;
        return _buildCodePart(
          context,
          partTitles[entry.key] ?? 'PART ${entry.key}',
          rows.asMap().entries.map((indexed) {
            final rule = indexed.value;
            final permitted = rule['permitted_values']?.toString();
            final authority = rule['authority']?.toString();
            final defaultValue = rule['default_value']?.toString() ?? '—';
            final ruleTitleSize = context.widgetValueStyle.fontSize;
            return EarthDataRow(
              title: rule['title']?.toString() ?? 'Rule',
              subtitle: rule['description']?.toString() ?? '',
              secondarySubtitleSpan: TextSpan(
                children: [
                  const TextSpan(text: 'Default: '),
                  TextSpan(text: defaultValue, style: const TextStyle(color: Colors.white)),
                  if (permitted != null && permitted.isNotEmpty) ...[
                    const TextSpan(text: ' · Permitted values: '),
                    TextSpan(text: permitted, style: const TextStyle(color: Colors.white)),
                  ],
                ],
              ),
              tertiarySubtitleSpan: authority == null || authority.toLowerCase() == 'earth'
                  ? null
                  : TextSpan(
                      children: [
                        const TextSpan(text: 'Authority: '),
                        TextSpan(text: authority, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
              subtitleFontSize: ruleTitleSize,
              secondarySubtitleFontSize: ruleTitleSize,
              allowSubtitleWrap: true,
              leading: SizedBox(
                width: 30,
                child: Text(
                  rule['rule_number']?.toString() ?? '—',
                  style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                ),
              ),
              showDivider: indexed.key != rows.length - 1,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

}
