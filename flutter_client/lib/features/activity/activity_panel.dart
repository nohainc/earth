import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../core/models/live_connection_status.dart';

class ActivityPanel extends StatefulWidget {
  final List<dynamic> events;
  final List<dynamic> notifications;
  final int unreadCount;
  final bool isLiveConnected;
  final bool isReconnecting;
  final LiveConnectionStatus? connectionStatus;
  final VoidCallback onRefresh;
  final Future<void> Function(String) onMarkRead;
  final Future<void> Function() onMarkAllRead;
  final Key? panelKey;

  const ActivityPanel({
    super.key,
    this.panelKey,
    this.events = const [],
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLiveConnected = true,
    this.isReconnecting = false,
    this.connectionStatus,
    required this.onRefresh,
    required this.onMarkRead,
    required this.onMarkAllRead,
  });

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _locallyReadIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatEventSummary(Map<String, dynamic> evt) {
    final type = evt['type']?.toString() ?? 'event';
    final gameDay = evt['gameDay'] ?? evt['game_day'];
    final dayPrefix = gameDay != null ? '[Day $gameDay] ' : '';

    if (type == 'world_day_started' ||
        type == 'world_tick' ||
        type == 'world.day_advanced') {
      return '${dayPrefix}World simulation cycle advanced to Game Day $gameDay';
    }
    if (type == 'market.batch_settled' || type == 'market') {
      return '${dayPrefix}Central Market batch cleared and settled';
    }
    if (type == 'governance.vote_updated' || type == 'governance') {
      return '${dayPrefix}Governance proposal ballot recorded';
    }
    if (type == 'research.progressed' || type == 'research') {
      return '${dayPrefix}Collaborative technology research advanced';
    }
    if (type == 'business.policy_changed') {
      return '${dayPrefix}Enterprise operational policy adjusted';
    }
    if (type == 'contract.proposed' ||
        type == 'contract.accepted' ||
        type == 'contract.disputed' ||
        type == 'contract.resolved') {
      return '${dayPrefix}Contract lifecycle event ($type) recorded';
    }
    if (type == 'human.bankruptcy') {
      return '${dayPrefix}Insolvency restructuring registered with OUC treasury';
    }
    if (type == 'taxes.settled') {
      return '${dayPrefix}Public tax assessment settled with municipal authority';
    }

    final title =
        evt['title']?.toString() ?? evt['eventType']?.toString() ?? type;
    return '$dayPrefix$title';
  }

