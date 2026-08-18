import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../activity/activity_panel.dart';
import '../contracts/contracts_panel.dart';
import '../finance/personal_finance_panel.dart';
import '../governance/governance_panels.dart';
import '../institutions/institutions_panels.dart';
import '../lifecycle/lifecycle_panels.dart';
import '../market/market_panels.dart';
import '../operations/ai_panel.dart';
import '../operations/business_panel.dart';
import '../operations/machines_panel.dart';
import '../operations/technology_panel.dart';
import 'command_executive_quadrant.dart';
import 'hero_card.dart';
import 'opportunity_panel.dart';
import 'decision_queue_panel.dart';
import '../../core/models/decision_queue_item.dart';

String dashboardSectionTitle(String section) => switch (section) {
      'market' => 'MARKET',
      'business' => 'BUSINESS',
      'civic' => 'CIVIC',
      'city' => 'CITY',
      'technology' => 'TECHNOLOGY',
      'life' => 'LEGACY',
      'contracts' => 'CONTRACTS',
      'finance' => 'FINANCE',
      'activity' => 'ACTIVITY',
      _ => 'COMMAND',
    };

class Dashboard extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final List<dynamic> events;
  final List<dynamic> notifications;
  final List<dynamic> ownershipEvents;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final List<dynamic> membershipEvents;
  final List<dynamic> authorityEvents;
  final List<dynamic> productionCatalog;
  final Map<String, dynamic> marketHistory;
  final Map<String, dynamic> pantheon;
  final Map<String, dynamic> personalFinanceData;
  final List<dynamic> contracts;
  final bool isLiveConnected;
  final bool isReconnecting;
  final LiveConnectionStatus? connectionStatus;
  final int unreadNotifications;
  final Map<String, GlobalKey> sectionKeys;
  final String selectedSection;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function(Future<EarthState> Function()) action;
  final VoidCallback? onRefreshEvents;
  final Future<void> Function(String)? onMarkNotificationRead;
  final Future<void> Function()? onMarkAllNotificationsRead;

  const Dashboard({
    super.key,
    required this.state,
    required this.busy,
    required this.events,
    required this.notifications,
    required this.ownershipEvents,
    required this.businessOwnership,
    required this.businessFinancials,
    required this.businessProfile,
    required this.membershipEvents,
    required this.authorityEvents,
    required this.productionCatalog,
    this.marketHistory = const {},
    this.pantheon = const {},
    this.personalFinanceData = const {},
    this.contracts = const [],
    this.isLiveConnected = true,
    this.isReconnecting = false,
    this.connectionStatus,
    required this.unreadNotifications,
    required this.sectionKeys,
    this.selectedSection = 'command',
    this.onNavigate,
    required this.action,
    this.onRefreshEvents,
    this.onMarkNotificationRead,
    this.onMarkAllNotificationsRead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSection == 'command') ...[
          HeroCard(key: sectionKeys['command'], state: state),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final numCols = availableWidth >= 1200
                  ? 6
                  : availableWidth >= 600
                      ? 3
                      : 2;
              final itemWidth = (availableWidth - (numCols - 1) * 14) / numCols;
              final flows = (state.json['resourceFlows'] as Map<String, dynamic>?) ?? const {};

              final creditsFlow = flows['credits'] as Map<String, dynamic>? ??
                  {'inflow': 1250, 'outflow': 320, 'net': 930};
              final foodFlow = flows['food'] as Map<String, dynamic>? ??
                  {'inflow': 16, 'outflow': 4, 'net': 12};
              final matFlow = (flows['materials'] ?? flows['material']) as Map<String, dynamic>? ??
                  {'inflow': 24, 'outflow': 8, 'net': 16};
              final compFlow = flows['components'] as Map<String, dynamic>? ??
                  {'inflow': 10, 'outflow': 12, 'net': -2};
              final energyFlow = flows['energy'] as Map<String, dynamic>? ??
                  {'inflow': 30, 'outflow': 18, 'net': 12};
              final computeFlow = flows['compute'] as Map<String, dynamic>? ??
                  {'inflow': 12, 'outflow': 4, 'net': 8};

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'CREDITS',
                    accent: violetColor,
                    inflow: asDoubleOr(creditsFlow['inflow'], 1250),
                    outflow: asDoubleOr(creditsFlow['outflow'], 320),
                    net: asDoubleOr(creditsFlow['net'], 930),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.eco_outlined,
                    label: 'FOOD',
                    accent: Colors.lightGreenAccent,
                    inflow: asDoubleOr(foodFlow['inflow'], 16),
                    outflow: asDoubleOr(foodFlow['outflow'], 4),
                    net: asDoubleOr(foodFlow['net'], 12),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.view_in_ar_outlined,
                    label: 'MATERIALS',
                    accent: Colors.tealAccent,
                    inflow: asDoubleOr(matFlow['inflow'], 24),
                    outflow: asDoubleOr(matFlow['outflow'], 8),
                    net: asDoubleOr(matFlow['net'], 16),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.settings_outlined,
                    label: 'COMPONENTS',
                    accent: cyanAccentColor,
                    inflow: asDoubleOr(compFlow['inflow'], 10),
                    outflow: asDoubleOr(compFlow['outflow'], 12),
                    net: asDoubleOr(compFlow['net'], -2),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.bolt_outlined,
                    label: 'ENERGY',
                    accent: Colors.amberAccent,
                    inflow: asDoubleOr(energyFlow['inflow'], 30),
                    outflow: asDoubleOr(energyFlow['outflow'], 18),
                    net: asDoubleOr(energyFlow['net'], 12),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.memory_rounded,
                    label: 'COMPUTE',
                    accent: violetColor,
                    inflow: asDoubleOr(computeFlow['inflow'], 12),
                    outflow: asDoubleOr(computeFlow['outflow'], 4),
                    net: asDoubleOr(computeFlow['net'], 8),
                  ),
                ],
              );
            },
          ),
          if (state.human['politicalMaturity'] == false)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'POLITICAL MATURITY · AVAILABLE FROM GAME DAY ${state.human['politicalEligibilityGameDay']}',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 10,
                  letterSpacing: .7,
                ),
              ),
            ),
          const SizedBox(height: 18),
        ],
        ..._selectedPanels(),
      ],
    );
  }

  List<Widget> _selectedPanels() {
    switch (selectedSection) {
      case 'market':
        return [
          MarketSignalsPanel(
            panelKey: sectionKeys['market'],
            state: state,
            busy: busy,
            priceHistory: marketHistory,
            action: action,
          ),
          MarketOrderBookPanel(state: state),
          MyMarketOrdersPanel(state: state, busy: busy, action: action),
          MacroLiquidityPanel(state: state),
        ];
      case 'business':
        return [
          BusinessPanel(
            panelKey: sectionKeys['business'],
            state: state,
            busy: busy,
            businessOwnership: businessOwnership,
            businessFinancials: businessFinancials,
            businessProfile: businessProfile,
            action: action,
          ),
          ProductionEventsPanel(state: state),
          InstitutionSolvencyPanel(state: state, busy: busy, action: action),
        ];
      case 'civic':
        return [
          HumanServicesPanel(panelKey: sectionKeys['civic'], state: state),
          ProposalPanel(state: state, busy: busy, action: action),
          RolesPanel(state: state, busy: busy, action: action),
          CommunitiesPanel(state: state, busy: busy, action: action),
          CivicMembershipHistoryPanel(membershipEvents: membershipEvents),
          AuthorityHistoryPanel(authorityEvents: authorityEvents),
          PublicFinanceGovernancePanel(
            state: state,
            busy: busy,
            action: action,
          ),
        ];
      case 'city':
        return [
          InstitutionsCapacityPanel(
            panelKey: sectionKeys['city'],
            state: state,
            busy: busy,
            action: action,
          ),
          CommunitiesPanel(state: state, busy: busy, action: action),
          InstitutionSolvencyPanel(state: state, busy: busy, action: action),
          WorldRankingsPanel(state: state),
        ];
      case 'technology':
        return [
          TechnologyPanel(
            panelKey: sectionKeys['technology'],
            state: state,
            busy: busy,
            action: action,
          ),
          MachinesPanel(
            state: state,
            busy: busy,
            productionCatalog: productionCatalog,
            action: action,
          ),
          AiAssistantPanel(state: state, busy: busy, action: action),
          AiRecommendationsPanel(state: state),
          const EarthPanel(
            title: 'EIGHT-SECTOR ECONOMY / INTERDEPENDENT MATRIX',
            infoDescription:
                '• Eight-Sector Industrial Matrix: The macroeconomic production loop linking raw extraction, power generation, mechanical fabrication, residential housing, computational infrastructure, and research.\n\n• Interdependency Loops:\n  - ENERGY & EXTRACTION: Powers high-capacity mining and bio-nutrient yields.\n  - COMPONENTS & MACHINES: Converts raw ores into precision subassemblies and industrial fabrication rigs.\n  - MAINTENANCE & HOUSING: Preserves fleet condition and citizen vitality.\n  - COMPUTE & R&D: Fuels quantum research algorithms unlocking patentable technologies.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(Icons.bolt_outlined, size: 14, color: Colors.amberAccent),
                  label: Text('ENERGY', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.terrain_outlined, size: 14, color: Colors.tealAccent),
                  label: Text('EXTRACTION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.settings_outlined, size: 14, color: cyanAccentColor),
                  label: Text('COMPONENTS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.precision_manufacturing_outlined, size: 14, color: violetColor),
                  label: Text('MACHINES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.build_outlined, size: 14, color: Colors.orangeAccent),
                  label: Text('MAINTENANCE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.home_work_outlined, size: 14, color: Colors.lightGreenAccent),
                  label: Text('HOUSING', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.memory_outlined, size: 14, color: cyanAccentColor),
                  label: Text('COMPUTE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
                Chip(
                  avatar: Icon(Icons.biotech_outlined, size: 14, color: violetColor),
                  label: Text('R&D', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ];
      case 'life':
        return [
          SuccessionPanel(
            state: state,
            busy: busy,
            action: action,
          ),
          LedgerPanel(state: state),
          OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
          HistoryArchivePanel(state: state),
          PantheonPanel(pantheon: pantheon),
        ];
      case 'contracts':
        return [
          ContractsPanel(
            panelKey: sectionKeys['contracts'],
            state: state,
            busy: busy,
            contracts: contracts,
            action: action,
          ),
          AuthorityHistoryPanel(authorityEvents: authorityEvents),
        ];
      case 'finance':
        return [
          PersonalFinancePanel(
            panelKey: sectionKeys['finance'],
            state: state,
            busy: busy,
            personalFinanceData: personalFinanceData,
            action: action,
          ),
          LedgerPanel(state: state),
        ];
      case 'activity':
        return [
          ActivityPanel(
            panelKey: sectionKeys['activity'],
            events: events,
            notifications: notifications,
            unreadCount: unreadNotifications,
            isLiveConnected: isLiveConnected,
            isReconnecting: isReconnecting,
            connectionStatus: connectionStatus,
            onRefresh: onRefreshEvents ?? () {},
            onMarkRead: onMarkNotificationRead ?? (_) async {},
            onMarkAllRead: onMarkAllNotificationsRead ?? () async {},
          ),
          OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
          HistoryArchivePanel(state: state),
        ];
      case 'command':
      default:
        final decisionQueueItems = DecisionQueueItem.synthesizeFromState(state);
        return [
          DecisionQueuePanel(
            items: decisionQueueItems,
            onNavigate: onNavigate,
            onExecuteDecision: (item) {
              if (onNavigate != null) {
                onNavigate!(item.targetSection);
              }
            },
          ),
          const SizedBox(height: 16),
          OpportunityPanel(
            opportunities: state.opportunities,
            onNavigate: onNavigate,
          ),
          const SizedBox(height: 16),
          CommandExecutiveQuadrant(
            state: state,
            businessFinancials: businessFinancials,
            contracts: contracts,
            onNavigate: onNavigate,
          ),
        ];
    }
  }
}

class EarthFlowMetric extends StatelessWidget {
  final double? width;
  final IconData icon;
  final String label;
  final Color accent;
  final double inflow;
  final double outflow;
  final double net;

  const EarthFlowMetric({
    super.key,
    this.width,
    required this.icon,
    required this.label,
    required this.accent,
    required this.inflow,
    required this.outflow,
    required this.net,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = net > 0;
    final isNegative = net < 0;
    final netPrefix = isPositive ? '+' : '';
    final netColor = isPositive
        ? Colors.greenAccent
        : isNegative
            ? Colors.redAccent
            : mutedColor;
    final badgeLabel = isPositive
        ? 'SURPLUS'
        : isNegative
            ? 'DEFICIT'
            : 'STABLE';
    final badgeColor = isPositive
        ? Colors.greenAccent.withValues(alpha: .15)
        : isNegative
            ? Colors.redAccent.withValues(alpha: .15)
            : Colors.white10;
    final badgeTextColor = isPositive
        ? Colors.greenAccent
        : isNegative
            ? Colors.redAccent
            : mutedColor;

    final inStr = formatWholeNumber(inflow);
    final outStr = formatWholeNumber(outflow);
    final netStr = '$netPrefix${formatWholeNumber(net)} /day';

    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 1.1,
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeTextColor.withValues(alpha: .3)),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: badgeTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              netStr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: netColor,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  '▲ +$inStr in',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.greenAccent,
                  ),
                ),
                Text(
                  '▼ -$outStr out',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
