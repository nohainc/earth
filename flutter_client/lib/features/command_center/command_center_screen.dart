import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/earth_theme_context.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../shared/design_system/earth_empty_state.dart';
import '../auth/security_dialog.dart';
import '../onboarding/house_onboarding_panel.dart';
import '../../core/onboarding_controller.dart';
import '../../core/navigation_deep_link.dart';
import 'dashboard.dart';
import 'sidebar.dart';
import 'top_fixed_hud_panel.dart';
import '../communications/comm_link_dialog.dart';
import '../../core/models/live_connection_status.dart';
import '../../core/auth_storage.dart';
import '../../core/realtime_socket.dart';
import '../../earth_http_client.dart';

Uri? liveEventsUri({required String configuredBase, required Uri pageUri}) {
  final base = configuredBase.isNotEmpty
      ? configuredBase
      : (pageUri.scheme == 'http' || pageUri.scheme == 'https'
          ? pageUri.origin
          : '');
  if (!base.startsWith('http')) return null;
  return Uri.parse('${base.replaceFirst(RegExp(r'^http'), 'ws')}/api/realtime');
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
  final _sectionKeys = <String, Key>{
    'command': const ValueKey('section-command'),
    'market': const ValueKey('section-market'),
    'civic': const ValueKey('section-civic'),
    'corporation': const ValueKey('section-corporation'),
    'corporations': const ValueKey('section-corporations'),
    'city': const ValueKey('section-city'),
    'technology': const ValueKey('section-technology'),
    'life': const ValueKey('section-life'),
    'finance': const ValueKey('section-finance'),
    'activity': const ValueKey('section-activity'),
    'world': const ValueKey('section-world'),
  };
  EarthState? state;
  String? error;
  bool busy = false;
  List<dynamic> events = const [];
  List<dynamic> notifications = const [];
  List<dynamic> ownershipEvents = const [];
  List<dynamic> membershipEvents = const [];
  Map<String, dynamic> marketHistory = const {};
  Map<String, dynamic> pantheon = const {};
  Map<String, dynamic> personalFinanceData = const {};
  Map<String, dynamic> mutualCreditData = const {};
  Map<String, dynamic> territoryCommonsData = const {};
  int unreadNotifications = 0;
  int unreadCommMessages = 0;
  String selectedSection = 'command';
  String _previousSection = 'command';
  LiveConnectionStatus connectionStatus = LiveConnectionStatus.reconnecting;
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  Timer? pollingFallbackTimer;
  Timer? liveHeartbeatTimer;
  Timer? liveHeartbeatTimeoutTimer;
  Timer? refreshCoalesceTimer;
  http.Client? liveClient;
  WebSocketChannel? liveSocket;
  StreamSubscription<String>? liveSubscription;
  bool _liveConnecting = false;
  bool _authExpiredHandled = false;
  int _wsFailCount = 0;
  final Set<String> _seenEventKeys = <String>{};
  final Set<String> _pendingRefreshTopics = <String>{};
  int _requestGeneration = 0;
  final Set<String> _loadingPanels = <String>{};
  final Map<String, Future<dynamic>> _historyRequests =
      <String, Future<dynamic>>{};

  bool get _isLiveConnected => liveClient != null || liveSocket != null;

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
    eventTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshEvents();
      _syncWorldSilently();
    });
  }

  Future<void> _loadProductionCatalog() async {
    try {
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
        final topics = decoded['topics'] is List
            ? (decoded['topics'] as List).map((value) => value.toString())
            : <String>[];
        if (type == 'refresh_required') {
          _queueRefresh(topics.isEmpty ? [topic ?? 'world'] : topics);
        } else if (type == 'world_day_started' ||
            type == 'world_tick' ||
            topic == 'world_activity' ||
            topic == 'market') {
          _queueRefresh([topic == 'market' ? 'market' : 'world']);
        }
      }
    } catch (_) {}
    return true;
  }

  Future<void> _connectLiveChannel() async {
    if (_liveConnecting || liveClient != null || liveSocket != null) return;
    final uri = liveEventsUri(configuredBase: api.baseUrl, pageUri: Uri.base);
    if (uri == null) {
      _startPollingFallback();
      return;
    }
    _liveConnecting = true;
    try {
      final token = await AuthStorage.getToken();
      final socket = connectRealtimeSocket(uri, token);
      liveSocket = socket;
      await socket.ready;
      _markLiveConnected();
      liveSubscription = socket.stream.map((message) => message.toString()).listen(
        (message) {
          _resetLiveHeartbeatTimeout();
          if (message != 'pong') handleLiveMessage(message);
        },
        onError: (_) {
          _closeLiveConnection();
          _onWebSocketDisconnected();
        },
        onDone: () {
          if (liveSocket == null) return;
          _closeLiveConnection();
          _onWebSocketDisconnected();
        },
      );
    } catch (_) {
      if (_authExpiredHandled) return;
      _closeLiveConnection();
      await _connectSseFallback(uri);
    } finally {
      _liveConnecting = false;
    }
  }

  Future<void> _connectSseFallback(Uri uri) async {
    final client = createEarthHttpClient();
    liveClient = client;
    try {
      final token = await AuthStorage.getToken();
      final request = http.Request(
        'GET',
        uri.replace(scheme: uri.scheme == 'wss' ? 'https' : 'http'),
      )
        ..headers['accept'] = 'text/event-stream'
        ..headers['cache-control'] = 'no-cache';
      if (token != null && token.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $token';
      }
      final response = await client.send(request);
      if (response.statusCode == 401) {
        await _handleAuthenticationExpired();
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('SSE connection failed (${response.statusCode})');
      }
      _markLiveConnected();
      liveSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (!line.startsWith('data:')) return;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) return;
        try {
          handleLiveMessage(jsonDecode(payload));
        } catch (_) {}
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
    }
  }

  void _markLiveConnected() {
    _wsFailCount = 0;
    _stopPollingFallback();
    if (mounted && connectionStatus != LiveConnectionStatus.live) {
      setState(() => connectionStatus = LiveConnectionStatus.live);
    }
    liveHeartbeatTimer?.cancel();
    liveHeartbeatTimeoutTimer?.cancel();
    if (liveSocket != null) {
      liveHeartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          liveSocket?.sink.add('ping');
          _resetLiveHeartbeatTimeout();
        } catch (_) {
          _closeLiveConnection();
          _onWebSocketDisconnected();
        }
      });
      _resetLiveHeartbeatTimeout();
    }
  }

  void _resetLiveHeartbeatTimeout() {
    liveHeartbeatTimeoutTimer?.cancel();
    if (liveSocket == null) return;
    liveHeartbeatTimeoutTimer = Timer(const Duration(seconds: 45), () {
      _closeLiveConnection();
      _onWebSocketDisconnected();
    });
  }

  void _queueRefresh(Iterable<String> topics) {
    _pendingRefreshTopics.addAll(topics.where((topic) => topic.isNotEmpty));
    refreshCoalesceTimer ??= Timer(const Duration(milliseconds: 100), () {
      refreshCoalesceTimer = null;
      final pending = Set<String>.from(_pendingRefreshTopics);
      _pendingRefreshTopics.clear();
      if (pending.any((topic) => topic != 'notifications')) {
        unawaited(_syncWorldSilently());
      }
      unawaited(_refreshEvents());
    });
  }

  void _closeLiveConnection() {
    liveHeartbeatTimer?.cancel();
    liveHeartbeatTimer = null;
    liveHeartbeatTimeoutTimer?.cancel();
    liveHeartbeatTimeoutTimer = null;
    liveSubscription?.cancel();
    liveSubscription = null;
    liveSocket?.sink.close();
    liveSocket = null;
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
      _scheduleLiveReconnect(_nextReconnectDelay());
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
    // Keep retrying in the background, but cap the exponential delay.
    _scheduleLiveReconnect(_nextReconnectDelay());
  }

  EarthState? _prefetchedDayState;

  void _stopPollingFallback() {
    pollingFallbackTimer?.cancel();
    pollingFallbackTimer = null;
  }

  Future<void> _onDayRecalculateTrigger() async {
    // World advancement is server-owned. The HUD callback now only refreshes
    // the prefetched snapshot; clients must not trigger a second clock path.
    await _onDayPrefetch();
  }

  Future<void> _onDayPrefetch() async {
    try {
      final next = await api.world();
      if (mounted) {
        _prefetchedDayState = next;
      }
    } catch (_) {
      _prefetchedDayState = null;
    }
  }

  void _onDayRollover() {
    if (_prefetchedDayState != null && mounted) {
      final next = _prefetchedDayState!;
      _prefetchedDayState = null;
      setState(() {
        state = next;
      });
    } else {
      _run(api.world);
    }
  }

  Future<void> _syncWorldSilently() async {
    try {
      final latest = await const EarthApi().world();
      if (mounted) {
        setState(() {
          state = latest;
        });
      }
    } catch (_) {}
  }

  Future<void> _pollFallbackSync() async {
    try {
      await _refreshEvents();
      await _syncWorldSilently();
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

  Duration _nextReconnectDelay() {
    final exponent = _wsFailCount.clamp(0, 5);
    final seconds = 1 << exponent;
    final jitterMilliseconds = DateTime.now().millisecond % 1000;
    return Duration(seconds: seconds, milliseconds: jitterMilliseconds);
  }

  Future<void> _refreshEvents() async {
    try {
      final results = await Future.wait<dynamic>([
        api.events(),
        api.notifications(),
        api.personalFinance().catchError((_) => personalFinanceData),
        api.commMetrics().catchError((_) => <String, dynamic>{}),
      ]);
      final latest = results[0] as List<dynamic>;
      final notificationData = results[1] as Map<String, dynamic>;
      final ownership = latest.where((event) => event is Map<String, dynamic> && event['category'] == 'OWNERSHIP').toList();
      final memberships = latest.where((event) => event is Map<String, dynamic> && event['category'] == 'AFFILIATION').toList();
      final finData = results[2] as Map<String, dynamic>;
      final commUnread = 0;
      if (mounted) {
        setState(() {
          events = latest;
          ownershipEvents = ownership;
          membershipEvents = memberships;
          personalFinanceData = finData;
          unreadCommMessages = commUnread;
          notifications =
              (notificationData['notifications'] as List<dynamic>?) ?? const [];
          unreadNotifications = asInt(notificationData['unread']) ??
              asInt(notificationData['unreadCount']) ??
              0;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = _isLiveConnected
                ? LiveConnectionStatus.live
                : LiveConnectionStatus.polling;
          }
        });
      }
    } catch (exception) {
      // Protected feeds are allowed to reject a request while the session is
      // being restored or has just expired. AuthGate owns that transition;
      // do not mark the whole command center offline for an expected 401.
      if (exception is EarthApiException && exception.isAuthenticationError) {
        await _handleAuthenticationExpired();
        return;
      }
      // If requests fail completely, transition to offline state
      if (mounted && connectionStatus != LiveConnectionStatus.reconnecting) {
        setState(() => connectionStatus = LiveConnectionStatus.offline);
      }
    }
  }

  Future<void> _handleAuthenticationExpired() async {
    if (_authExpiredHandled) return;
    _authExpiredHandled = true;
    eventTimer?.cancel();
    liveReconnectTimer?.cancel();
    pollingFallbackTimer?.cancel();
    await liveSubscription?.cancel();
    liveSubscription = null;
    liveClient?.close();
    liveClient = null;
    await AuthStorage.clearToken();
    if (mounted) widget.onLogout();
  }

  Future<void> _run(Future<EarthState> Function() action) async {
    final requestGeneration = ++_requestGeneration;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Mutation endpoints may return only the changed slice of state. Always
      // follow them with the canonical world snapshot so panels do not lose
      // unrelated collections such as buildings, businesses, or holdings.
      await action();
      final value = await const EarthApi().world();
      if (mounted && requestGeneration == _requestGeneration) {
        setState(() {
          state = value;
          if (connectionStatus == LiveConnectionStatus.offline) {
            connectionStatus = _isLiveConnected
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
    if (selectedSection == 'mutual-credit') {
      _loadPanel('mutual-credit', () async {
        final data = await api.mutualCreditNetworks();
        if (mounted) setState(() => mutualCreditData = data);
      });
    }
    if (selectedSection == 'territory-commons') {
      _loadPanel('territory-commons', () async {
        final residency = await api.getHouseResidency();
        final territoryId = (residency['currentTerritoryId'] ?? residency['territoryId'])?.toString();
        if (territoryId == null || territoryId.isEmpty) return;
        final rights = await api.territoryRights(territoryId: territoryId);
        final commons = await api.commonsStatement(territoryId: territoryId);
        if (mounted) setState(() => territoryCommonsData = {'residency': residency, 'rights': rights['rights'] ?? const [], 'commons': commons});
      });
    }
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
    liveHeartbeatTimer?.cancel();
    liveHeartbeatTimeoutTimer?.cancel();
    refreshCoalesceTimer?.cancel();
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
        section == 'corporation' ||
        section == 'corporations') {
      OnboardingController.instance.completeStep('join_community');
    } else if (section == 'market') {
      OnboardingController.instance.completeStep('first_market_decision');
    } else if (section == 'technology') {
      OnboardingController.instance.completeStep('start_enterprise');
    } else if (section == 'activity' || section == 'comm') {
      OnboardingController.instance.completeStep('receive_consequence');
    }

    if (updateUrl) {
      NavigationDeepLink.updateSection(section);
    }
    if (mounted) {
      if (selectedSection != section &&
          !selectedSection.startsWith('messages') &&
          selectedSection != 'notifications') {
        _previousSection = selectedSection;
      }
      setState(() => selectedSection = section);
      final current = state;
      if (current != null &&
          (section == 'market' || section == 'life' || section == 'mutual-credit' || section == 'territory-commons')) {
        unawaited(_loadSecondaryPanels(current));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state;

    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxWidth < 800;
      final isMessagesMode = selectedSection == 'messages' ||
          selectedSection.startsWith('messages:');
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
                    unreadNotifications: unreadNotifications,
                    unreadCommMessages: unreadCommMessages,
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
                  decoration: BoxDecoration(
                    color: context.canvasColor,
                    gradient: LinearGradient(
                      colors: [
                        context.canvasColor,
                        context.surfaceColor.withValues(alpha: 0.5),
                        context.canvasColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      TopFixedHudPanel(
                        state: current,
                        notifications: notifications,
                        unreadNotifications: unreadNotifications,
                        unreadCommMessages: unreadCommMessages,
                        isLiveConnected: _isLiveConnected,
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
                        onNotifications: () => _navigateToSection(
                            context, 'notifications',
                            closeDrawer: false),
                        onOpenNotifications: () async {
                          await api.markAllNotificationsRead();
                          await _refreshEvents();
                        },
                        onReconnect: _manualReconnect,
                        onDayRecalculateTrigger: _onDayRecalculateTrigger,
                        onDayPrefetch: _onDayPrefetch,
                        onDayRollover: _onDayRollover,
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (!compact)
                            Sidebar(
                              state: current,
                              selectedSection: selectedSection,
                              busy: busy,
                              unreadNotifications: unreadNotifications,
                              unreadCommMessages: unreadCommMessages,
                              isSlim: isMessagesMode,
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
                          if (isMessagesMode)
                            Expanded(
                              child: CommLinkDialog(
                                api: api,
                                state: current,
                                initialChannelId: selectedSection.contains(':')
                                    ? selectedSection.substring(
                                        selectedSection.indexOf(':') + 1)
                                    : null,
                                isPageMode: true,
                                compact: compact,
                                onNavigate: (section) => _navigateToSection(
                                  context,
                                  section,
                                  closeDrawer: false,
                                ),
                                onClose: () => _navigateToSection(
                                  context,
                                  _previousSection.isNotEmpty &&
                                          _previousSection != 'messages' &&
                                          !_previousSection
                                              .startsWith('messages:')
                                      ? _previousSection
                                      : 'command',
                                  closeDrawer: false,
                                ),
                              ),
                            )
                          else
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
                                      child: EarthAlertBanner(
                                        message: error!,
                                        isError: true,
                                        onClose: () =>
                                            setState(() => error = null),
                                      ),
                                    ),
                                  if (selectedSection == 'command')
                                    HouseOnboardingPanel(
                                      api: api,
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
                                      previousSection: _previousSection,
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
                                      membershipEvents: membershipEvents,
                                      marketHistory: marketHistory,
                                      pantheon: pantheon,
                                      personalFinanceData: personalFinanceData,
                                      mutualCreditData: mutualCreditData,
                                      territoryCommonsData: territoryCommonsData,
                                      isLiveConnected: _isLiveConnected,
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
                                      onLogout: widget.onLogout,
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
