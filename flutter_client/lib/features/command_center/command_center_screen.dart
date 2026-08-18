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
import 'dashboard.dart';
import 'sidebar.dart';
import 'top_fixed_hud_panel.dart';

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
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  WebSocketChannel? liveChannel;
  final Set<String> _seenEventKeys = <String>{};
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
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
    if (uri == null) return;
    try {
      liveChannel = WebSocketChannel.connect(uri);
      _refreshEvents();
      liveChannel!.stream.listen((message) {
        handleLiveMessage(message);
      }, onError: (_) {
        liveChannel = null;
        _scheduleLiveReconnect();
      }, onDone: () {
        liveChannel = null;
        _scheduleLiveReconnect();
      });
    } catch (_) {
      liveChannel = null;
    }
  }

  void _scheduleLiveReconnect() {
    if (!mounted || liveReconnectTimer?.isActive == true) return;
    liveReconnectTimer = Timer(const Duration(seconds: 10), () {
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
        });
      }
    } catch (_) {
      // The world snapshot remains usable if the optional live feed is temporarily unavailable.
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
        });
      }
      await _refreshEvents();
    } catch (exception) {
      if (mounted && requestGeneration == _requestGeneration) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
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
    liveChannel?.sink.close();
    super.dispose();
  }

  void _navigateToSection(BuildContext context, String section,
      {required bool closeDrawer}) {
    if (closeDrawer) Navigator.of(context).pop();
    if (section == 'map') {
      showPlanetaryMapDialog(context, api: api, state: state);
      return;
    }
    if (section == 'dynasty') {
      showDynastyTreeDialog(context, api: api, state: state);
      return;
    }
    if (section == 'derivatives') {
      showDerivativesDialog(context, api: api, state: state);
      return;
    }
    if (mounted) setState(() => selectedSection = section);
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
                        onMapTap: () => showPlanetaryMapDialog(context,
                            api: api, state: current),
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
