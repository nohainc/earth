import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/models/decision_queue_item.dart';
import '../../core/models/player_objective.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../core/audio/earth_audio_engine.dart';

class ExecutiveCommandSummary extends StatefulWidget {
  final EarthState state;
  final Map<String, dynamic> businessFinancials;
  final List<dynamic> contracts;
  final ValueChanged<String>? onNavigate;
  final ValueChanged<DecisionQueueItem>? onExecuteDecision;
  final VoidCallback? onOpenFullBriefing;

  const ExecutiveCommandSummary({
    super.key,
    required this.state,
    this.businessFinancials = const {},
    this.contracts = const [],
    this.onNavigate,
    this.onExecuteDecision,
    this.onOpenFullBriefing,
  });

  @override
  State<ExecutiveCommandSummary> createState() => _ExecutiveCommandSummaryState();
}

class _ExecutiveCommandSummaryState extends State<ExecutiveCommandSummary> {
  bool _briefingExpanded = false;
  String _selectedActionFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final briefing = DailyBriefingReport.synthesizeFromState(widget.state);
    final decisionItems = DecisionQueueItem.synthesizeFromState(widget.state);
    final objectives = PlayerObjective.synthesizeFromState(widget.state);
    final opportunities = widget.state.opportunities;

    final primaryObjective = objectives.isNotEmpty ? objectives.first : null;

    final criticalCount = decisionItems
        .where((i) =>
            i.riskLevel.toLowerCase() == 'critical' ||
            i.riskLevel.toLowerCase() == 'high')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ====================================================================
        // QUESTION 1: WHAT IS MY CURRENT SITUATION?
        // ====================================================================
        _buildSectionHeader(
          number: '1',
          question: 'WHAT IS MY CURRENT SITUATION?',
          subtitle: 'Executive posture, capital reserves, fleet condition & production vitality',
          accentColor: EarthColors.cyanAccent,
          icon: Icons.account_circle_outlined,
        ),
        const SizedBox(height: 10),
        _buildSituationMatrix(primaryObjective),
        const SizedBox(height: 24),

