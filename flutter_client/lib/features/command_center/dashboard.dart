import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/decision_queue_item.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/design_system/design_system.dart';
import '../finance/personal_finance_panel.dart';
import '../governance/governance_panels.dart';
import '../institutions/institutions_panels.dart';
import '../lifecycle/lifecycle_panels.dart';
import '../market/market_panels.dart';
import '../operations/technology_panel.dart';
import '../operations/buildings_hub_screen.dart';
import '../communications/news_panel.dart';
import '../account/account_screen.dart';
import '../activity/activity_panel.dart';
import 'hero_card.dart';
import 'executive_command_summary.dart';
import 'objectives_panel.dart';
import '../house/house_tree_dialog.dart';
import '../market/derivatives_dialog.dart';
import '../finance/net_worth_analytics_dialog.dart';
import 'daily_briefing_dialog.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/player_objective.dart';
import '../communications/comm_link_dialog.dart';
import '../lifecycle/historical_archive_panel.dart';
import '../governance/constitution_panel.dart';
import 'quick_actions_panel.dart';
import 'command_executive_quadrant.dart';

String dashboardSectionTitle(String section, [EarthState? state]) => switch (section) {
      'account' => 'ACCOUNT SETTINGS',
      'command' => 'COMMAND CENTER',
      'business' => 'BUSINESS',
      'market' => 'MARKET',
      'derivatives' => 'FUTURES & DERIVATIVES',
      'net_worth' => 'NET WORTH ANALYTICS',
      'briefing' => 'EXECUTIVE BRIEFING',
      'messages' => 'MESSAGES',
      String s when s.startsWith('messages:') => 'MESSAGES',
      'notifications' => 'NOTIFICATIONS',
      'buildings' => 'BUILDINGS & URBAN INFRASTRUCTURE',
      'real_estate' => 'BUILDINGS & DISTRICT',
      'civic' => 'PUBLIC',
      'corporations' => 'CORPORATIONS',
      'corporation' => 'CORPORATION',
      'my-corporation' => 'MY CORPORATION',
      'city' => 'MY CITY',
      String s when s.startsWith('my-community') => 'MY COMMUNITY',
      'communities' => 'COMMUNITIES',
      'news' => 'NEWS',
      'house' => 'HOUSE',
      'dynasty' => 'HOUSE',
      'technology' => 'TECHNOLOGY',
      'public-finance' => 'PUBLIC FINANCE',
      'civic-rankings' => 'CIVIC RANKINGS',
      'history' => 'MEMORIAL',
      'memorial' => 'MEMORIAL',
      'life' => () {
        if (state == null) return 'LIFE';
        final raw = (state.human['display_name'] ?? state.human['name'])?.toString().trim();
        if (raw == null || raw.isEmpty) return 'CITIZEN';
        return raw.split(RegExp(r'\s+')).first.toUpperCase();
      }(),
      'pantheon' => 'MEMORIAL',
      'constitution' => 'CONSTITUTION',
      'contracts' => 'CONTRACTS',
      'finance' => 'FINANCE',
      'activity' => 'ACTIVITY & EVENTS',
      _ => 'COMMAND CENTER',
    };

class Dashboard extends StatelessWidget {
  final EarthState state;
  // Retained as ignored constructor inputs so older widget harnesses can be
  // migrated independently; no company data is read or rendered.
  @Deprecated('Company entities were removed; use Human-owned operations.')
  final Map<String, dynamic>? businessOwnership;
  @Deprecated('Company entities were removed; use Human-owned operations.')
  final Map<String, dynamic>? businessFinancials;
  @Deprecated('Company entities were removed; use Human-owned operations.')
  final Map<String, dynamic>? businessProfile;
  final bool busy;
  final List<dynamic> events;
  final List<dynamic> notifications;
  final List<dynamic> ownershipEvents;
  final List<dynamic> membershipEvents;
  final Map<String, dynamic> marketHistory;
  final Map<String, dynamic> pantheon;
  final Map<String, dynamic> personalFinanceData;
  final bool isLiveConnected;
  final bool isReconnecting;
  final LiveConnectionStatus? connectionStatus;
  final int unreadNotifications;
  final Map<String, Key> sectionKeys;
  final String selectedSection;
  final String? previousSection;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function(Future<EarthState> Function()) action;
  final VoidCallback? onRefreshEvents;
  final Future<void> Function(String)? onMarkNotificationRead;
  final Future<void> Function()? onMarkAllNotificationsRead;
  final VoidCallback? onLogout;