  IconData _getEventIcon(String type) {
    if (type.contains('market')) return Icons.storefront_outlined;
    if (type.contains('world') || type.contains('tick')) {
      return Icons.public_rounded;
    }
    if (type.contains('governance') || type.contains('vote')) {
      return Icons.how_to_vote_outlined;
    }
    if (type.contains('research')) return Icons.biotech_outlined;
    if (type.contains('business')) return Icons.domain_outlined;
    if (type.contains('contract')) return Icons.handshake_outlined;
    if (type.contains('tax')) return Icons.receipt_long_outlined;
    if (type.contains('bankrupt') || type.contains('insolvency')) {
      return Icons.warning_amber_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  Color _getEventColor(String type) {
    if (type.contains('market')) return Colors.tealAccent;
    if (type.contains('world') || type.contains('tick')) return cyanAccentColor;
    if (type.contains('governance') || type.contains('vote'))
      return violetColor;
    if (type.contains('research')) return Colors.lightGreenAccent;
    if (type.contains('business')) return Colors.amberAccent;
    if (type.contains('contract')) return cyanAccentColor;
    if (type.contains('tax')) return Colors.orangeAccent;
    if (type.contains('bankrupt') || type.contains('insolvency')) {
      return Colors.redAccent;
    }
    return mutedColor;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveUnread = widget.unreadCount - _locallyReadIds.length;
    final displayUnread = effectiveUnread > 0 ? effectiveUnread : 0;

    return EarthPanel(
      key: widget.panelKey,
      title: 'ACTIVITY & NOTIFICATIONS CENTER',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Real-Time Operations Telemetry: Unified stream of private executive alerts and macroscopic planetary simulation events.\n\n• Stream Channels:\n  - PERSONAL ALERTS: Directed high-priority notices including tax assessments, contract proposals, filled trade orders, and enterprise dividends.\n  - PUBLIC FEED: Live global ledger updates, market batch settlement cycles, research milestones, and governance ballots.\n\n• Connection Status: Real-time telemetry pulse displaying WebSocket / SSE streaming health with automatic reconnection and event replay.\n\n• Acknowledgment: Mark individual alerts or batch acknowledge all pending notifications.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopicHeading(context),
          // 1. ACTIVITY TOOLBAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 16, color: mutedColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.events.length} EVENTS BUFFERED',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                      letterSpacing: .5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  tooltip: 'Refresh events & notifications',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. SEGMENTED NAVIGATION TABS
          Container(
            decoration: BoxDecoration(
              color: surfaceColor.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: cyanAccentColor,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 2.5,
              dividerColor: Colors.transparent,
              labelColor: inkColor,
              unselectedLabelColor: mutedColor,
              labelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active_outlined, size: 14),
                      const SizedBox(width: 6),
                      Text(displayUnread > 0
                          ? 'ALERTS ($displayUnread)'
                          : 'ALERTS'),
                    ],
                  ),
                ),
                const Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.feed_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('PUBLIC FEED'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. STREAM CONTENT VIEW
          SizedBox(
            height: 320,
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: PERSONAL ALERTS
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.notifications.isNotEmpty && displayUnread > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$displayUnread PENDING NOTIFICATIONS',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .8,
                                color: mutedColor,
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                for (final n in widget.notifications) {
                                  if (n is Map<String, dynamic> &&
                                      n['id'] != null) {
                                    _locallyReadIds.add(n['id'].toString());
                                  }
                                }
                                setState(() {});
                                await widget.onMarkAllRead();
                              },
                              icon: const Icon(Icons.done_all_rounded,
                                  size: 13, color: cyanAccentColor),
                              label: const Text(
                                'MARK ALL READ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cyanAccentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: widget.notifications.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded,
                                      size: 32, color: mutedColor),
                                  SizedBox(height: 8),
                                  Text(
                                    'No notifications received yet.',
                                    style: TextStyle(
                                        fontSize: 11, color: mutedColor),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount:
                                  widget.notifications.length.clamp(0, 30),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (ctx, i) {
                                final n = widget.notifications[i];
                                if (n is! Map<String, dynamic>) {
                                  return const SizedBox.shrink();
                                }
                                final id = n['id']?.toString() ?? 'NOTIF-$i';
                                final title =
                                    n['title']?.toString() ?? 'Notification';
                                final body = n['body']?.toString() ?? '';
                                final isRead = n['read'] == true ||
                                    _locallyReadIds.contains(id);

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isRead
                                        ? surfaceColor.withValues(alpha: .4)
                                        : surfaceColor.withValues(alpha: .85),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isRead
                                          ? Colors.white10
                                          : cyanAccentColor.withValues(
                                              alpha: .3),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isRead
                                              ? Colors.white
                                                  .withValues(alpha: .04)
                                              : cyanAccentColor.withValues(
                                                  alpha: .15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          isRead
                                              ? Icons.notifications_none_rounded
                                              : Icons
                                                  .notifications_active_outlined,
                                          size: 14,
                                          color: isRead
                                              ? mutedColor
                                              : cyanAccentColor,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: isRead
                                                    ? FontWeight.w600
                                                    : FontWeight.w800,
                                                color: isRead
                                                    ? mutedColor
                                                    : inkColor,
                                              ),
                                            ),
                                            if (body.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                body,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  color: isRead
                                                      ? mutedColor.withValues(
                                                          alpha: .8)
                                                      : inkColor.withValues(
                                                          alpha: .9),
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (!isRead) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                              Icons
                                                  .check_circle_outline_rounded,
                                              size: 16,
                                              color: cyanAccentColor),
                                          tooltip: 'Mark read',
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            setState(
                                                () => _locallyReadIds.add(id));
                                            await widget.onMarkRead(id);
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),

                // TAB 2: PUBLIC ACTIVITY FEED
                widget.events.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sensors_off_rounded,
                                size: 32, color: mutedColor),
                            SizedBox(height: 8),
                            Text(
                              'No recent simulation activity recorded.',
                              style: TextStyle(fontSize: 11, color: mutedColor),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.events.length.clamp(0, 40),
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (ctx, i) {
                          final evt = widget.events[i];
                          if (evt is! Map<String, dynamic>) {
                            return const SizedBox.shrink();
                          }
                          final type = evt['type']?.toString() ?? 'event';
                          final color = _getEventColor(type);
                          final icon = _getEventIcon(type);
                          final summary = _formatEventSummary(evt);

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: surfaceColor.withValues(alpha: .6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(icon, size: 14, color: color),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    summary,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: inkColor,
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicHeading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Flexible(
            child: Text(
              'ACTIVITY & NOTIFICATIONS CENTER',
              style: TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'About activity and notifications',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.info_outline,
                size: 14, color: mutedColor.withValues(alpha: .8)),
            onPressed: () => showEarthInfoDialog(
              context,
              title: 'ACTIVITY & NOTIFICATIONS CENTER',
              description:
                  '• Real-Time Operations Telemetry: review personal alerts and public simulation activity.\n\n'
                  '• Mark notifications as read and refresh the event stream.\n\n'
                  '• Connection status is available from the Alerts menu.',
            ),
          ),
        ],
      ),
    );
  }
}
