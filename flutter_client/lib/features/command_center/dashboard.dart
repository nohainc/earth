import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../governance/governance_panels.dart';
import '../institutions/institutions_panels.dart';
import '../lifecycle/lifecycle_panels.dart';
import '../market/market_panels.dart';
import '../operations/ai_panel.dart';
import '../operations/business_panel.dart';
import '../operations/machines_panel.dart';
import '../operations/technology_panel.dart';
import 'hero_card.dart';
import 'opportunity_panel.dart';

String dashboardSectionTitle(String section) => switch (section) {
      'market' => 'CENTRAL MARKET',
      'business' => 'BUSINESS',
      'civic' => 'CIVIC LIFE',
      'city' => 'CITY',
      'technology' => 'TECHNOLOGY',
      'life' => 'LIFE & LEGACY',
      'contracts' => 'CONTRACTS',
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
  final List<dynamic> membershipEvents;
  final List<dynamic> authorityEvents;
  final List<dynamic> productionCatalog;
  final int unreadNotifications;
  final Map<String, GlobalKey> sectionKeys;
  final String selectedSection;
  final Future<void> Function(Future<EarthState> Function()) action;

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
    required this.unreadNotifications,
    required this.sectionKeys,
    this.selectedSection = 'command',
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final resourceText = state.resources.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSection == 'command') ...[
        HeroCard(key: sectionKeys['command'], state: state),
        const SizedBox(height: 16),
        Text(
          'The world is moving.',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: inkColor,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'DAY ${state.clock['day']}  ·  ${state.institutions['city']['name']}  ·  ${state.institutions['corporation']['name']}',
          style: const TextStyle(color: mutedColor, fontSize: 11, letterSpacing: .7),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            EarthMetric(
              label: 'CREDITS',
              value: '${state.human['credits']} C',
              accent: violetColor,
            ),
            EarthMetric(
              label: 'STANDING',
              value: '${state.human['standing']}',
              accent: Colors.teal,
            ),
            EarthMetric(
              label: 'LEGACY',
              value: '${state.human['legacy']}',
              accent: Colors.indigo,
            ),
            EarthMetric(
              label: 'WORLD HEALTH',
              value: '${state.world['health']} / 100',
              accent: Colors.orange,
            ),
          ],
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESOURCE RESERVES   $resourceText',
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: .8,
                    color: mutedColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'STARTER ECONOMY   living-cost ${state.world['livingCostIndex'] ?? '—'}  ·  productive ${state.world['economicStartIndex'] ?? '—'}',
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: .6,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        ],
        if (selectedSection != 'command') ...[
          Text(
            dashboardSectionTitle(selectedSection),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: inkColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'DAY ${state.clock['day']}  ·  ${state.institutions['city']['name']}  ·  ${state.institutions['corporation']['name']}',
            style: const TextStyle(
              color: mutedColor,
              fontSize: 11,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 20),
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
        ];
      case 'contracts':
        return [
          NegotiatedContractsPanel(
            state: state,
            busy: busy,
            action: action,
          ),
          AuthorityHistoryPanel(authorityEvents: authorityEvents),
        ];
      case 'command':
      default:
        return [
          OpportunityPanel(opportunities: state.opportunities),
          WorldFeedPanel(events: events),
          NotificationsPanel(
            notifications: notifications,
            unreadNotifications: unreadNotifications,
            busy: busy,
            action: action,
            state: state,
          ),
          OwnershipTimelinePanel(ownershipEvents: ownershipEvents),
          WorldIntegrityPanel(state: state),
          HistoryArchivePanel(state: state),
          LedgerPanel(state: state),
        ];
    }
  }

}
