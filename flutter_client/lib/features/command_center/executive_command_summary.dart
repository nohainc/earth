import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/models/decision_queue_item.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../core/audio/earth_audio_engine.dart';

class ExecutiveCommandSummary extends StatefulWidget {
  final EarthState state;
  final ValueChanged<String>? onNavigate;
  final ValueChanged<DecisionQueueItem>? onExecuteDecision;
  final VoidCallback? onOpenFullBriefing;

  const ExecutiveCommandSummary({
    super.key,
    required this.state,
    this.onNavigate,
    this.onExecuteDecision,
    this.onOpenFullBriefing,
  });

  @override
  State<ExecutiveCommandSummary> createState() => _ExecutiveCommandSummaryState();
}

class _ExecutiveCommandSummaryState extends State<ExecutiveCommandSummary> {
  String _selectedActionFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final briefing = DailyBriefingReport.synthesizeFromState(widget.state);
    final decisionItems = DecisionQueueItem.synthesizeFromState(widget.state);
    final opportunities = widget.state.opportunities;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // QUESTION 1: WHAT IS MY CURRENT SITUATION?
        EarthSection(
          title: 'WHAT IS MY CURRENT SITUATION?',
          showSurface: false,
          infoBulletPoints: const [
            'Situation Matrix & Core Metrics: Real-time overview of spendable capital reserves, enterprise solvency, workforce capacity, machine fleet condition, and municipal pressure.',
            'Actionable Drill-Down: Tap any metric tile to jump directly to its detailed management interface.',
          ],
          child: _buildSituationMatrix(context),
        ),
        SizedBox(height: context.spacingTopic),

        // QUESTION 2: WHAT CHANGED SINCE MY LAST VISIT?
        EarthSection(
          title: 'WHAT CHANGED SINCE MY LAST VISIT?',
          showSurface: false,
          infoBulletPoints: const [
            'Nightly Cycle & Overnight Intelligence: Summary of net wealth shifts, overnight revenue & operating expenses, and passed civic referendums since your previous login session.',
          ],
          child: _buildWhatChangedCard(context, briefing),
        ),
        SizedBox(height: context.spacingTopic),

