import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../auth/security_dialog.dart';
import 'dashboard.dart';
import 'sidebar.dart';

class CommandCenter extends StatefulWidget {
  final VoidCallback onLogout;
  const CommandCenter({super.key, required this.onLogout});

  @override
  State<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<CommandCenter> {
  final api = const EarthApi();
  final _scrollController = ScrollController();
  final _sectionKeys = <String, GlobalKey>{
    'command': GlobalKey(),
    'market': GlobalKey(),
    'business': GlobalKey(),
    'civic': GlobalKey(),
    'city': GlobalKey(),
    'technology': GlobalKey(),
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
  int unreadNotifications = 0;
  Timer? eventTimer;
  Timer? liveReconnectTimer;
  WebSocketChannel? liveChannel;

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

  void _connectLiveChannel() {
    final base = api.baseUrl;
    if (base.isEmpty) return;
    final uri =
        Uri.parse('${base.replaceFirst(RegExp(r'^http'), 'ws')}/edge/events');
    try {
      liveChannel = WebSocketChannel.connect(uri);
      liveChannel!.stream.listen((_) {
        if (mounted) _refreshEvents();
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
      if (mounted) {
        setState(() {
          events = latest;
          ownershipEvents = ownership;
          membershipEvents = memberships;
          authorityEvents = authority;
          notifications =
              (notificationData['notifications'] as List<dynamic>?) ?? const [];
          unreadNotifications =
              (notificationData['unread'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // The world snapshot remains usable if the optional live feed is temporarily unavailable.
    }
  }

  Future<void> _run(Future<EarthState> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await action();
      Map<String, dynamic> ownership = const {};
      Map<String, dynamic> financials = const {};
      Map<String, dynamic> profile = const {};
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
      if (mounted) {
        setState(() {
          state = value;
          businessProfile = profile;
          businessOwnership = ownership;
          businessFinancials = financials;
        });
      }
      await _refreshEvents();
    } catch (exception) {
      if (mounted) {
        setState(
            () => error = exception.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    eventTimer?.cancel();
    liveReconnectTimer?.cancel();
    liveChannel?.sink.close();
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToSection(BuildContext context, String section,
      {required bool closeDrawer}) {
    if (closeDrawer) Navigator.of(context).pop();
    final target = _sectionKeys[section]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: .04);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = state;
    final canAdvanceDay = current?.roles.any((raw) {
          final role = raw as Map<String, dynamic>;
          return role['id'] == 'ROLE-OUC-DELEGATE' &&
              role['human_id'] == current.human['id'] &&
              role['assignment_status'] == 'active';
        }) ??
        false;

    return LayoutBuilder(builder: (context, viewport) {
      final compact = viewport.maxWidth < 900;
      return Scaffold(
        drawer: current != null && compact
            ? Drawer(
                backgroundColor: canvasColor,
                child: SafeArea(
                  child: Sidebar(
                    state: current,
                    onNavigate: (section) => _navigateToSection(
                      context,
                      section,
                      closeDrawer: true,
                    ),
                  ),
                ),
              )
            : null,
        appBar: AppBar(
          title: const Text(
            'EARTH  ·  COMMAND CENTER',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
          actions: [
            if (busy)
              const Padding(
                padding: EdgeInsets.all(18),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            TextButton(
              onPressed:
                  busy || !canAdvanceDay ? null : () => _run(api.advanceDay),
              child: const Text('ADVANCE DAY  →'),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: busy
                  ? null
                  : () async {
                      await api.logout();
                      if (mounted) widget.onLogout();
                    },
              icon: const Icon(Icons.logout),
            ),
            IconButton(
              tooltip: 'Account security',
              onPressed: busy
                  ? null
                  : () => showSecurityDialog(context, api, widget.onLogout),
              icon: const Icon(Icons.security),
            ),
          ],
        ),
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
                  child: Row(
                    children: [
                      if (!compact)
                        Sidebar(
                          state: current,
                          onNavigate: (section) => _navigateToSection(
                            context,
                            section,
                            closeDrawer: false,
                          ),
                        ),
                      Expanded(
                        child: ListView(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                            compact ? 16 : 34,
                            compact ? 16 : 26,
                            compact ? 16 : 42,
                            56,
                          ),
                          children: [
                            if (compact)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'COMPACT COMMAND VIEW',
                                  style: TextStyle(
                                    color: mutedColor,
                                    fontSize: 9,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ),
                            Dashboard(
                              state: current,
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
                              unreadNotifications: unreadNotifications,
                              sectionKeys: _sectionKeys,
                              action: _run,
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
