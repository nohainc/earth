import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_queue_item.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
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
import 'hero_card.dart';
import 'executive_command_summary.dart';
import 'objectives_panel.dart';
import '../dynasty/dynasty_tree_dialog.dart';
import '../contracts/supply_contracts_dialog.dart';
import '../market/derivatives_dialog.dart';
import '../finance/net_worth_analytics_dialog.dart';
import 'daily_briefing_dialog.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/player_objective.dart';
import '../communications/social_gameplay_panel.dart';
import '../communications/comm_link_dialog.dart';
import '../lifecycle/historical_archive_panel.dart';
import 'quick_actions_panel.dart';

String dashboardSectionTitle(String section) => switch (section) {
      'command' => 'COMMAND CENTER',
      'market' => 'MARKET',
      'derivatives' => 'FUTURES & DERIVATIVES',
      'net_worth' => 'NET WORTH ANALYTICS',
      'briefing' => 'EXECUTIVE BRIEFING',
      'messages' => 'MESSAGES',
      'business' => 'BUSINESS',
      'civic' => 'PUBLIC',
      'corporation' => 'CORPORATION',
      'city' => 'MY CITY',
      'dynasty' => 'FAMILY',
      'technology' => 'TECHNOLOGY',
      'patents' => 'PATENTS & LICENSING',
      'machines' => 'MACHINES & PRODUCTION',
      'public-finance' => 'PUBLIC FINANCE',
      'civic-rankings' => 'CIVIC RANKINGS',
      'history' => 'ARCHIVE',
      'life' => 'LIFE',
      'pantheon' => 'MEMORIAL',
      'contracts' => 'CONTRACTS',
      'finance' => 'FINANCE',
      'activity' => 'ACTIVITY & EVENTS',
      _ => 'COMMAND CENTER',
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
  final Map<String, dynamic>? activeBusiness;
  final ValueChanged<String>? onSelectBusiness;
  final List<dynamic> membershipEvents;
  final List<dynamic> authorityEvents;
  final List<dynamic> productionCatalog;
  final Map<String, dynamic> marketHistory;
  final Map<String, dynamic> pantheon;
  final Map<String, dynamic> personalFinanceData;
  final List<dynamic> contracts;
  final List<dynamic> socialInitiatives;
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
    this.activeBusiness,
    this.onSelectBusiness,
    required this.membershipEvents,
    required this.authorityEvents,
    required this.productionCatalog,
    this.marketHistory = const {},
    this.pantheon = const {},
    this.personalFinanceData = const {},
    this.contracts = const [],
    this.socialInitiatives = const [],
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
    final decisions = DecisionQueueItem.synthesizeFromState(state);
    final visibleDecisions = decisions.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSection == 'command') ...[
          HeroCard(key: sectionKeys['command'], state: state),
          const SizedBox(height: 34),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (visibleDecisions.isNotEmpty
                          ? visibleDecisions.first.riskColor
                          : cyanAccentColor)
                      .withValues(alpha: .16),
                  surfaceColor.withValues(alpha: .78),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: (visibleDecisions.isNotEmpty
                          ? visibleDecisions.first.riskColor
                          : cyanAccentColor)
                      .withValues(alpha: .35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      visibleDecisions.isNotEmpty
                          ? Icons.priority_high_rounded
                          : Icons.check_circle_outline,
                      color: visibleDecisions.isNotEmpty
                          ? visibleDecisions.first.riskColor
                          : cyanAccentColor,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('TODAY\'S MANAGEMENT FOCUS',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: mutedColor)),
                    ),
                    Text(
                      visibleDecisions.isEmpty
                          ? 'NO OPEN DECISIONS'
                          : '${visibleDecisions.length} ${visibleDecisions.length == 1 ? 'PRIORITY' : 'PRIORITIES'}',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: mutedColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (visibleDecisions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(left: 36, bottom: 8),
                    child: Text(
                      'Operations are stable. Choose the next investment in people, capacity, or research.',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  ...visibleDecisions
                      .map((decision) => _focusDecisionRow(decision)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'CURRENT OPERATIONS',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final numCols = availableWidth >= 1200
                  ? 6
                  : availableWidth >= 600
                      ? 3
                      : 2;
              final itemWidth = (availableWidth - (numCols - 1) * 14) / numCols;
              final flows =
                  (state.json['resourceFlows'] as Map<String, dynamic>?) ??
                      const {};

              final creditsFlow = flows['credits'] as Map<String, dynamic>? ??
                  {'inflow': 1250, 'outflow': 320, 'net': 930};
              final foodFlow = flows['food'] as Map<String, dynamic>? ??
                  {'inflow': 16, 'outflow': 4, 'net': 12};
              final matFlow = (flows['materials'] ?? flows['material'])
                      as Map<String, dynamic>? ??
                  {'inflow': 24, 'outflow': 8, 'net': 16};
              final energyFlow = flows['energy'] as Map<String, dynamic>? ??
                  {'inflow': 30, 'outflow': 18, 'net': 12};

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'CREDITS',
                    accent: EarthResourceColors.credits,
                    inflow: asDoubleOr(creditsFlow['inflow'], 1250),
                    outflow: asDoubleOr(creditsFlow['outflow'], 320),
                    net: asDoubleOr(creditsFlow['net'], 930),
                    onTap: () => onNavigate?.call('finance'),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.eco_outlined,
                    label: 'FOOD',
                    accent: EarthResourceColors.food,
                    inflow: asDoubleOr(foodFlow['inflow'], 16),
                    outflow: asDoubleOr(foodFlow['outflow'], 4),
                    net: asDoubleOr(foodFlow['net'], 12),
                    onTap: () => onNavigate?.call('market'),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.view_in_ar_outlined,
                    label: 'MATERIALS',
                    accent: EarthResourceColors.materials,
                    inflow: asDoubleOr(matFlow['inflow'], 24),
                    outflow: asDoubleOr(matFlow['outflow'], 8),
                    net: asDoubleOr(matFlow['net'], 16),
                    onTap: () => onNavigate?.call('market'),
                  ),
                  EarthFlowMetric(
                    width: itemWidth,
                    icon: Icons.bolt_outlined,
                    label: 'ENERGY',
                    accent: EarthResourceColors.energy,
                    inflow: asDoubleOr(energyFlow['inflow'], 30),
                    outflow: asDoubleOr(energyFlow['outflow'], 18),
                    net: asDoubleOr(energyFlow['net'], 12),
                    onTap: () => onNavigate?.call('business'),
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
          const SizedBox(height: 34),
        ],
        ..._selectedPanels(),
      ],
    );
  }

  Widget _focusDecisionRow(DecisionQueueItem decision) {
    return Padding(
      padding: const EdgeInsets.only(left: 36, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: decision.riskColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  decision.title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${decision.deadline} · ${decision.expectedImpact}',
                  style: const TextStyle(fontSize: 10, color: mutedColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onNavigate == null
                ? null
                : () => onNavigate!.call(decision.targetSection),
            child: Text(decision.primaryActionLabel),
          ),
        ],
      ),
    );
  }

  List<Widget> _selectedPanels() {
    switch (selectedSection) {
      case 'market':
        return [
          LayoutBuilder(
            builder: (context, _) {
              final signals = MarketSignalsPanel(
                panelKey: sectionKeys['market'],
                state: state,
                busy: busy,
                priceHistory: marketHistory,
                action: action,
              );
              final supplies = SuppliesTodayPanel(state: state);
              final orderBook = MarketOrderBookPanel(state: state);
              final orders =
                  MyMarketOrdersPanel(state: state, busy: busy, action: action);
              final macro = MacroLiquidityPanel(state: state);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  supplies,
                  const SizedBox(height: 24),
                  signals,
                  const SizedBox(height: 24),
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                      childrenPadding: EdgeInsets.zero,
                      title: const Text(
                        'ADVANCED TRADE TOOLS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: mutedColor,
                        ),
                      ),
                      subtitle: const Text(
                        'Order book, open orders, and macro liquidity analysis',
                        style: TextStyle(fontSize: 11, color: mutedColor),
                      ),
                      children: [
                        const SizedBox(height: 12),
                        orderBook,
                        const SizedBox(height: 24),
                        orders,
                        const SizedBox(height: 24),
                        macro,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ];
      case 'derivatives':
        return [
          DerivativesDialog(
            api: const EarthApi(),
            state: state,
            isPageMode: true,
            onNavigate: onNavigate,
          ),
        ];
      case 'net_worth':
        return [
          NetWorthAnalyticsDialog(
            api: const EarthApi(),
            isPageMode: true,
            onNavigate: onNavigate,
          ),
        ];
      case 'briefing':
        return [
          DailyBriefingDialog(
            api: const EarthApi(),
            isPageMode: true,
            onNavigate: onNavigate ?? (_) {},
          ),
        ];
      case 'messages':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final commLink = CommLinkDialog(
                api: const EarthApi(),
                state: state,
                isPageMode: true,
                onNavigate: onNavigate,
              );
              final initiatives = SocialGameplayPanel(
                initiatives: socialInitiatives,
                gameDay: asInt((state.json['clock']
                        as Map<String, dynamic>?)?['day']) ??
                    1,
                onChanged: onRefreshEvents,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  commLink,
                  const SizedBox(height: 34),
                  initiatives,
                ],
              );
            },
          ),
        ];
      case 'dynasty':
        return [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DynastyTreeDialog(
              api: const EarthApi(),
              state: state,
              isPageMode: true,
              onNavigate: onNavigate,
            ),
            const SizedBox(height: 34),
            HistoricalDynastiesPanel(pantheon: pantheon),
          ]),
        ];
      case 'business':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final business = BusinessPanel(
                panelKey: sectionKeys['business'],
                state: state,
                busy: busy,
                businessOwnership: businessOwnership,
                businessFinancials: businessFinancials,
                businessProfile: businessProfile,
                activeBusiness: activeBusiness,
                onSelectBusiness: onSelectBusiness,
                action: action,
              );
              final managerOverview = BusinessManagerOverviewPanel(
                  state: state,
                  businessFinancials: businessFinancials,
                  businessProfile: businessProfile,
                  activeBusiness: activeBusiness);
              final aiAssistant =
                  AiAssistantPanel(state: state, busy: busy, action: action);
              final recommendations = AiRecommendationsPanel(state: state);
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          managerOverview,
                          const SizedBox(height: 34),
                          business
                        ])),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          aiAssistant,
                          const SizedBox(height: 34),
                          recommendations,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  managerOverview,
                  const SizedBox(height: 34),
                  business,
                  const SizedBox(height: 34),
                  aiAssistant,
                  const SizedBox(height: 34),
                  recommendations,
                ],
              );
            },
          ),
        ];
      case 'civic':
      case 'governance':
        return [
          ProposalPanel(state: state, busy: busy, action: action),
          const SizedBox(height: 34),
          PublicFinanceGovernancePanel(
              state: state, busy: busy, action: action),
        ];
      case 'corporation':
        return [
          LayoutBuilder(builder: (context, constraints) {
            final overview = CorporationOverviewPanel(
                state: state, busy: busy, action: action);
            final isMember = state.membership?['corporation_id'] != null;
            if (isMember) {
              final corporationId =
                  state.membership?['corporation_id']?.toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  overview,
                  if (corporationId != null) ...[
                    const SizedBox(height: 34),
                    ProposalPanel(
                      state: state,
                      busy: busy,
                      action: action,
                      institutionId: corporationId,
                      scopeLabel: 'CORPORATION',
                    ),
                    const SizedBox(height: 34),
                    RolesPanel(
                      state: state,
                      busy: busy,
                      action: action,
                      institutionId: corporationId,
                    ),
                  ],
                ],
              );
            }
            final directory = CorporationDirectoryPanel(
                state: state, busy: busy, action: action);
            if (constraints.maxWidth > 1000) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: overview),
                    const SizedBox(width: 34),
                    Expanded(child: directory),
                  ]);
            }
            return Column(
                children: [overview, const SizedBox(height: 34), directory]);
          })
        ];
      case 'city':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final humanServices = HumanServicesPanel(
                  panelKey: sectionKeys['city'], state: state);
              final institutions = InstitutionsCapacityPanel(
                state: state,
                busy: busy,
                action: action,
              );
              final cityId = state.membership?['city_id']?.toString();
              final cityProposal = cityId == null
                  ? null
                  : ProposalPanel(
                      state: state,
                      busy: busy,
                      action: action,
                      institutionId: cityId,
                      scopeLabel: 'CITY');
              final communities =
                  CommunitiesPanel(state: state, busy: busy, action: action);
              final cityImpact = CityImpactPanel(state: state);
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          institutions,
                          if (cityProposal != null) ...[
                            const SizedBox(height: 34),
                            cityProposal,
                          ],
                          if (cityId != null) ...[
                            const SizedBox(height: 34),
                            RolesPanel(
                              state: state,
                              busy: busy,
                              action: action,
                              institutionId: cityId,
                            ),
                          ],
                          const SizedBox(height: 34),
                          humanServices,
                          const SizedBox(height: 34),
                          communities,
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cityImpact,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  institutions,
                  if (cityProposal != null) ...[
                    const SizedBox(height: 34),
                    cityProposal,
                  ],
                  if (cityId != null) ...[
                    const SizedBox(height: 34),
                    RolesPanel(
                      state: state,
                      busy: busy,
                      action: action,
                      institutionId: cityId,
                    ),
                  ],
                  const SizedBox(height: 34),
                  humanServices,
                  const SizedBox(height: 34),
                  cityImpact,
                  const SizedBox(height: 34),
                  communities,
                ],
              );
            },
          ),
        ];
      case 'technology':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final technology = TechnologyPanel(
                panelKey: sectionKeys['technology'],
                state: state,
                busy: busy,
                action: action,
              );
              final matrix = TechnologyOutcomePanel(state: state);
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          technology,
                          const SizedBox(height: 34),
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          matrix,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  technology,
                  const SizedBox(height: 34),
                  matrix,
                ],
              );
            },
          ),
        ];
      case 'machines':
        return [
          MachinesPanel(
            state: state,
            busy: busy,
            productionCatalog: productionCatalog,
            activeBusiness: activeBusiness,
            action: action,
          )
        ];
      case 'patents':
        return [TechnologyPortfolioPanel(state: state, action: action)];
      case 'public-finance':
        return [
          PublicFinanceGovernancePanel(state: state, busy: busy, action: action)
        ];
      case 'civic-rankings':
        return [CivicRankingsPanel(state: state)];
      case 'history':
        return [HistoricalArchivePanel(pantheon: pantheon, events: events)];
      case 'life':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final succession = SuccessionPanel(
                state: state,
                busy: busy,
                action: action,
              );
                  final lifeToday = LifeTodayPanel(state: state);
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          lifeToday,
                          const SizedBox(height: 34),
                          succession,
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  lifeToday,
                  const SizedBox(height: 34),
                  succession,
                  const SizedBox(height: 34),
                ],
              );
            },
          ),
        ];
      case 'pantheon':
        return [PantheonPanel(pantheon: pantheon)];
      case 'contracts':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final supply = SupplyContractsDialog(
                api: const EarthApi(),
                state: state,
                isPageMode: true,
                onNavigate: onNavigate,
              );
              final revenueOverview = ContractRevenueOverviewPanel(
                state: state,
                contracts: contracts,
              );
              final contractsPanel = ContractsPanel(
                panelKey: sectionKeys['contracts'],
                state: state,
                busy: busy,
                contracts: contracts,
                action: action,
              );
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          revenueOverview,
                          const SizedBox(height: 34),
                          supply
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          contractsPanel,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  revenueOverview,
                  const SizedBox(height: 34),
                  supply,
                  const SizedBox(height: 34),
                  contractsPanel,
                ],
              );
            },
          ),
        ];
      case 'finance':
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final personalFinance = PersonalFinancePanel(
                panelKey: sectionKeys['finance'],
                state: state,
                busy: busy,
                personalFinanceData: personalFinanceData,
                action: action,
              );
              final financialOutlook = FinancialOutlookPanel(
                state: state,
                personalFinanceData: personalFinanceData,
              );
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          personalFinance,
                          const SizedBox(height: 34),
                          financialOutlook
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  personalFinance,
                  const SizedBox(height: 34),
                  financialOutlook,
                ],
              );
            },
          ),
        ];
      case 'command':
      default:
        final playerObjectives = PlayerObjective.synthesizeFromState(state);
        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = ExecutiveCommandSummary(
                state: state,
                businessFinancials: businessFinancials,
                contracts: contracts,
                onNavigate: onNavigate,
                onExecuteDecision: (item) {
                  if (onNavigate != null) {
                    onNavigate!(item.targetSection);
                  }
                },
              );
              final objectives = ObjectivesPanel(
                objectives: playerObjectives,
                onNavigate: onNavigate,
              );
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          QuickActionsPanel(
                              state: state, onNavigate: onNavigate),
                          const SizedBox(height: 28),
                          summary,
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          objectives,
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QuickActionsPanel(state: state, onNavigate: onNavigate),
                  const SizedBox(height: 28),
                  summary,
                  const SizedBox(height: 34),
                  objectives,
                ],
              );
            },
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
  final VoidCallback? onTap;

  const EarthFlowMetric({
    super.key,
    this.width,
    required this.icon,
    required this.label,
    required this.accent,
    required this.inflow,
    required this.outflow,
    required this.net,
    this.onTap,
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                              color: mutedColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: badgeTextColor.withValues(alpha: .3)),
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
      ),
    );
  }
}