        // QUESTION 3: WHAT DECISION SHOULD I MAKE NEXT?
        EarthSection(
          title: 'WHAT DECISION SHOULD I MAKE NEXT?',
          showSurface: false,
          infoBulletPoints: const [
            'Prioritized Decision Queue & Opportunities: Actionable operational alerts, critical risk warnings, pending contract obligations, and live market arbitrage opportunities.',
          ],
          child: _buildWhatDecisionNextCard(context, decisionItems, opportunities),
        ),
      ],
    );
  }

  // ==========================================================================
  // 1. SITUATION MATRIX
  // ==========================================================================
  Widget _buildSituationMatrix(BuildContext context) {
    final business = <String, dynamic>{};
    final credits = asDouble(widget.state.human['credits']) ??
        asDouble(widget.state.json['player'] is Map
            ? (widget.state.json['player'] as Map)['credits']
            : null);
    final profit = asDouble(business['profit']);
    final margin = asDouble(business['margin'] ?? business['profit_margin']);
    final workforce = widget.state.json['workforce'] is List
        ? (widget.state.json['workforce'] as List)
        : const [];
    final activeStaff = workforce.where((e) => e is Map && e['status'] != 'dismissed').length;
    final capacity = asInt(business['workforceCapacity'] ?? business['staffCapacity']);
    final city = widget.state.institutions['city'];
    final cityMap = city is Map ? Map<String, dynamic>.from(city) : const <String, dynamic>{};
    final cityPressure = asDouble(cityMap['service_pressure'] ?? cityMap['servicePressure']);
    final buildings = widget.state.buildings;

    return EarthMetricGrid(
      metrics: [
        EarthMetricTile(
          label: 'LIQUID CAPITAL',
          value: credits == null ? 'UNAVAILABLE' : '${formatWholeNumber(credits)} C',
          subtitle: 'Spendable now',
          icon: Icons.account_balance_wallet_outlined,
          accentColor: context.primaryColor,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('finance');
          },
        ),
        EarthMetricTile(
          label: 'ENTERPRISE HEALTH',
          value: profit == null
              ? 'UNAVAILABLE'
              : '${profit >= 0 ? '+' : ''}${formatWholeNumber(profit)} CR',
          subtitle: margin == null ? 'Profit unavailable' : '${margin.toStringAsFixed(1)}% margin',
          icon: Icons.storefront_outlined,
          accentColor: profit == null || profit >= 0 ? context.successColor : context.warningColor,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('buildings');
          },
        ),
        EarthMetricTile(
          label: 'WORKFORCE',
          value: activeStaff == 0 && capacity == null ? 'UNAVAILABLE' : '$activeStaff STAFF',
          subtitle: capacity == null ? 'Capacity unavailable' : '$capacity capacity',
          icon: Icons.groups_outlined,
          accentColor: context.primaryColor,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('buildings');
          },
        ),
        EarthMetricTile(
          label: 'BUILDINGS',
          value: buildings.isEmpty ? 'NO BUILDINGS' : '${buildings.length} BUILDINGS',
          subtitle: 'Productive assets',
          icon: Icons.domain_outlined,
          accentColor: context.successColor,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('buildings');
          },
        ),
        EarthMetricTile(
          label: 'CITY EFFECT',
          value: cityMap['name']?.toString().toUpperCase() ?? 'UNAVAILABLE',
          subtitle: cityPressure == null
              ? 'Pressure unavailable'
              : 'Pressure ${cityPressure.toStringAsFixed(0)}%',
          icon: Icons.location_city_outlined,
          accentColor: cityPressure != null && cityPressure > 70 ? context.warningColor : context.successColor,
          onTap: () {
            EarthAudioEngine.instance.playClick();
            widget.onNavigate?.call('city');
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // 2. WHAT CHANGED SINCE MY LAST VISIT
  // ==========================================================================
  Widget _buildWhatChangedCard(BuildContext context, DailyBriefingReport briefing) {
    final netDelta = briefing.netWealthDelta;
    final isPositiveDelta = netDelta.delta >= 0;
    final sign = isPositiveDelta ? '+' : '';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary Overnight Telemetry Strip
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.radiusControl),
                  border: Border.all(color: context.warningColor.withValues(alpha: .3)),
                ),
                child: Icon(Icons.newspaper_outlined, size: context.iconSize + 4, color: context.warningColor),
              ),
              SizedBox(width: context.spacingInline),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'DAY ${briefing.gameDay} CHRONICLE',
                          style: context.widgetTitleStyle.copyWith(
                            color: context.warningColor,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '• Summary since the previous cycle',
                            style: context.widgetFooterStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Net Wealth Shift: $sign${formatWholeNumber(netDelta.delta)} CR ($sign${netDelta.deltaPct.toStringAsFixed(1)}%) · Cashflow Net: +${formatWholeNumber(briefing.cashflow.netProfit)} CR/day',
                      style: context.widgetValueStyle.copyWith(
                        color: isPositiveDelta ? context.successColor : context.errorColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.spacingTitleOffset),

          // Operational and civic headline changes
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (briefing.businessSummary.activeBuildings > 0)
                _headlineChip(
                  context,
                  Icons.domain_outlined,
                  '${briefing.businessSummary.activeBuildings} building${briefing.businessSummary.activeBuildings == 1 ? '' : 's'} operating',
                  context.successColor,
                ),
              if (briefing.civicSummary.recentCivicEvents.isNotEmpty)
                _headlineChip(
                  context,
                  Icons.gavel,
                  briefing.civicSummary.recentCivicEvents.first,
                  context.warningColor,
                ),
            ],
          ),

          SizedBox(height: context.spacingTitleOffset),
          Divider(color: context.subtleBorderColor, height: 1),
          SizedBox(height: context.spacingControl),
          Row(
            children: [
              Expanded(
                child: _microStat(
                  context,
                  'OVERNIGHT REVENUE',
                  '+${formatWholeNumber(briefing.cashflow.totalIncome)} CR',
                  'Dividends & Market Sales',
                  context.successColor,
                ),
              ),
              SizedBox(width: context.spacingControl),
              Expanded(
                child: _microStat(
                  context,
                  'OVERNIGHT EXPENSES',
                  '-${formatWholeNumber(briefing.cashflow.totalExpenses)} CR',
                  'Maintenance & Taxes',
                  context.warningColor,
                ),
              ),
              SizedBox(width: context.spacingControl),
              Expanded(
                child: _microStat(
                  context,
                  'ACTIVE CITIZEN RESIDENCY',
                  briefing.civicSummary.cityResidency,
                  'Tax Rate: ${briefing.civicSummary.cityTaxRatePct.toStringAsFixed(1)}%',
                  context.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _microStat(BuildContext context, String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(context.radiusControl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.widgetTitleStyle.copyWith(color: color),
          ),
          const SizedBox(height: 1),
          Text(sub, style: context.widgetFooterStyle, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _headlineChip(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: context.widgetFooterStyle.copyWith(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ==========================================================================
  // 3. WHAT DECISION SHOULD I MAKE NEXT?
  // ==========================================================================
  Widget _buildWhatDecisionNextCard(
    BuildContext context,
    List<DecisionQueueItem> decisionItems,
    List<dynamic> opportunities,
  ) {
    final filteredDecisions = _filterDecisionItems(decisionItems);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Tabs Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(context, 'ALL', 'ALL (${decisionItems.length + opportunities.length})'),
              const SizedBox(width: 6),
              _filterChip(context, 'CRITICAL', 'CRITICAL', color: context.warningColor),
              const SizedBox(width: 6),
              _filterChip(context, 'CORPORATION', 'ENTERPRISE', color: context.primaryColor),
              const SizedBox(width: 6),
              _filterChip(context, 'CIVIC', 'CIVIC & HOUSE', color: context.secondaryColor),
            ],
          ),
        ),
        SizedBox(height: context.spacingTitleOffset),

        // Render Decision Items
        if (filteredDecisions.isEmpty)
          const EarthEmptyState(
            message: 'No pending critical obligations. Your enterprise and civic standing are fully optimized.',
            icon: Icons.check_circle_outline,
          )
        else
          EarthDataList(
            children: List.generate(filteredDecisions.length, (index) {
              final item = filteredDecisions[index];
              final isLast = index == filteredDecisions.length - 1;
              return _buildUnifiedDecisionItem(context, item, isLast: isLast);
            }),
          ),

        // Merged Live Opportunity Signals
        if (opportunities.isNotEmpty) ...[
          SizedBox(height: context.spacingTitleOffset),
          Divider(color: context.subtleBorderColor, height: 1),
          SizedBox(height: context.spacingControl),
          Row(
            children: [
              Icon(Icons.trending_up, size: context.iconSize, color: context.primaryColor),
              SizedBox(width: context.spacingInline),
              Text(
                'LIVE STRATEGIC OPPORTUNITIES',
                style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),
          ...opportunities.map((opp) {
            final mapOpp = Map<String, dynamic>.from(opp as Map);
            return _buildOpportunityStrip(context, mapOpp);
          }),
        ],
      ],
    );
  }

  List<DecisionQueueItem> _filterDecisionItems(List<DecisionQueueItem> items) {
    switch (_selectedActionFilter) {
      case 'CRITICAL':
        return items
            .where((i) =>
                i.riskLevel.toLowerCase() == 'critical' || i.riskLevel.toLowerCase() == 'high')
            .toList();
      case 'CORPORATION':
        return items
            .where((i) =>
                i.category.toLowerCase() == 'business' ||
                i.category.toLowerCase() == 'buildings' ||
                i.category.toLowerCase() == 'market')
            .toList();
      case 'CIVIC':
        return items
            .where((i) =>
                i.category.toLowerCase() == 'governance' ||
                i.category.toLowerCase() == 'civic' ||
                i.category.toLowerCase() == 'house' ||
                i.category.toLowerCase() == 'dynasty' ||
                i.category.toLowerCase() == 'technology' ||
                i.category.toLowerCase() == 'finance')
            .toList();
      case 'ALL':
      default:
        return items;
    }
  }

  Widget _filterChip(BuildContext context, String filterKey, String label, {Color? color}) {
    final isSelected = _selectedActionFilter == filterKey;
    final activeColor = color ?? context.primaryColor;

    return InkWell(
      onTap: () {
        EarthAudioEngine.instance.playClick();
        setState(() => _selectedActionFilter = filterKey);
      },
      borderRadius: BorderRadius.circular(context.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusControl),
          border: Border.all(
            color: isSelected ? activeColor : context.subtleBorderColor,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: context.captionStyle.copyWith(
            color: isSelected ? activeColor : context.mutedColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedDecisionItem(
    BuildContext context,
    DecisionQueueItem item, {
    bool isLast = false,
  }) {
    final isCritical = item.riskLevel.toLowerCase() == 'critical' ||
        item.riskLevel.toLowerCase() == 'high';
    final categoryColor = _getDecisionCategoryColor(context, item);
    final categoryIcon = _getDecisionCategoryIcon(item);

    return EarthDataRow(
      title: item.title,
      subtitle: '${item.whyItMatters}\nDeadline: ${item.deadline} · Impact: ${item.expectedImpact}',
      leading: Icon(categoryIcon, size: context.iconSize, color: categoryColor),
      badges: [
        EarthBadge(
          label: item.riskLevel.toUpperCase(),
          variant: isCritical ? EarthBadgeVariant.warning : EarthBadgeVariant.neutral,
        ),
      ],
      trailing: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isCritical ? context.errorColor : context.primaryColor,
          foregroundColor: isCritical ? Colors.white : context.canvasColor,
          elevation: 0,
          padding: EdgeInsets.symmetric(horizontal: context.spacingControl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusControl),
          ),
        ),
        onPressed: () {
          EarthAudioEngine.instance.playClick();
          if (widget.onExecuteDecision != null) {
            widget.onExecuteDecision!(item);
          } else if (widget.onNavigate != null) {
            widget.onNavigate!(item.targetSection);
          }
        },
        child: Text(
          item.primaryActionLabel,
          style: context.controlStyle.copyWith(
            color: isCritical ? Colors.white : context.canvasColor,
          ),
        ),
      ),
      showDivider: !isLast,
    );
  }

  Color _getDecisionCategoryColor(BuildContext context, DecisionQueueItem item) {
    switch (item.category.toLowerCase()) {
      case 'business':
      case 'buildings':
        return context.warningColor;
      case 'governance':
      case 'civic':
        return context.secondaryColor;
      case 'technology':
      case 'market':
        return context.primaryColor;
      default:
        return context.primaryColor;
    }
  }

  IconData _getDecisionCategoryIcon(DecisionQueueItem item) {
    switch (item.category.toLowerCase()) {
      case 'business':
        return Icons.storefront_outlined;
      case 'buildings':
        return Icons.domain_outlined;
      case 'governance':
      case 'civic':
        return Icons.how_to_vote_outlined;
      case 'house':
      case 'dynasty':
        return Icons.shield_outlined;
      default:
        return Icons.alt_route;
    }
  }

  Widget _buildOpportunityStrip(BuildContext context, Map<String, dynamic> opp) {
    final title = opp['title']?.toString() ?? 'Strategic Opportunity';
    final detail = opp['detail']?.toString() ?? '';
    final signal = opp['signal']?.toString() ?? 'market';

    String targetSection = 'market';
    if (signal.contains('gov') || signal.contains('civic')) {
      targetSection = 'civic';
    }
    if (signal.contains('tech') || signal.contains('research')) {
      targetSection = 'technology';
    }
    if (signal.contains('business')) targetSection = 'business';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.symmetric(horizontal: context.tokens.number('pageTopics.cardPadding', 10), vertical: 6),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: context.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.flash_on, size: context.iconSize, color: context.primaryColor),
          SizedBox(width: context.spacingInline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.widgetTitleStyle.copyWith(color: context.inkColor),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  detail,
                  style: context.widgetFooterStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: context.spacingInline),
          EarthButton(
            label: 'EXPLOIT',
            variant: EarthButtonVariant.primary,
            onPressed: () {
              EarthAudioEngine.instance.playClick();
              widget.onNavigate?.call(targetSection);
            },
          ),
        ],
      ),
    );
  }
}