  const Dashboard({
    super.key,
    required this.state,
    this.businessOwnership,
    this.businessFinancials,
    this.businessProfile,
    required this.busy,
    required this.events,
    required this.notifications,
    required this.ownershipEvents,
    required this.membershipEvents,
    this.marketHistory = const {},
    this.pantheon = const {},
    this.personalFinanceData = const {},
    this.isLiveConnected = true,
    this.isReconnecting = false,
    this.connectionStatus,
    required this.unreadNotifications,
    this.sectionKeys = const {},
    this.selectedSection = 'command',
    this.previousSection,
    this.onNavigate,
    required this.action,
    this.onRefreshEvents,
    this.onMarkNotificationRead,
    this.onMarkAllNotificationsRead,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final decisions = DecisionQueueItem.synthesizeFromState(state);
    final visibleDecisions = decisions.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSection == 'command') ...[
          HeroCard(
            key: sectionKeys['command'],
            state: state,
            onNavigate: onNavigate,
          ),
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
                    onTap: () => onNavigate?.call('buildings'),
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
      case 'account':
        return [
          AccountScreen(
            state: state,
            api: const EarthApi(),
            onLogout: onLogout,
            onNavigate: onNavigate,
          ),
        ];
      case 'market':
        return [
          MarketWorkspace(
            key: sectionKeys['market'],
            state: state,
            busy: busy,
            priceHistory: marketHistory,
            action: action,
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
      case String s when s == 'messages' || s.startsWith('messages:'):
        final initialChannelId = s.contains(':') ? s.substring(s.indexOf(':') + 1) : null;
        return [
          LayoutBuilder(
            builder: (context, _) {
              final commLink = CommLinkDialog(
                api: const EarthApi(),
                state: state,
                initialChannelId: initialChannelId,
                isPageMode: true,
                onNavigate: onNavigate,
                onClose: () => onNavigate?.call(previousSection ?? 'command'),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  commLink,
                ],
              );
            },
          ),
        ];
      case 'notifications':
        return [
          ActivityPanel(
            panelKey: sectionKeys['notifications'],
            notifications: notifications,
            unreadCount: unreadNotifications,
            isLiveConnected: isLiveConnected,
            isReconnecting: isReconnecting,
            connectionStatus: connectionStatus,
            onRefresh: onRefreshEvents ?? () {},
            onMarkRead: onMarkNotificationRead ?? (_) async {},
            onMarkAllRead: onMarkAllNotificationsRead ?? () async {},
            onClose: () => onNavigate?.call(previousSection ?? 'command'),
          ),
        ];
      case 'house':
      case 'dynasty':
        return [
          HouseTreeDialog(
            api: const EarthApi(),
            state: state,
            isPageMode: true,
            onNavigate: onNavigate,
            onRefresh: () => action(() => const EarthApi().world()),
          ),
        ];
      case 'civic':
      case 'governance':
        if (state.membership?['city_id']?.toString().isNotEmpty != true) {
          return [
            const AffiliationRequiredPanel(
              title: 'PUBLIC GOVERNANCE',
              icon: Icons.public_outlined,
              message:
                  'Public Governance explains the common rules of Earth and how cities are managed. You are currently independent, so city proposals, municipal budgets, and local voting are not available yet. Join a city to participate in its governance.',
            ),
          ];
        }
        return [
          PublicFinanceGovernancePanel(
              state: state, busy: busy, action: action),
          const SizedBox(height: 34),
          ProposalPanel(state: state, busy: busy, action: action),
        ];
      case 'corporation':
      case 'my-corporation':
        final corporationId = state.membership?['corporation_id']?.toString();
        return [
          CorporationOverviewPanel(
            state: state,
            busy: busy,
            action: action,
          ),
          if (corporationId != null && corporationId.isNotEmpty) ...[
            const SizedBox(height: 34),
            ProposalPanel(
              state: state,
              busy: busy,
              action: action,
              institutionId: corporationId,
              scopeLabel: 'CORPORATION',
            ),
          ],
        ];
      case 'corporations':
        return [
          CorporationDirectoryPanel(
            state: state,
            busy: busy,
            action: action,
            isExpandable: true,
            showMemberSummary: false,
            showSelection: false,
          ),
        ];
      case 'city':
        if (state.membership?['city_id']?.toString().isNotEmpty != true) {
          return [
            const AffiliationRequiredPanel(
              title: 'CITY ACCESS',
              icon: Icons.location_city_outlined,
              message:
                  'Independent users cannot form cities directly. Join a corporation to access city formation and create an additional city in its network.',
            ),
          ];
        }
        return [
          LayoutBuilder(
            builder: (context, _) {
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
              final cityImpact = CityImpactPanel(state: state);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  institutions,
                  const SizedBox(height: 34),
                  if (cityId != null && cityId.isNotEmpty)
                    ActiveGovernanceRulePanel(
                        state: state, institutionId: cityId),
                  const SizedBox(height: 34),
                  cityImpact,
                  if (cityProposal != null) ...[
                    const SizedBox(height: 34),
                    cityProposal,
                  ],
                ],
              );
            },
          ),
        ];
      case 'buildings':
      case 'real_estate':
        return [
          BuildingsHubScreen(state: state, busy: busy, action: action),
        ];
      case String s when s.startsWith('my-community'):
        final targetId = s.contains(':') ? s.split(':').last : null;
        return [
          MyCommunityPanel(
            panelKey: sectionKeys[s] ?? sectionKeys['my-community'],
            communityId: targetId,
            state: state,
            busy: busy,
            action: action,
            onNavigate: onNavigate,
          ),
        ];
      case 'communities':
        return [
          CommunitiesPanel(state: state, busy: busy, action: action),
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
              return technology;
            },
          ),
        ];
      case 'public-finance':
        return [
          PublicFinanceGovernancePanel(state: state, busy: busy, action: action)
        ];
      case 'civic-rankings':
        return [CivicRankingsPanel(state: state)];
      case 'history':
      case 'pantheon':
        return [HistoricalArchivePanel(pantheon: pantheon, events: events)];
      case 'news':
        return [NewsPanel(events: events, notifications: notifications, onRefresh: onRefreshEvents)];
      case 'constitution':
        return [ConstitutionPanel(state: state)];
      case 'life':
        final human = state.human;
        final life = state.life;
        final rawFullName =
            (human['display_name'] ?? human['name'] ?? 'CITIZEN')
                .toString()
                .trim();
        final health = asDouble(human['health'] ??
                human['vitality'] ??
                life['health'] ??
                life['vitality']) ??
            100.0;
        final energy = asDouble(human['energy'] ??
                human['stamina'] ??
                life['energy'] ??
                life['stamina']) ??
            100.0;
        final age =
            asInt(human['age_years'] ?? human['age'] ?? life['ageYears']) ?? 31;
        final houseName = (life['houseName'] ??
                life['house_name'] ??
                human['house_name'] ??
                'Founding Lineage')
            .toString();
        final generation =
            asIntOr(life['generation'] ?? human['generation'], 1);

        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final succession = SuccessionPanel(
                state: state,
                busy: busy,
                action: action,
              );
              final lifeToday =
                  LifeTodayPanel(state: state, busy: busy, action: action);

              final epitaph = (human['epitaph'] ??
                      life['epitaph'] ??
                      'Pioneered civilization across the frontier of Earth.')
                  .toString()
                  .trim();

              final cockpit = EarthPageCockpit(
                status: health < 40 ? 'CRITICAL VITALITY' : 'ACTIVE CITIZEN',
                statusColor:
                    health < 40 ? context.warningColor : context.successColor,
                infoTitle: 'CITIZEN BIOMETRICS & SUCCESSION ARCHITECTURE',
                infoDescription:
                    '• Vitality & Daily Energy: Physical health (100% base) and daily operational capacity for actions, work, and planetary decisions.\n\n• Dynastic Lineage: House heritage, generational continuity, and ancestral standing on Earth.\n\n• Estate Succession: Testamentary allocation, heirs, and asset preservation across generations.',
                title: rawFullName.toUpperCase(),
                titleWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        rawFullName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: context.inkColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Edit name',
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: context.primaryColor,
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              final initialName = rawFullName.contains(' ')
                                  ? rawFullName.split(' ').first
                                  : rawFullName;
                              final controller =
                                  TextEditingController(text: initialName);
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: context.panelColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        context.radiusPanel),
                                    side: BorderSide(
                                        color: context.primaryColor
                                            .withValues(alpha: .35)),
                                  ),
                                  title: Text('Edit name',
                                      style: context.topicTitleStyle
                                          .copyWith(
                                              color: context.primaryColor)),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    maxLength: 80,
                                    style: context.bodyStyle
                                        .copyWith(color: context.inkColor),
                                    decoration: InputDecoration(
                                      labelText: 'Name',
                                      labelStyle: context.widgetFooterStyle,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: Text('CANCEL',
                                          style: context.controlStyle
                                              .copyWith(
                                                  color: context.mutedColor)),
                                    ),
                                    EarthButton(
                                      label: 'SAVE',
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              final name =
                                                  controller.text.trim();
                                              if (name.length < 2) return;
                                              Navigator.pop(dialogContext);
                                              await action(
                                                  () => const EarthApi()
                                                      .updateDisplayName(name));
                                            },
                                    ),
                                  ],
                                ),
                              );
                              controller.dispose();
                            },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                subtitleWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        epitaph,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.mutedColor,
                          fontSize: 12,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                          height: 1.35,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Edit epitaph / motto',
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: context.primaryColor,
                      ),
                      onPressed: busy
                          ? null
                          : () async {
                              final controller =
                                  TextEditingController(text: epitaph);
                              await showDialog<void>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: context.panelColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        context.radiusPanel),
                                    side: BorderSide(
                                        color: context.primaryColor
                                            .withValues(alpha: .35)),
                                  ),
                                  title: Text('Edit citizen epitaph',
                                      style: context.topicTitleStyle
                                          .copyWith(
                                              color: context.primaryColor)),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    maxLength: 160,
                                    maxLines: 2,
                                    style: context.bodyStyle
                                        .copyWith(color: context.inkColor),
                                    decoration: InputDecoration(
                                      labelText:
                                          'Epitaph / Memorial Inscription',
                                      labelStyle: context.widgetFooterStyle,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: Text('CANCEL',
                                          style: context.controlStyle
                                              .copyWith(
                                                  color: context.mutedColor)),
                                    ),
                                    EarthButton(
                                      label: 'SAVE',
                                      onPressed: busy
                                          ? null
                                          : () async {
                                              final text =
                                                  controller.text.trim();
                                              if (text.isEmpty) return;
                                              Navigator.pop(dialogContext);
                                              await action(
                                                  () => const EarthApi()
                                                      .updateEpitaph(text));
                                            },
                                    ),
                                  ],
                                ),
                              );
                              controller.dispose();
                            },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                metrics: [
                  CockpitMetric(
                    label: 'Vitality',
                    value: '${health.toStringAsFixed(0)}%',
                    icon: Icons.favorite_outline,
                    color: health < 40
                        ? context.warningColor
                        : context.successColor,
                  ),
                  CockpitMetric(
                    label: 'Energy',
                    value: '${energy.toStringAsFixed(0)}%',
                    icon: Icons.bolt_outlined,
                    color: context.primaryColor,
                  ),
                  CockpitMetric(
                    label: 'Age',
                    value: '$age',
                    icon: Icons.hourglass_empty_outlined,
                    color: context.goldColor,
                  ),
                  CockpitMetric(
                    label: 'Generation',
                    value: '$generation',
                    icon: Icons.account_balance_outlined,
                    color: context.secondaryColor,
                  ),
                ],
              );

              final content = constraints.maxWidth > 1000
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: lifeToday),
                        const SizedBox(width: 40),
                        Expanded(child: succession),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        lifeToday,
                        const SizedBox(height: 34),
                        succession,
                      ],
                    );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cockpit,
                  const SizedBox(height: 28),
                  content,
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
              if (constraints.maxWidth > 1000) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          personalFinance,
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
              final quadrant = CommandExecutiveQuadrant(
                state: state,
                onNavigate: onNavigate,
              );
              final summary = ExecutiveCommandSummary(
                state: state,
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
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quadrant,
                    const SizedBox(height: 28),
                    Row(
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
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  quadrant,
                  const SizedBox(height: 28),
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
                            style: const TextStyle(
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
