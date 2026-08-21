import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/models/decision_queue_item.dart';
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
  State<ExecutiveCommandSummary> createState() =>
      _ExecutiveCommandSummaryState();
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
        const Text(
          'EXECUTIVE OVERVIEW',
          style: TextStyle(
            color: EarthColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        // ====================================================================
        // QUESTION 1: WHAT IS MY CURRENT SITUATION?
        // ====================================================================
        _buildCleanTopicHeader(
          context,
          title: 'WHAT IS MY CURRENT SITUATION?',
          infoTitle: 'WHAT IS MY CURRENT SITUATION?',
          infoText:
              '• Situation Matrix & Core Metrics: Real-time overview of spendable capital reserves, enterprise solvency & fleet condition, biological energy & vitality status, and active strategic ambition progress.\n\n• Actionable Drill-Down: Select any matrix item to jump directly to its management interface.',
        ),
        const SizedBox(height: 8),
        _buildSituationMatrix(),
        const SizedBox(height: 34),

        // ====================================================================
        // QUESTION 2: WHAT CHANGED SINCE MY LAST VISIT?
        // ====================================================================
        _buildCleanTopicHeader(
          context,
          title: 'WHAT CHANGED SINCE MY LAST VISIT?',
          infoTitle: 'WHAT CHANGED SINCE MY LAST VISIT?',
          infoText:
              '• Nightly Cycle & Overnight Intelligence: Summary of net worth changes, overnight revenue & operating expenses, commodity market price swings, and passed civic referendums since your previous login session.',
        ),
        const SizedBox(height: 8),
        _buildWhatChangedCard(briefing),
        const SizedBox(height: 34),

        // ====================================================================
        // QUESTION 3: WHAT DECISION SHOULD I MAKE NEXT?
        // ====================================================================
        _buildCleanTopicHeader(
          context,
          title: 'WHAT DECISION SHOULD I MAKE NEXT?',
          infoTitle: 'WHAT DECISION SHOULD I MAKE NEXT?',
          infoText:
              '• Prioritized Decision Queue & Opportunities: Actionable operational alerts, critical risk warnings, pending contract obligations, and live market arbitrage opportunities requiring your executive decision.',
        ),
        const SizedBox(height: 8),
        _buildWhatDecisionNextCard(decisionItems, opportunities),
      ],
    );
  }

  // ==========================================================================
  // SECTION HEADERS
  // ==========================================================================
  Widget _buildCleanTopicHeader(
    BuildContext context, {
    required String title,
    required String infoTitle,
    required String infoText,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: EarthColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.info_outline,
              size: 14, color: EarthColors.textMuted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Info',
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: EarthColors.cardSurface,
                title: Text(
                  infoTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: EarthColors.cyanAccent,
                  ),
                ),
                content: Text(
                  infoText,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('CLOSE'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================================================
  // 1. SITUATION MATRIX
  // ==========================================================================
  Widget _buildSituationMatrix() {
    final human = widget.state.human;
    final business = widget.businessFinancials['business'] is Map
        ? Map<String, dynamic>.from(
            widget.businessFinancials['business'] as Map)
        : widget.state.business;
    final credits = asDouble(widget.state.human['credits']) ??
        asDouble(widget.state.json['player'] is Map
            ? (widget.state.json['player'] as Map)['credits']
            : null);
    final profit = asDouble(business['profit']);
    final margin = asDouble(business['margin'] ?? business['profit_margin']);
    final workforce = widget.state.json['workforce'] is List
        ? (widget.state.json['workforce'] as List)
        : const [];
    final activeStaff =
        workforce.where((e) => e is Map && e['status'] != 'dismissed').length;
    final capacity =
        asInt(business['workforceCapacity'] ?? business['staffCapacity']);
    final machines = widget.state.machines;
    final degradedMachines = machines.where((machine) {
      return machine is Map && (asDouble(machine['condition']) ?? 100) < 60;
    }).length;
    final city = widget.state.institutions['city'];
    final cityMap = city is Map
        ? Map<String, dynamic>.from(city)
        : const <String, dynamic>{};
    final cityPressure =
        asDouble(cityMap['service_pressure'] ?? cityMap['servicePressure']);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final itemWidth = isNarrow
            ? (constraints.maxWidth - 8) / 2
            : (constraints.maxWidth - 32) / 5;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _situationPill(
              width: itemWidth,
              label: 'LIQUID CAPITAL',
              value: credits == null
                  ? 'UNAVAILABLE'
                  : '${formatWholeNumber(credits)} CR',
              subvalue: 'Spendable now',
              icon: Icons.account_balance_wallet_outlined,
              accent: EarthColors.cyanAccent,
              onTap: () => widget.onNavigate?.call('finance'),
            ),
            _situationPill(
              width: itemWidth,
              label: 'ENTERPRISE HEALTH',
              value: profit == null
                  ? 'UNAVAILABLE'
                  : '${profit >= 0 ? '+' : ''}${formatWholeNumber(profit)} CR',
              subvalue: margin == null
                  ? 'Profit data unavailable'
                  : '${margin.toStringAsFixed(1)}% margin',
              icon: Icons.storefront_outlined,
              accent: profit == null || profit >= 0
                  ? const Color(0xFF00E676)
                  : Colors.orangeAccent,
              onTap: () => widget.onNavigate?.call('business'),
            ),
            _situationPill(
              width: itemWidth,
              label: 'WORKFORCE',
              value: activeStaff == 0 && capacity == null
                  ? 'UNAVAILABLE'
                  : '$activeStaff STAFF',
              subvalue: capacity == null
                  ? 'Capacity unavailable'
                  : '$capacity capacity',
              icon: Icons.groups_outlined,
              accent: Colors.lightBlueAccent,
              onTap: () => widget.onNavigate?.call('business'),
            ),
            _situationPill(
              width: itemWidth,
              label: 'OPERATIONS',
              value: machines.isEmpty
                  ? 'NO MACHINES'
                  : '${machines.length} MACHINES',
              subvalue: degradedMachines == 0
                  ? 'Running normally'
                  : '$degradedMachines need attention',
              icon: Icons.precision_manufacturing_outlined,
              accent:
                  degradedMachines == 0 ? cyanAccentColor : Colors.orangeAccent,
              onTap: () => widget.onNavigate?.call('business'),
            ),
            _situationPill(
              width: itemWidth,
              label: 'CITY EFFECT',
              value: cityMap['name']?.toString().toUpperCase() ?? 'UNAVAILABLE',
              subvalue: cityPressure == null
                  ? 'Pressure unavailable'
                  : 'Pressure ${cityPressure.toStringAsFixed(0)}%',
              icon: Icons.location_city_outlined,
              accent: cityPressure != null && cityPressure > 70
                  ? Colors.orangeAccent
                  : Colors.tealAccent,
              onTap: () => widget.onNavigate?.call('city'),
            ),
          ],
        );
      },
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
        border: Border.all(color: EarthColors.borderSubtle),
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
                  border: Border.all(color: EarthColors.borderSubtle),
                ),
                child: const Icon(Icons.newspaper_outlined,
                    size: 20, color: EarthColors.goldMetallic),
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
                            '•  Summary since the previous cycle',
                            style: TextStyle(
                                color: EarthColors.textMuted, fontSize: 10.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Net Wealth Shift: $sign${formatWholeNumber(netDelta.delta)} CR (${sign}${netDelta.deltaPct.toStringAsFixed(1)}%)  ·  Cashflow Net: +${formatWholeNumber(briefing.cashflow.netProfit)} CR/day',
                      style: TextStyle(
                        color: isPositiveDelta
                            ? const Color(0xFF00E676)
                            : Colors.redAccent,
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

          // Operational and civic headline changes
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (briefing.businessSummary.degradedMachinesCount > 0)
                _headlineChip(
                  Icons.precision_manufacturing_outlined,
                  '${briefing.businessSummary.degradedMachinesCount} machine${briefing.businessSummary.degradedMachinesCount == 1 ? '' : 's'} need attention',
                  Colors.orangeAccent,
                ),
              if (briefing.businessSummary.pendingContractsCount > 0)
                _headlineChip(
                  Icons.description_outlined,
                  '${briefing.businessSummary.pendingContractsCount} contract${briefing.businessSummary.pendingContractsCount == 1 ? '' : 's'} pending',
                  EarthColors.cyanAccent,
                ),
              if (briefing.civicSummary.recentCivicEvents.isNotEmpty)
                _headlineChip(
                    Icons.gavel,
                    briefing.civicSummary.recentCivicEvents.first,
                    EarthColors.goldMetallic),
            ],
          ),

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
          Text(label,
              style: const TextStyle(
                  color: EarthColors.textMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(sub,
              style: const TextStyle(color: Colors.white54, fontSize: 9),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _headlineChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.bold)),
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

    return Column(
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
                  _filterChip('CRITICAL', 'CRITICAL',
                      color: Colors.orangeAccent),
                  const SizedBox(width: 6),
                  _filterChip('CORPORATION', 'ENTERPRISE',
                      color: EarthColors.cyanAccent),
                  const SizedBox(width: 6),
                  _filterChip('CIVIC', 'CIVIC & DYNASTY',
                      color: EarthColors.goldMetallic),
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
          Container(
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: List.generate(filteredDecisions.length, (index) {
                  final item = filteredDecisions[index];
                  final isLast = index == filteredDecisions.length - 1;
                  return _buildUnifiedDecisionItem(item, isLast: isLast);
                }),
              ),
            ),
          ),

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
          color: isSelected
              ? activeColor.withValues(alpha: 0.18)
              : EarthColors.cardSurface,
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

  Widget _buildUnifiedDecisionItem(DecisionQueueItem item,
      {bool isLast = false}) {
    final isCritical = item.riskLevel.toLowerCase() == 'critical' ||
        item.riskLevel.toLowerCase() == 'high';
    final categoryColor = _getDecisionCategoryColor(item);
    final categoryIcon = _getDecisionCategoryIcon(item);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: EarthColors.borderSubtle),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isCritical
                            ? Colors.orangeAccent.withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.riskLevel.toUpperCase(),
                        style: TextStyle(
                          color:
                              isCritical ? Colors.orangeAccent : Colors.white60,
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
                  style: const TextStyle(
                      color: EarthColors.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Deadline: ${item.deadline}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '•  Impact: ${item.expectedImpact}',
                        style: TextStyle(
                            color: categoryColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
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
              backgroundColor:
                  isCritical ? Colors.orangeAccent : EarthColors.cyanAccent,
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
    if (signal.contains('gov') || signal.contains('civic'))
      targetSection = 'civic';
    if (signal.contains('tech') || signal.contains('research'))
      targetSection = 'technology';
    if (signal.contains('business')) targetSection = 'business';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: EarthColors.cyanAccent.withValues(alpha: 0.2)),
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
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  detail,
                  style: const TextStyle(
                      color: EarthColors.textMuted, fontSize: 9.5),
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
                style: TextStyle(
                    color: EarthColors.cyanAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
