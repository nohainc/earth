import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/command_overview.dart';
import '../../core/models/decision_queue_item.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/design_system/design_system.dart';
import '../finance/personal_finance_panel.dart';
import '../governance/governance_panels.dart';
import '../institutions/institutions_panels.dart';
import '../institutions/organization_directory_panel.dart';
import '../lifecycle/lifecycle_panels.dart' hide WorldRankingsPanel;
import '../market/market_panels.dart';
import '../operations/technology_panel.dart';
import '../operations/buildings_hub_screen.dart';
import '../communications/news_panel.dart';
import '../account/account_screen.dart';
import '../activity/activity_panel.dart';
import 'hero_card.dart';
import '../house/house_tree_dialog.dart';
import '../finance/net_worth_analytics_dialog.dart';
import 'daily_summary_dialog.dart';
import '../../core/api/earth_api.dart';
import '../communications/comm_link_dialog.dart';
import '../lifecycle/historical_archive_panel.dart';
import '../governance/constitution_panel.dart';
import 'command_executive_quadrant.dart';
import 'decision_queue_panel.dart';
import 'last_completed_day_strip.dart';
import '../world/world_conditions_panel.dart';
import '../../core/navigation_registry.dart';
import '../world/initiatives_panel.dart';
import '../institutions/mutual_credit_panel.dart';
import '../house/house_policy_panel.dart';

String dashboardSectionTitle(String section, [EarthState? state]) =>
    NavigationRegistry.pageTitle(section, state);

