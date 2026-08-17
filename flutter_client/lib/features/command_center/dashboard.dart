import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
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
              final useFourColumns = availableWidth >= 700;
              final itemWidth = useFourColumns
                  ? (availableWidth - 3 * 14) / 4
                  : (availableWidth - 14) / 2;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  EarthMetric(
                    width: itemWidth,
                    label: 'CREDITS',
                    value: '${state.human['credits']} C',
                    accent: violetColor,
                    hint:
                        'Personal liquid currency for market trade, machinery, and investments.',
                    onInfoTap: () => showEarthInfoDialog(
                      context,
                      title: 'CREDITS & CURRENCY',
                      subtitle: 'Personal liquid account balance',
                      items: [
                        {
                          'label': 'Liquid Reserve (${state.human['credits']} C)',
                          'description':
                              'The non-inflationary base currency of EARTH. Used to purchase physical commodities, machinery, research licenses, and pay city taxes.',
                        },
                      ],
                    ),
                  ),
                  EarthMetric(
                    width: itemWidth,
                    label: 'STANDING',
                    value: '${state.human['standing']}',
                    accent: Colors.tealAccent,
                    hint:
                        'Civic reputation within your city, influencing voting weight.',
                    onInfoTap: () => showEarthInfoDialog(
                      context,
                      title: 'CIVIC STANDING',
                      subtitle: 'Municipal influence and reputation',
                      items: [
                        {
                          'label': 'Standing Score (${state.human['standing']})',
                          'description':
                              'Earned through active economic production, community contributions, and assembly participation. Enhances your voting weight in local ordinances.',
                        },
                      ],
                    ),
                  ),
                  EarthMetric(
                    width: itemWidth,
                    label: 'LEGACY',
                    value: '${state.human['legacy']}',
                    accent: Colors.indigoAccent,
                    hint:
                        'Dynastic achievement score passed down to designated successors.',
                    onInfoTap: () => showEarthInfoDialog(
                      context,
                      title: 'DYNASTIC LEGACY',
                      subtitle: 'Generational achievement and lineage',
                      items: [
                        {
                          'label': 'Legacy Points (${state.human['legacy']})',
                          'description':
                              'Accumulated across lifetimes. Determines your historical standing in the UC Archive and unlocks dynastic foundation privileges.',
                        },
                      ],
                    ),
                  ),
                  EarthMetric(
                    width: itemWidth,
                    label: 'WORLD HEALTH',
                    value: '${state.world['health']} / 100',
                    accent: Colors.orangeAccent,
                    hint:
                        'Composite simulation health across resource scarcity, energy, and costs.',
                    onInfoTap: () => showEarthInfoDialog(
                      context,
                      title: 'WORLD HEALTH SCORE',
                      subtitle: 'Planetary simulation vitality index',
                      items: [
                        {
                          'label': 'Health Score (${state.world['health']} / 100)',
                          'description':
                              'Composite index reflecting ecological stability, machine maintenance rates, and macroeconomic liquidity.',
                        },
                      ],
                    ),
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
          // REDESIGNED RESOURCE RESERVES HUD
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'PHYSICAL COMMODITIES & RESERVES',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                            color: mutedColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.info_outline,
                            size: 13,
                            color: mutedColor.withValues(alpha: .7),
                          ),
                          tooltip: 'Commodity reserves information',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => showEarthInfoDialog(
                            context,
                            title: 'PHYSICAL COMMODITIES & RESERVES',
                            subtitle:
                                'The 4 fundamental pillars of the physical economy',
                            items: [
                              {
                                'label': 'Materials (M)',
                                'description':
                                    'Base matter and raw industrial feedstock utilized to manufacture components and construct city infrastructure.',
                              },
                              {
                                'label': 'Components (C)',
                                'description':
                                    'Manufactured precision sub-assemblies and replacement parts required to operate and maintain machinery.',
                              },
                              {
                                'label': 'Energy (E)',
                                'description':
                                    'Electrical power consumed per cycle to power machines and support municipal infrastructure grids.',
                              },
                              {
                                'label': 'Compute (Q)',
                                'description':
                                    'Processing power utilized for AI assistants and technology R&D progress.',
                              },
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'LCI ${state.world['livingCostIndex'] ?? '1.00'}  ·  ESI ${state.world['essentialServicesIndex'] ?? '1.00'}',
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: .6,
                        color: mutedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final resWidth = constraints.maxWidth >= 600
                        ? (constraints.maxWidth - 3 * 12) / 4
                        : (constraints.maxWidth - 12) / 2;

                    final entries = [
                      {
                        'key': 'Materials',
                        'symbol': '❖',
                        'val': state.resources['materials'] ??
                            state.resources['material'] ??
                            '0',
                        'color': Colors.tealAccent,
                      },
                      {
                        'key': 'Components',
                        'symbol': '⚙',
                        'val': state.resources['components'] ?? '0',
                        'color': cyanAccentColor,
                      },
                      {
                        'key': 'Energy',
                        'symbol': '⚡',
                        'val': state.resources['energy'] ?? '0',
                        'color': Colors.amberAccent,
                      },
                      {
                        'key': 'Compute',
                        'symbol': '◈',
                        'val': state.resources['compute'] ??
                            state.resources['computing'] ??
                            '0',
                        'color': violetColor,
                      },
                    ];

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: entries.map((entry) {
                        final valStr = entry['val'] is num
                            ? (entry['val'] as num).toInt().toString()
                            : entry['val'].toString();

                        return Container(
                          width: resWidth,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(8),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              Text(
                                entry['symbol'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: entry['color'] as Color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (entry['key'] as String).toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        letterSpacing: .8,
                                        color: mutedColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      valStr,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: inkColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
          PersonalFinancePanel(state: state, busy: busy, action: action),
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
            title: 'EIGHT-SECTOR ECONOMY',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('ENERGY')),
                Chip(label: Text('EXTRACTION')),
                Chip(label: Text('COMPONENTS')),
                Chip(label: Text('MACHINES')),
                Chip(label: Text('MAINTENANCE')),
                Chip(label: Text('HOUSING')),
                Chip(label: Text('COMPUTE')),
                Chip(label: Text('R&D')),
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
            onRefresh: onRefreshEvents ?? () {},
            onMarkRead: onMarkNotificationRead ?? (_) async {},
            onMarkAllRead: onMarkAllNotificationsRead ?? () async {},
          ),
          OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
          HistoryArchivePanel(state: state),
        ];
      case 'command':
      default:
        return [
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
