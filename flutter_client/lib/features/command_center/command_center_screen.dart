import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../auth/security_dialog.dart';
import '../onboarding/onboarding_guidance_bar.dart';
import '../../core/onboarding_controller.dart';
import '../../core/navigation_deep_link.dart';
import 'dashboard.dart';
import 'sidebar.dart';
import 'top_fixed_hud_panel.dart';
import '../../core/models/live_connection_status.dart';
import '../../core/auth_storage.dart';
import '../../earth_http_client.dart';

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
    'corporation': GlobalKey(),
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
  String? selectedBusinessId;
  List<dynamic> productionCatalog = const [];
  Map<String, dynamic> marketHistory = const {};
  Map<String, dynamic> pantheon = const {};
  Map<String, dynamic> personalFinanceData = const {};
  List<dynamic> contractsList = const [];
  List<dynamic> socialInitiatives = const [];
  int unreadNotifications = 0;
  int unreadCommMessages = 0;
  String selectedSection = 'command';
  LiveConnectionStatus connectionStatus = LiveConnectionStatus.reconnecting;
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  Timer? pollingFallbackTimer;
  http.Client? liveClient;
  StreamSubscription<String>? liveSubscription;
  bool _liveConnecting = false;
  int _wsFailCount = 0;
  final Set<String> _seenEventKeys = <String>{};
  int _requestGeneration = 0;
  final Set<String> _loadingPanels = <String>{};
  final Map<String, Future<dynamic>> _historyRequests =
      <String, Future<dynamic>>{};

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

  Future<void> _connectLiveChannel() async {
    if (_liveConnecting || liveClient != null) return;
    final uri = liveEventsUri(configuredBase: api.baseUrl, pageUri: Uri.base);
    if (uri == null) {
      _startPollingFallback();
      return;
    }
    _liveConnecting = true;
    final client = createEarthHttpClient();
    liveClient = client;
    try {
      final token = await AuthStorage.getToken();
      final sseUri =
          uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http');
      final request = http.Request('GET', sseUri)
        ..headers['accept'] = 'text/event-stream'
        ..headers['cache-control'] = 'no-cache';
      if (token != null && token.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $token';
      }
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('SSE connection failed (${response.statusCode})');
      }
      _wsFailCount = 0;
      _stopPollingFallback();
      if (mounted && connectionStatus != LiveConnectionStatus.live) {
        setState(() => connectionStatus = LiveConnectionStatus.live);
      }
      liveSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('data:')) return;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) return;
        try {
          handleLiveMessage(jsonDecode(payload));
        } catch (_) {
          // Ignore malformed SSE frames and keep the stream alive.
        }
      }, onError: (_) {
        _closeLiveConnection();
        _onWebSocketDisconnected();
      }, onDone: () {
        if (liveClient == null) return;
        _closeLiveConnection();
        _onWebSocketDisconnected();
      });
    } catch (_) {
      _closeLiveConnection();
      _onWebSocketDisconnected();
    } finally {
      _liveConnecting = false;
    }
  }

  void _closeLiveConnection() {
    liveSubscription?.cancel();
    liveSubscription = null;
    liveClient?.close();
    liveClient = null;
  }

  void _manualReconnect() {
    liveReconnectTimer?.cancel();
    liveReconnectTimer = null;
    pollingFallbackTimer?.cancel();
    pollingFallbackTimer = null;
    _closeLiveConnection();
    _wsFailCount = 0;
    if (mounted) {
      setState(() => connectionStatus = LiveConnectionStatus.reconnecting);
    }
    unawaited(_connectLiveChannel());
    unawaited(_refreshEvents());
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
      if (mounted && liveClient == null && !_liveConnecting) {
        unawaited(_connectLiveChannel());
      }
    });
  }

  Future<void> _refreshEvents() async {
    try {
      final results = await Future.wait<dynamic>([
        api.events(),
        api.notifications(),
        api.ownershipEvents(),
        api.membershipEvents(),
        api.authorityEvents(),
        api.personalFinance().catchError((_) => personalFinanceData),
        api.contracts().catchError((_) => contractsList),
        api.commMetrics().catchError((_) => <String, dynamic>{}),
        api.socialInitiatives().catchError((_) => socialInitiatives),
      ]);
      final latest = results[0] as List<dynamic>;
      final notificationData = results[1] as Map<String, dynamic>;
      final ownership = results[2] as List<dynamic>;
      final memberships = results[3] as List<dynamic>;
      final authority = results[4] as List<dynamic>;
      final finData = results[5] as Map<String, dynamic>;
      final cList = results[6] as List<dynamic>;
      final commUnread =
          asInt((results[7] as Map<String, dynamic>)['unreadDispatches']) ??
              unreadCommMessages;
      final social = results[8] as List<dynamic>;
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
          socialInitiatives = social;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = liveClient != null
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
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() {
          state = value;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = liveClient != null
                ? LiveConnectionStatus.live
                : LiveConnectionStatus.polling;
          }
        });
      }
      // The world snapshot is the critical path. Everything else is panel data.
      unawaited(_loadSecondaryPanels(value));
      unawaited(_refreshEvents());
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

  Future<void> _loadSecondaryPanels(EarthState value) async {
    final available = value.businesses.whereType<Map>().toList();
    if (selectedBusinessId == null || !available.any((item) => item['id']?.toString() == selectedBusinessId)) {
      selectedBusinessId = value.business['id']?.toString();
    }
    final businessId = selectedBusinessId;
    if (businessId != null && businessId.isNotEmpty) {
      _loadPanel('business', () async {
        final results = await Future.wait<dynamic>([
          api.businessProfile(businessId),
          api.businessOwnership(businessId),
          api.businessFinancials(businessId),
        ]);
        if (mounted) {
          setState(() {
            businessProfile = results[0];
            businessOwnership = results[1];
            businessFinancials = results[2];
          });
        }
      });
    }
    for (final product in value.market.keys) {
      if (marketHistory.containsKey(product)) continue;
      final request = _historyRequests.putIfAbsent(
          product, () => api.marketPriceHistory(product));
      request.then((history) {
        if (mounted) setState(() => marketHistory[product] = history);
      }).catchError((_) => null);
    }
    if (selectedSection == 'life' || selectedSection == 'command') {
      _loadPanel('pantheon', () async {
        final data = await api.pantheon();
        if (mounted) setState(() => pantheon = data);
      });
    }
  }

  Future<void> _selectBusiness(String businessId) async {
    if (businessId == selectedBusinessId) return;
    setState(() => selectedBusinessId = businessId);
    final results = await Future.wait<dynamic>([
      api.businessProfile(businessId),
      api.businessOwnership(businessId),
      api.businessFinancials(businessId),
    ]);
    if (!mounted || selectedBusinessId != businessId) return;
    setState(() {
      businessProfile = results[0];
      businessOwnership = results[1];
      businessFinancials = results[2];
    });
  }

  Map<String, dynamic>? _activeBusiness(EarthState current) {
    for (final raw in current.businesses) {
      if (raw is Map && raw['id']?.toString() == selectedBusinessId) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  Future<void> _loadPanel(String panel, Future<void> Function() action) async {
    if (_loadingPanels.contains(panel)) return;
    setState(() => _loadingPanels.add(panel));
    try {
      await action();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPanels.remove(panel));
    }
  }

  @override
  void dispose() {
    eventTimer?.cancel();
    liveReconnectTimer?.cancel();
    pollingFallbackTimer?.cancel();
    _closeLiveConnection();
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
    } else if (section == 'city' ||
        section == 'civic' ||
        section == 'corporation') {
      OnboardingController.instance.completeStep('join_community');
    } else if (section == 'market' || section == 'derivatives') {
      OnboardingController.instance.completeStep('first_market_decision');
    } else if (section == 'business' || section == 'technology') {
      OnboardingController.instance.completeStep('start_enterprise');
    } else if (section == 'activity' || section == 'comm') {
      OnboardingController.instance.completeStep('receive_consequence');
    }

    if (updateUrl) {
      NavigationDeepLink.updateSection(section);
    }
    if (mounted) {
      setState(() => selectedSection = section);
      final current = state;
      if (current != null &&
          (section == 'business' || section == 'market' || section == 'life')) {
        unawaited(_loadSecondaryPanels(current));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state;
    final canAdvanceDay = kDebugMode && current != null;

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
                        isLiveConnected: liveClient != null,
                        isReconnecting: liveReconnectTimer?.isActive == true,
                        connectionStatus: connectionStatus,
                        showDrawerButton: compact,
                        onOpenDrawer: () =>
                            _scaffoldKey.currentState?.openDrawer(),
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
                        onCommLink: () => _navigateToSection(
                            context, 'messages',
                            closeDrawer: false),
                        onReconnect: _manualReconnect,
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
                                onSecurity: () => showSecurityDialog(
                                    context, api, widget.onLogout),
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
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: MaterialBanner(
                                        content: Text(error!),
                                        leading:
                                            const Icon(Icons.warning_amber),
                                        actions: [
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => _run(api.world),
                                            child: const Text('RETRY'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (selectedSection == 'command')
                                    OnboardingGuidanceBar(
                                      onNavigate: (section) =>
                                          _navigateToSection(
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
                                      onNavigate: (section) =>
                                          _navigateToSection(
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
                                      activeBusiness: _activeBusiness(current),
                                      onSelectBusiness: _selectBusiness,
                                      membershipEvents: membershipEvents,
                                      authorityEvents: authorityEvents,
                                      productionCatalog: productionCatalog,
                                      marketHistory: marketHistory,
                                      pantheon: pantheon,
                                      personalFinanceData: personalFinanceData,
                                      contracts: contractsList,
                                      socialInitiatives: socialInitiatives,
                                      isLiveConnected: liveClient != null,
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