class Dashboard extends StatelessWidget {
  final EarthState state;
  final CommandOverview? commandOverview;
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
  final List<dynamic> news;
  final bool newsHasMore;
  final VoidCallback? onLoadEarlierNews;
  final List<dynamic> notifications;
  final List<dynamic> decisionQueue;
  final List<dynamic> ownershipEvents;
  final List<dynamic> membershipEvents;
  final Map<String, dynamic> marketHistory;
  final Map<String, dynamic> pantheon;
  final Map<String, dynamic> personalFinanceData;
  final Map<String, dynamic> mutualCreditData;
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
    this.commandOverview,
    this.businessOwnership,
    this.businessFinancials,
    this.businessProfile,
    required this.busy,
    required this.events,
    this.news = const [],
    this.newsHasMore = false,
    this.onLoadEarlierNews,
    required this.notifications,
    this.decisionQueue = const [],
    required this.ownershipEvents,
    required this.membershipEvents,
    this.marketHistory = const {},
    this.pantheon = const {},
    this.personalFinanceData = const {},
    this.mutualCreditData = const {},
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectedSection == 'command') ...[
          HeroCard(
            key: sectionKeys['command'],
            state: state,
            onNavigate: onNavigate,
          ),
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
            onPressed: onNavigate == null || !decision.viewerCanAct
                ? null
                : () => onNavigate!.call(decision.targetRoute),
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
          DailySummaryDialog(
            api: const EarthApi(),
            isPageMode: true,
            onNavigate: onNavigate ?? (_) {},
          ),
        ];
      case String s when s == 'messages' || s.startsWith('messages:'):
        final initialChannelId =
            s.contains(':') ? s.substring(s.indexOf(':') + 1) : null;
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
        return [
          V5GovernancePanel(
            state: state,
            busy: busy,
            action: action,
          ),
          const SizedBox(height: 24),
          RulesInForcePanel(state: state),
        ];
      case 'corporation':
      case 'my-corporation':
        return [
          CorporationOverviewPanel(
            state: state,
            busy: busy,
            action: action,
          ),
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
      case 'organizations':
        return [
          OrganizationDirectoryPanel(
            state: state,
            busy: busy,
            action: action,
          ),
        ];
      case 'territories':
      case 'territory':
      case 'city':
      case 'territory-commons':
        // Territory remains a contextual attribute, not a standalone player
        // system. Legacy routes land on the canonical world context screen.
        return [WorldConditionsPanel(state: state)];
      case 'contracts':
        return [
          OrganizationContractsPanel(
            organizationId: state.membership?['corporation_id']?.toString() ??
                state.membership?['organization_id']?.toString() ??
                '',
            api: const EarthApi(),
            onRefresh: () => action(() => const EarthApi().world()),
          )
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
          CommunitiesPanel(
            state: state,
            busy: busy,
            action: action,
            onNavigate: onNavigate,
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
              return technology;
            },
          ),
        ];
      case 'public-finance':
        return [RulesInForcePanel(state: state)];
      case 'civic-rankings':
        return [WorldRankingsPanel(state: state)];
      case 'history':
      case 'pantheon':
      case 'memorial':
        return [HistoricalArchivePanel(pantheon: pantheon, events: events)];
      case 'world':
      case 'conditions':
        return [WorldConditionsPanel(state: state)];
      case 'initiatives':
        return [
          InitiativesPanel(
            state: state,
            personalFinanceData: personalFinanceData,
            busy: busy,
            action: action,
            initialTabIndex: 0,
          ),
        ];
      case 'programs':
        return [
          InitiativesPanel(
            state: state,
            personalFinanceData: personalFinanceData,
            busy: busy,
            action: action,
            initialTabIndex: 0,
          ),
        ];
      case 'public-projects':
        return [
          InitiativesPanel(
            state: state,
            personalFinanceData: personalFinanceData,
            busy: busy,
            action: action,
            initialTabIndex: 1,
          ),
        ];
      case 'mutual-credit':
        return [MutualCreditPanel(data: mutualCreditData)];
      case 'news':
        return [
          NewsPanel(
              news: news,
              hasMore: newsHasMore,
              onLoadEarlier: onLoadEarlierNews,
              onNavigate: onNavigate,
              events: events,
              notifications: notifications,
              onRefresh: onRefreshEvents)
        ];
      case 'constitution':
        return [
          ConstitutionPanel(
            state: state,
            canonicalLoader: () => const EarthApi().getV5Constitution(
              corporationId: state.membership?['corporation_id']?.toString(),
            ),
            onPreviewAmendment: (changes) =>
                const EarthApi().previewV5ConstitutionAmendment(
              corporationId: state.membership?['corporation_id']?.toString(),
              changes: changes,
            ),
            onProposeAmendment: (changes) async {
              final corporationId =
                  state.membership?['corporation_id']?.toString();
              final preview =
                  await const EarthApi().previewV5ConstitutionAmendment(
                corporationId: corporationId,
                changes: changes,
              );
              if (preview['ok'] == false) return preview;
              final previewGameDay =
                  int.tryParse(preview['gameDay']?.toString() ?? '');
              if (previewGameDay == null || previewGameDay < 1) {
                return {
                  'ok': false,
                  'error': 'Canonical Constitution game day is unavailable.',
                };
              }
              return const EarthApi().proposeV5ConstitutionAmendment(
                subjectType: corporationId == null ? 'EARTH' : 'CORPORATION',
                subjectId: corporationId,
                title: 'Constitution amendment proposal',
                body:
                    'Typed Constitution amendment submitted from the canonical policy editor.',
                changes: changes,
                effectiveFromGameDay: previewGameDay + 1,
              );
            },
          ),
        ];
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
            life['vitality']);
        final energy = asDouble(human['energy'] ??
            human['stamina'] ??
            life['energy'] ??
            life['stamina']);
        final age =
            asInt(human['age_years'] ?? human['age'] ?? life['ageYears']);
        final houseName =
            (life['houseName'] ?? life['house_name'] ?? human['house_name'])
                ?.toString();

        return [
          LayoutBuilder(
            builder: (context, constraints) {
              final lifeToday = LifeTodayPanel(
                state: state,
                busy: busy,
                action: action,
                onNavigate: onNavigate,
              );
              final rawStatus =
                  (life['status'] ?? human['life_status'] ?? 'ACTIVE')
                      .toString()
                      .toUpperCase();
              final status = rawStatus == 'DECEASED'
                  ? 'DECEASED'
                  : rawStatus == 'ESTATE'
                      ? 'ESTATE TRANSITION'
                      : health != null && health < 40
                          ? 'CRITICAL'
                          : health != null && health < 70
                              ? 'LOW VITALITY'
                              : 'ACTIVE';

              final cockpit = EarthPageCockpit(
                status: status,
                statusColor: status == 'CRITICAL'
                    ? context.warningColor
                    : context.successColor,
                infoTitle: 'CURRENT HUMAN',
                infoDescription:
                    'Your current living Human: identity, condition, residence, affiliations, and civic standing. House succession and inherited assets are managed from the House page.',
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
                                      style: context.topicTitleStyle.copyWith(
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
                                          style: context.controlStyle.copyWith(
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
                                              await action(() =>
                                                  const EarthApi()
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
                subtitle: houseName == null
                    ? 'Current Human'
                    : 'Current Human · House of $houseName',
                metrics: [
                  CockpitMetric(
                    label: 'Vitality',
                    value:
                        health == null ? '—' : '${health.toStringAsFixed(0)}%',
                    icon: Icons.favorite_outline,
                    color: health != null && health < 40
                        ? context.warningColor
                        : context.successColor,
                  ),
                  CockpitMetric(
                    label: 'Energy',
                    value:
                        energy == null ? '—' : '${energy.toStringAsFixed(0)}%',
                    icon: Icons.bolt_outlined,
                    color: context.primaryColor,
                  ),
                  CockpitMetric(
                    label: 'Age',
                    value: age == null ? '—' : '$age',
                    icon: Icons.hourglass_empty_outlined,
                    color: context.goldColor,
                  ),
                  CockpitMetric(
                    label: 'Civic standing',
                    value: formatWholeNumber(
                        asIntOr(human['standing'], 0).toDouble()),
                    icon: Icons.verified_user_outlined,
                    color: context.secondaryColor,
                  ),
                ],
              );

              final content = lifeToday;

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
      case 'policies':
      case 'automation':
        return [
          HousePolicyPanel(state: state, busy: busy, action: action),
        ];
      case 'command':
      default:
        final items = decisionQueue
            .whereType<Map>()
            .map((item) =>
                DecisionQueueItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        return [
          CommandExecutiveQuadrant(
            overview: commandOverview,
            houseAssets: state.houseBuildingAssets,
            onNavigate: onNavigate,
          ),
          const SizedBox(height: 24),
          DecisionQueuePanel(
            items: items,
            onNavigate: onNavigate,
          ),
          const SizedBox(height: 24),
          LastCompletedDayStrip(onNavigate: onNavigate),
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