        // ====================================================================
        // QUESTION 2: WHAT CHANGED SINCE MY LAST VISIT?
        // ====================================================================
        _buildSectionHeader(
          number: '2',
          question: 'WHAT CHANGED SINCE MY LAST VISIT?',
          subtitle: 'Nightly cycle intelligence, net worth deltas, market volatility & civic updates',
          accentColor: EarthColors.goldMetallic,
          icon: Icons.history_toggle_off,
          trailingWidget: InkWell(
            onTap: () {
              EarthAudioEngine.instance.playClick();
              setState(() => _briefingExpanded = !_briefingExpanded);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: EarthColors.goldMetallic.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EarthColors.goldMetallic.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _briefingExpanded ? Icons.unfold_less : Icons.unfold_more,
                    size: 13,
                    color: EarthColors.goldMetallic,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _briefingExpanded ? 'COLLAPSE' : 'EXPAND INTEL',
                    style: const TextStyle(
                      color: EarthColors.goldMetallic,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildWhatChangedCard(briefing),
        const SizedBox(height: 24),

        // ====================================================================
        // QUESTION 3: WHAT DECISION SHOULD I MAKE NEXT?
        // ====================================================================
        _buildSectionHeader(
          number: '3',
          question: 'WHAT DECISION SHOULD I MAKE NEXT?',
          subtitle: 'Prioritized decision queue & real-time market arbitrage opportunities',
          accentColor: criticalCount > 0 ? Colors.orangeAccent : const Color(0xFF00E676),
          icon: Icons.alt_route,
          badgeLabel: criticalCount > 0 ? '$criticalCount CRITICAL' : 'OPTIMAL',
          badgeColor: criticalCount > 0 ? Colors.orangeAccent : const Color(0xFF00E676),
        ),
        const SizedBox(height: 10),
        _buildWhatDecisionNextCard(decisionItems, opportunities),
      ],
    );
  }

  // ==========================================================================
  // SECTION HEADERS
  // ==========================================================================
  Widget _buildSectionHeader({
    required String number,
    required String question,
    required String subtitle,
    required Color accentColor,
    required IconData icon,
    String? badgeLabel,
    Color? badgeColor,
    Widget? trailingWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: accentColor),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      question,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badgeLabel != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? accentColor).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: (badgeColor ?? accentColor).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          color: badgeColor ?? accentColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                subtitle,
                style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailingWidget != null) trailingWidget,
      ],
    );
  }

  // ==========================================================================
  // 1. SITUATION MATRIX
  // ==========================================================================
  Widget _buildSituationMatrix(PlayerObjective? primaryObjective) {
    final player = widget.state.json['player'] as Map<String, dynamic>? ?? {};
    final human = widget.state.human;
    final business = widget.state.business;
    final credits = (player['credits'] ?? player['cash'] ?? 0).toDouble();
    final energy = (player['energy'] ?? 100).toDouble();
    final health = (human['vitality'] ?? 100).toDouble();
    final corpName = business['name']?.toString() ?? 'Vance Logistics';
    final isSolvent = business['solvent'] ?? true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EarthColors.cyanAccent.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          final itemWidth = isNarrow ? (constraints.maxWidth - 8) / 2 : (constraints.maxWidth - 24) / 4;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _situationPill(
                    width: itemWidth,
                    label: 'LIQUID CAPITAL',
                    value: '${formatWholeNumber(credits)} CR',
                    subvalue: '+930 CR/day net',
                    icon: Icons.account_balance_wallet_outlined,
                    accent: EarthColors.cyanAccent,
                    onTap: () => widget.onNavigate?.call('finance'),
                  ),
                  _situationPill(
                    width: itemWidth,
                    label: 'ENTERPRISE HEALTH',
                    value: corpName.toUpperCase(),
                    subvalue: isSolvent ? 'SOLVENT · 100% FLEET' : 'INSOLVENT RISK',
                    icon: Icons.storefront_outlined,
                    accent: isSolvent ? const Color(0xFF00E676) : Colors.orangeAccent,
                    onTap: () => widget.onNavigate?.call('business'),
                  ),
                  _situationPill(
                    width: itemWidth,
                    label: 'ENERGY & VITALITY',
                    value: '${energy.toStringAsFixed(0)}% ENERGY',
                    subvalue: '${health.toStringAsFixed(0)}% Vitality · Stable',
                    icon: Icons.bolt_outlined,
                    accent: energy < 20 ? Colors.redAccent : Colors.amberAccent,
                    onTap: () => widget.onNavigate?.call('technology'),
                  ),
                  _situationPill(
                    width: itemWidth,
                    label: 'STRATEGIC AMBITION',
                    value: primaryObjective != null ? primaryObjective.title : 'VALUABLE CORP',
                    subvalue: primaryObjective != null
                        ? '${primaryObjective.progressPercentage.toStringAsFixed(0)}% Progress'
                        : 'Active',
                    icon: Icons.flag_outlined,
                    accent: EarthColors.goldMetallic,
                    onTap: () => widget.onNavigate?.call('command'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _situationPill({
    required double width,
    required String label,
    required String value,
    required String subvalue,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () {
          EarthAudioEngine.instance.playClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: EarthColors.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 12, color: accent),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: EarthColors.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subvalue,
                style: TextStyle(
                  color: accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 2. WHAT CHANGED SINCE MY LAST VISIT
  // ==========================================================================
  Widget _buildWhatChangedCard(DailyBriefingReport briefing) {
    final netDelta = briefing.netWealthDelta;
    final isPositiveDelta = netDelta.delta >= 0;
    final sign = isPositiveDelta ? '+' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EarthColors.goldMetallic.withValues(alpha: 0.3)),
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
                  color: EarthColors.goldMetallic.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EarthColors.goldMetallic.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.newspaper_outlined, size: 20, color: EarthColors.goldMetallic),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'DAY ${briefing.gameDay} CHRONICLE',
                          style: const TextStyle(
                            color: EarthColors.goldMetallic,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '•  +${briefing.daysElapsed} day processed overnight',
                            style: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Net Wealth Shift: $sign${formatWholeNumber(netDelta.delta)} CR (${sign}${netDelta.deltaPct.toStringAsFixed(1)}%)  ·  Cashflow Net: +${formatWholeNumber(briefing.cashflow.netProfit)} CR/day',
                      style: TextStyle(
                        color: isPositiveDelta ? const Color(0xFF00E676) : Colors.redAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Market Moores & Headline Chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...briefing.marketMovements.take(3).map((m) {
                final isUp = m.deltaPct >= 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isUp ? const Color(0xFF00E676).withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward, size: 10, color: isUp ? const Color(0xFF00E676) : Colors.redAccent),
                      const SizedBox(width: 4),
                      Text(
                        '${m.commodity.toUpperCase()}: ${m.currentPrice.toStringAsFixed(1)} CR (${isUp ? '+' : ''}${m.deltaPct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          color: isUp ? const Color(0xFF00E676) : Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (briefing.civicSummary.recentCivicEvents.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: EarthColors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.gavel, size: 10, color: EarthColors.goldMetallic),
                      const SizedBox(width: 4),
                      Text(
                        briefing.civicSummary.recentCivicEvents.first,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // Expandable Detailed Breakdown
          if (_briefingExpanded) ...[
            const SizedBox(height: 12),
            const Divider(color: EarthColors.borderSubtle, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _microStat(
                    'OVERNIGHT REVENUE',
                    '+${formatWholeNumber(briefing.cashflow.totalIncome)} CR',
                    'Dividends & Market Sales',
                    const Color(0xFF00E676),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _microStat(
                    'OVERNIGHT EXPENSES',
                    '-${formatWholeNumber(briefing.cashflow.totalExpenses)} CR',
                    'Maintenance & Taxes',
                    Colors.orangeAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _microStat(
                    'ACTIVE CITIZEN RESIDENCY',
                    briefing.civicSummary.cityResidency,
                    'Tax Rate: ${briefing.civicSummary.cityTaxRatePct.toStringAsFixed(1)}%',
                    EarthColors.cyanAccent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _microStat(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: EarthColors.textMuted, fontSize: 8.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 9), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ==========================================================================
  // 3. WHAT DECISION SHOULD I MAKE NEXT?
  // ==========================================================================
  Widget _buildWhatDecisionNextCard(
    List<DecisionQueueItem> decisionItems,
    List<dynamic> opportunities,
  ) {
    final filteredDecisions = _filterDecisionItems(decisionItems);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('ALL', 'ALL (${decisionItems.length})'),
                    const SizedBox(width: 6),
                    _filterChip('CRITICAL', 'CRITICAL', color: Colors.orangeAccent),
                    const SizedBox(width: 6),
                    _filterChip('CORPORATION', 'ENTERPRISE', color: EarthColors.cyanAccent),
                    const SizedBox(width: 6),
                    _filterChip('CIVIC', 'CIVIC & DYNASTY', color: EarthColors.goldMetallic),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Render Decision Items
          if (filteredDecisions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No pending critical obligations. Your enterprise and civic standing are fully optimized.',
                  style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                ),
              ),
            )
          else
            ...filteredDecisions.take(4).map((item) => _buildUnifiedDecisionItem(item)),

          // Merged Live Opportunity Signals
          if (opportunities.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: EarthColors.borderSubtle, height: 1),
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.trending_up, size: 13, color: EarthColors.cyanAccent),
                SizedBox(width: 6),
                Text(
                  'LIVE STRATEGIC OPPORTUNITIES',
                  style: TextStyle(
                    color: EarthColors.cyanAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...opportunities.take(2).map((opp) {
              final mapOpp = Map<String, dynamic>.from(opp as Map);
              return _buildOpportunityStrip(mapOpp);
            }),
          ],
        ],
      ),
    );
  }

  List<DecisionQueueItem> _filterDecisionItems(List<DecisionQueueItem> items) {
    switch (_selectedActionFilter) {
      case 'CRITICAL':
        return items
            .where((i) =>
                i.riskLevel.toLowerCase() == 'critical' ||
                i.riskLevel.toLowerCase() == 'high')
            .toList();
      case 'CORPORATION':
        return items
            .where((i) =>
                i.category.toLowerCase() == 'business' ||
                i.category.toLowerCase() == 'machines' ||
                i.category.toLowerCase() == 'contracts' ||
                i.category.toLowerCase() == 'market')
            .toList();
      case 'CIVIC':
        return items
            .where((i) =>
                i.category.toLowerCase() == 'governance' ||
                i.category.toLowerCase() == 'civic' ||
                i.category.toLowerCase() == 'dynasty' ||
                i.category.toLowerCase() == 'technology' ||
                i.category.toLowerCase() == 'finance')
            .toList();
      case 'ALL':
      default:
        return items;
    }
  }

  Widget _filterChip(String filterKey, String label, {Color? color}) {
    final isSelected = _selectedActionFilter == filterKey;
    final activeColor = color ?? EarthColors.cyanAccent;

    return InkWell(
      onTap: () {
        EarthAudioEngine.instance.playClick();
        setState(() => _selectedActionFilter = filterKey);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : EarthColors.cardSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : EarthColors.borderSubtle,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? activeColor : EarthColors.textMuted,
            fontSize: 9.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedDecisionItem(DecisionQueueItem item) {
    final isCritical = item.riskLevel.toLowerCase() == 'critical' || item.riskLevel.toLowerCase() == 'high';
    final categoryColor = _getDecisionCategoryColor(item);
    final categoryIcon = _getDecisionCategoryIcon(item);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCritical
              ? Colors.orangeAccent.withValues(alpha: 0.35)
              : EarthColors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(categoryIcon, size: 16, color: categoryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isCritical
                            ? Colors.orangeAccent.withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.riskLevel.toUpperCase(),
                        style: TextStyle(
                          color: isCritical ? Colors.orangeAccent : Colors.white60,
                          fontSize: 8.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.whyItMatters,
                  style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Deadline: ${item.deadline}',
                      style: const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '•  Impact: ${item.expectedImpact}',
                        style: TextStyle(color: categoryColor, fontSize: 9, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              EarthAudioEngine.instance.playClick();
              if (widget.onExecuteDecision != null) {
                widget.onExecuteDecision!(item);
              } else if (widget.onNavigate != null) {
                widget.onNavigate!(item.targetSection);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isCritical ? Colors.orangeAccent : EarthColors.cyanAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              item.primaryActionLabel,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Color _getDecisionCategoryColor(DecisionQueueItem item) {
    switch (item.category.toLowerCase()) {
      case 'business':
      case 'machines':
        return Colors.orangeAccent;
      case 'governance':
      case 'civic':
        return EarthColors.goldMetallic;
      case 'technology':
      case 'market':
        return EarthColors.cyanAccent;
      default:
        return EarthColors.cyanAccent;
    }
  }

  IconData _getDecisionCategoryIcon(DecisionQueueItem item) {
    switch (item.category.toLowerCase()) {
      case 'business':
        return Icons.storefront_outlined;
      case 'machines':
        return Icons.build_outlined;
      case 'governance':
      case 'civic':
        return Icons.how_to_vote_outlined;
      case 'contracts':
        return Icons.handshake_outlined;
      case 'dynasty':
        return Icons.shield_outlined;
      default:
        return Icons.alt_route;
    }
  }

  Widget _buildOpportunityStrip(Map<String, dynamic> opp) {
    final title = opp['title']?.toString() ?? 'Strategic Opportunity';
    final detail = opp['detail']?.toString() ?? '';
    final signal = opp['signal']?.toString() ?? 'market';

    String targetSection = 'market';
    if (signal.contains('gov') || signal.contains('civic')) targetSection = 'civic';
    if (signal.contains('tech') || signal.contains('research')) targetSection = 'technology';
    if (signal.contains('business')) targetSection = 'business';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EarthColors.cyanAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flash_on, size: 12, color: EarthColors.cyanAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  detail,
                  style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              EarthAudioEngine.instance.playClick();
              widget.onNavigate?.call(targetSection);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: EarthColors.cyanAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'EXPLOIT',
                style: TextStyle(color: EarthColors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
