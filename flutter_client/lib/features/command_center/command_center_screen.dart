import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../auth/security_dialog.dart';
import '../communications/comm_link_dialog.dart';
import '../map/planetary_map_dialog.dart';
import '../dynasty/dynasty_tree_dialog.dart';
import '../market/derivatives_dialog.dart';
import '../finance/net_worth_analytics_dialog.dart';
import '../onboarding/onboarding_guidance_bar.dart';
import 'daily_briefing_dialog.dart';
import '../../core/onboarding_controller.dart';
import '../../core/navigation_deep_link.dart';
import 'dashboard.dart';
import 'sidebar.dart';
import 'top_fixed_hud_panel.dart';
import '../../core/models/live_connection_status.dart';

Uri? liveEventsUri({required String configuredBase, required Uri pageUri}) {
  final base = configuredBase.isNotEmpty
      ? configuredBase
      : (pageUri.scheme == 'http' || pageUri.scheme == 'https'
          ? pageUri.origin
          : '');
  if (!base.startsWith('http')) return null;
  return Uri.parse('${base.replaceFirst(RegExp(r'^http'), 'ws')}/edge/events');
}

class CommandCenter extends StatefulWidget {
  final VoidCallback onLogout;
  const CommandCenter({super.key, required this.onLogout});

  @override
  State<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<CommandCenter> {
  final api = const EarthApi();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sectionKeys = <String, GlobalKey>{
    'command': GlobalKey(),
    'market': GlobalKey(),
    'business': GlobalKey(),
    'civic': GlobalKey(),
    'city': GlobalKey(),
    'technology': GlobalKey(),
    'life': GlobalKey(),
    'finance': GlobalKey(),
    'contracts': GlobalKey(),
    'activity': GlobalKey(),
  };
  EarthState? state;
  String? error;
  bool busy = false;
  List<dynamic> events = const [];
  List<dynamic> notifications = const [];
  List<dynamic> ownershipEvents = const [];
  List<dynamic> membershipEvents = const [];
  List<dynamic> authorityEvents = const [];
  Map<String, dynamic> businessOwnership = const {};
  Map<String, dynamic> businessFinancials = const {};
  Map<String, dynamic> businessProfile = const {};
  List<dynamic> productionCatalog = const [];
  Map<String, dynamic> marketHistory = const {};
  Map<String, dynamic> pantheon = const {};
  Map<String, dynamic> personalFinanceData = const {};
  List<dynamic> contractsList = const [];
  int unreadNotifications = 0;
  int unreadCommMessages = 0;
  String selectedSection = 'command';
  LiveConnectionStatus connectionStatus = LiveConnectionStatus.reconnecting;
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  Timer? pollingFallbackTimer;
  WebSocketChannel? liveChannel;
  int _wsFailCount = 0;
  final Set<String> _seenEventKeys = <String>{};
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initialSec = NavigationDeepLink.getInitialSection();
    if (initialSec != null && initialSec.isNotEmpty) {
      selectedSection = initialSec;
    }
    NavigationDeepLink.listen((sec) {
      if (mounted && sec.isNotEmpty && sec != selectedSection) {
        _navigateToSection(context, sec, closeDrawer: false, updateUrl: false);
      }
    });
    _run(api.world);
    _loadProductionCatalog();
    _refreshEvents();
    _connectLiveChannel();
    eventTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshEvents());
  }

  Future<void> _loadProductionCatalog() async {
    try {
      final catalog = await api.productionCatalog();
      if (mounted) setState(() => productionCatalog = catalog);
    } catch (_) {
      // The dashboard remains usable if the public catalog is temporarily unavailable.
    }
  }

  bool handleLiveMessage(dynamic rawMessage) {
    if (rawMessage == null) return false;
    try {
      final decoded =
          rawMessage is String ? jsonDecode(rawMessage) : rawMessage;
      if (decoded is Map<String, dynamic>) {
        final key = (decoded['eventKey'] ?? decoded['id'] ?? decoded['eventId'])
            ?.toString();
        if (key != null && key.isNotEmpty) {
          if (_seenEventKeys.contains(key)) {
            return false; // Duplicate delivery: ignore without duplicating state
          }
          if (_seenEventKeys.length > 500) _seenEventKeys.clear();
          _seenEventKeys.add(key);
        }
        final type = decoded['type']?.toString();
        final topic = decoded['topic']?.toString();
        if (type == 'world_day_started' ||
            type == 'world_tick' ||
            topic == 'world_activity' ||
            topic == 'market') {
          _run(api.world);
        }
      }
    } catch (_) {}
    if (mounted) _refreshEvents();
    return true;
  }

  void _connectLiveChannel() {
    final uri = liveEventsUri(configuredBase: api.baseUrl, pageUri: Uri.base);
    if (uri == null) {
      _startPollingFallback();
      return;
    }
    try {
      liveChannel = WebSocketChannel.connect(uri);
      _refreshEvents();
      liveChannel!.stream.listen((message) {
        _wsFailCount = 0;
        _stopPollingFallback();
        if (mounted && connectionStatus != LiveConnectionStatus.live) {
          setState(() => connectionStatus = LiveConnectionStatus.live);
        }
        handleLiveMessage(message);
      }, onError: (_) {
        liveChannel = null;
        _onWebSocketDisconnected();
      }, onDone: () {
        liveChannel = null;
        _onWebSocketDisconnected();
      });
    } catch (_) {
      liveChannel = null;
      _onWebSocketDisconnected();
    }
  }

  void _onWebSocketDisconnected() {
    _wsFailCount++;
    if (_wsFailCount >= 2) {
      _startPollingFallback();
    } else {
      if (mounted) {
        setState(() => connectionStatus = LiveConnectionStatus.reconnecting);
      }
      _scheduleLiveReconnect(const Duration(seconds: 5));
    }
  }

  void _startPollingFallback() {
    if (mounted && connectionStatus != LiveConnectionStatus.polling) {
      setState(() => connectionStatus = LiveConnectionStatus.polling);
    }
    pollingFallbackTimer?.cancel();
    // Poll every 8 seconds when WebSockets are unavailable
    pollingFallbackTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _pollFallbackSync();
    });
    // And try to reconnect WebSocket in the background every 30 seconds
    _scheduleLiveReconnect(const Duration(seconds: 30));
  }

  void _stopPollingFallback() {
    pollingFallbackTimer?.cancel();
    pollingFallbackTimer = null;
  }

  Future<void> _pollFallbackSync() async {
    try {
      await _refreshEvents();
      if (mounted && connectionStatus == LiveConnectionStatus.offline) {
        setState(() => connectionStatus = LiveConnectionStatus.polling);
      }
    } catch (_) {
      if (mounted) {
        setState(() => connectionStatus = LiveConnectionStatus.offline);
      }
    }
  }

  void _scheduleLiveReconnect([Duration delay = const Duration(seconds: 10)]) {
    if (!mounted || liveReconnectTimer?.isActive == true) return;
    liveReconnectTimer = Timer(delay, () {
      liveReconnectTimer = null;
      if (mounted && liveChannel == null) _connectLiveChannel();
    });
  }

  Future<void> _refreshEvents() async {
    try {
      final latest = await api.events();
      final notificationData = await api.notifications();
      final ownership = await api.ownershipEvents();
      final memberships = await api.membershipEvents();
      final authority = await api.authorityEvents();
      Map<String, dynamic> finData = personalFinanceData;
      List<dynamic> cList = contractsList;
      int commUnread = unreadCommMessages;
      try {
        finData = await api.personalFinance();
      } catch (_) {}
      try {
        cList = await api.contracts();
      } catch (_) {}
      try {
        final commMetricsData = await api.commMetrics();
        commUnread = asInt(commMetricsData['unreadDispatches']) ?? 0;
      } catch (_) {}
      if (mounted) {
        setState(() {
          events = latest;
          ownershipEvents = ownership;
          membershipEvents = memberships;
          authorityEvents = authority;
          personalFinanceData = finData;
          contractsList = cList;
          unreadCommMessages = commUnread;
          notifications =
              (notificationData['notifications'] as List<dynamic>?) ?? const [];
          unreadNotifications = asInt(notificationData['unread']) ??
              asInt(notificationData['unreadCount']) ??
              0;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = liveChannel != null
                ? LiveConnectionStatus.live
                : LiveConnectionStatus.polling;
          }
        });
      }
    } catch (_) {
      // If requests fail completely, transition to offline state
      if (mounted && connectionStatus != LiveConnectionStatus.reconnecting) {
        setState(() => connectionStatus = LiveConnectionStatus.offline);
      }
    }
  }

  Future<void> _run(Future<EarthState> Function() action) async {
    final requestGeneration = ++_requestGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await action();
      Map<String, dynamic> ownership = const {};
      Map<String, dynamic> financials = const {};
      Map<String, dynamic> profile = const {};
      final history = <String, dynamic>{};
      Map<String, dynamic> achievementData = const {};
      final businessId = value.business['id'] as String?;
      if (businessId != null && businessId.isNotEmpty) {
        try {
          profile = await api.businessProfile(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
        try {
          ownership = await api.businessOwnership(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
        try {
          financials = await api.businessFinancials(businessId);
        } catch (_) {/* Keep the canonical world snapshot usable. */}
      }
      await Future.wait(value.market.keys.map((product) async {
        try {
          history[product] = await api.marketPriceHistory(product);
        } catch (_) {
          // Analytics are optional; live market data remains authoritative.
        }
      }));
      try {
        achievementData = await api.pantheon();
      } catch (_) {
        // Historical achievements are optional and must not block the world snapshot.
      }
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() {
          state = value;
          businessProfile = profile;
          businessOwnership = ownership;
          businessFinancials = financials;
          marketHistory = history;
          pantheon = achievementData;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = liveChannel != null
                ? LiveConnectionStatus.live
                : LiveConnectionStatus.polling;
          }
        });
      }
      await _refreshEvents();
    } catch (exception) {
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() {
          error = exception.toString().replaceFirst('Exception: ', '');
          connectionStatus = LiveConnectionStatus.offline;
        });
      }
    } finally {
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    eventTimer?.cancel();
    liveReconnectTimer?.cancel();
    pollingFallbackTimer?.cancel();
    liveChannel?.sink.close();
    super.dispose();
  }

  void _navigateToSection(BuildContext context, String section,
      {required bool closeDrawer, bool updateUrl = true}) {
    if (closeDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    if (section == 'command') {
      OnboardingController.instance.completeStep('world_status');
    } else if (section == 'net_worth' || section == 'finance') {
      OnboardingController.instance.completeStep('personal_resources');
    } else if (section == 'city' || section == 'civic') {
      OnboardingController.instance.completeStep('join_community');
    } else if (section == 'market' || section == 'derivatives') {
      OnboardingController.instance.completeStep('first_market_decision');
    } else if (section == 'business' || section == 'technology') {
      OnboardingController.instance.completeStep('start_enterprise');
    } else if (section == 'activity' || section == 'comm') {
      OnboardingController.instance.completeStep('receive_consequence');
    }

    if (section == 'briefing') {
      showDailyBriefingDialog(
        context,
        api: api,
        onNavigate: (sec) => _navigateToSection(context, sec, closeDrawer: false),
      );
      return;
    }

    if (updateUrl) {
      NavigationDeepLink.updateSection(section);
    }
    if (mounted) {
      setState(() => selectedSection = section);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state;
    final canAdvanceDay = current != null;

    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxWidth < 800;
      return Scaffold(
        key: _scaffoldKey,
        drawer: current != null && compact
            ? Drawer(
                backgroundColor: canvasColor,
                child: SafeArea(
                  child: Sidebar(
                    state: current,
                    selectedSection: selectedSection,
                    busy: busy,
                    canAdvanceDay: canAdvanceDay,
                    onAdvanceDay: () => _run(api.advanceDay),
                    onLogout: () async {
                      await api.logout();
                      if (mounted) widget.onLogout();
                    },
                    onSecurity: () =>
                        showSecurityDialog(context, api, widget.onLogout),
                    onNavigate: (section) => _navigateToSection(
                      context,
                      section,
                      closeDrawer: true,
                    ),
                  ),
                ),
              )
            : null,
        body: current == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : EarthErrorState(
                        message: error!,
                        retry: () => _run(api.world),
                      ),
              )
            : RefreshIndicator(
                onRefresh: () async => _run(api.world),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [canvasColor, Color(0xff171936), canvasColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      TopFixedHudPanel(
                        state: current,
                        unreadNotifications: unreadNotifications,
                        unreadCommMessages: unreadCommMessages,
                        isLiveConnected: liveChannel != null,
                        isReconnecting: liveReconnectTimer?.isActive == true,
                        connectionStatus: connectionStatus,
                        showDrawerButton: compact,
                        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                        onNavigate: (section) => _navigateToSection(
                          context,
                          section,
                          closeDrawer: false,
                        ),
                        onLogout: () async {
                          await api.logout();
                          if (mounted) widget.onLogout();
                        },
                        onSecurity: () =>
                            showSecurityDialog(context, api, widget.onLogout),
                        onCommLink: () => showCommLinkDialog(context,
                            api: api, state: current),
                        onMapTap: () => _navigateToSection(context, 'map',
                            closeDrawer: false),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            if (!compact)
                              Sidebar(
                                state: current,
                                selectedSection: selectedSection,
                                busy: busy,
                                canAdvanceDay: canAdvanceDay,
                                onAdvanceDay: () => _run(api.advanceDay),
                                onLogout: () async {
                                  await api.logout();
                                  if (mounted) widget.onLogout();
                                },
                                onSecurity: () =>
                                    showSecurityDialog(context, api, widget.onLogout),
                                onNavigate: (section) => _navigateToSection(
                                  context,
                                  section,
                                  closeDrawer: false,
                                ),
                              ),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.fromLTRB(
                                  compact ? 16 : 28,
                                  compact ? 14 : 22,
                                  compact ? 16 : 36,
                                  56,
                                ),
                                children: [
                                  if (error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: MaterialBanner(
                                        content: Text(error!),
                                        leading: const Icon(Icons.warning_amber),
                                        actions: [
                                          TextButton(
                                            onPressed:
                                                busy ? null : () => _run(api.world),
                                            child: const Text('RETRY'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (connectionStatus == LiveConnectionStatus.polling)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD600).withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFFFD600)),
                                          const SizedBox(width: 10),
                                          const Expanded(
                                            child: Text(
                                              'WebSocket telemetry unavailable — polling mode active (updates every 8s). Simulation data may be slightly delayed.',
                                              style: TextStyle(
                                                color: Color(0xFFFFD600),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            onPressed: () {
                                              _connectLiveChannel();
                                              _run(api.world);
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(0xFFFFD600),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            child: const Text(
                                              'RETRY LIVE STREAM',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (connectionStatus == LiveConnectionStatus.offline)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFFF5252).withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.cloud_off_outlined, size: 16, color: Color(0xFFFF5252)),
                                          const SizedBox(width: 10),
                                          const Expanded(
                                            child: Text(
                                              'Network offline — displaying cached simulation state. Reconnecting automatically...',
                                              style: TextStyle(
                                                color: Color(0xFFFF5252),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          TextButton(
                                            onPressed: () {
                                              _connectLiveChannel();
                                              _run(api.world);
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: const Color(0xFFFF5252),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                            child: const Text(
                                              'RECONNECT NOW',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                   OnboardingGuidanceBar(
                                     onNavigate: (section) => _navigateToSection(
                                       context,
                                       section,
                                       closeDrawer: false,
                                     ),
                                   ),
                                   const SizedBox(height: 8),
                                   ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: compact ? 320 : 860,
                                    ),
                                    child: Dashboard(
                                      state: current,
                                      selectedSection: selectedSection,
                                      onNavigate: (section) => _navigateToSection(
                                        context,
                                        section,
                                        closeDrawer: false,
                                      ),
                                      busy: busy,
                                      events: events,
                                      notifications: notifications,
                                      ownershipEvents: ownershipEvents,
                                      businessOwnership: businessOwnership,
                                      businessFinancials: businessFinancials,
                                      businessProfile: businessProfile,
                                      membershipEvents: membershipEvents,
                                      authorityEvents: authorityEvents,
                                      productionCatalog: productionCatalog,
                                      marketHistory: marketHistory,
                                      pantheon: pantheon,
                                      personalFinanceData: personalFinanceData,
                                      contracts: contractsList,
                                      isLiveConnected: liveChannel != null,
                                      isReconnecting:
                                          liveReconnectTimer?.isActive == true,
                                      connectionStatus: connectionStatus,
                                      unreadNotifications: unreadNotifications,
                                      sectionKeys: _sectionKeys,
                                      action: _run,
                                      onRefreshEvents: _refreshEvents,
                                      onMarkNotificationRead: (id) async {
                                        await api.markNotificationRead(id);
                                        await _refreshEvents();
                                      },
                                      onMarkAllNotificationsRead: () async {
                                        await api.markAllNotificationsRead();
                                        await _refreshEvents();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
    });
  }
}
