import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../shared/widgets/earth_primitives.dart';

class ActivityPanel extends StatefulWidget {
  final List<dynamic> events;
  final List<dynamic> notifications;
  final int unreadCount;
  final bool isLiveConnected;
  final bool isReconnecting;
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
    required this.onRefresh,
    required this.onMarkRead,
    required this.onMarkAllRead,
  });

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel> with SingleTickerProviderStateMixin {
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

    if (type == 'world_day_started' || type == 'world_tick' || type == 'world.day_advanced') {
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
    if (type == 'contract.proposed' || type == 'contract.accepted' || type == 'contract.disputed' || type == 'contract.resolved') {
      return '${dayPrefix}Contract lifecycle event ($type) recorded';
    }
    if (type == 'human.bankruptcy') {
      return '${dayPrefix}Insolvency restructuring registered with OUC treasury';
    }
    if (type == 'taxes.settled') {
      return '${dayPrefix}Public tax assessment settled with municipal authority';
    }

    // Default safe sanitized message without leaking private account hashes/tokens
    final title = evt['title']?.toString() ?? evt['eventType']?.toString() ?? type;
    return '$dayPrefix$title';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveUnread = widget.unreadCount - _locallyReadIds.length;
    final displayUnread = effectiveUnread > 0 ? effectiveUnread : 0;

    return EarthPanel(
      key: widget.panelKey,
      title: 'ACTIVITY & NOTIFICATIONS CENTER',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live connection status bar
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isLiveConnected
                      ? cyanAccentColor
                      : (widget.isReconnecting ? Colors.orangeAccent : Colors.redAccent),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.isLiveConnected
                      ? 'LIVE STREAM ACTIVE'
                      : (widget.isReconnecting ? 'RECONNECTING / REPLAYING...' : 'DISCONNECTED'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.isLiveConnected
                        ? cyanAccentColor
                        : (widget.isReconnecting ? Colors.orangeAccent : Colors.redAccent),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: 'Refresh events & notifications',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabController,
            isScrollable: false,
            indicatorColor: cyanAccentColor,
            labelColor: Colors.white,
            unselectedLabelColor: mutedColor,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            tabs: [
              Tab(
                text: displayUnread > 0 ? 'ALERTS ($displayUnread)' : 'ALERTS',
              ),
              const Tab(text: 'PUBLIC FEED'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Notifications
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.notifications.isNotEmpty && displayUnread > 0)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                          onPressed: () async {
                            for (final n in widget.notifications) {
                              if (n is Map<String, dynamic> && n['id'] != null) {
                                _locallyReadIds.add(n['id'].toString());
                              }
                            }
                            setState(() {});
                            await widget.onMarkAllRead();
                          },
                          child: const Text('MARK ALL READ', style: TextStyle(fontSize: 10, color: cyanAccentColor)),
                        ),
                      ),
                    Expanded(
                      child: widget.notifications.isEmpty
                          ? const Center(
                              child: Text('No notifications received yet.', style: TextStyle(fontSize: 11, color: mutedColor)),
                            )
                          : ListView.separated(
                              itemCount: widget.notifications.length.clamp(0, 30),
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                              itemBuilder: (ctx, i) {
                                final n = widget.notifications[i];
                                if (n is! Map<String, dynamic>) return const SizedBox.shrink();
                                final id = n['id']?.toString() ?? 'NOTIF-$i';
                                final title = n['title']?.toString() ?? 'Notification';
                                final body = n['body']?.toString() ?? '';
                                final isRead = n['read'] == true || _locallyReadIds.contains(id);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.only(top: 4, right: 8),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isRead ? Colors.transparent : cyanAccentColor,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(title, style: TextStyle(fontSize: 11, fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                                            if (body.isNotEmpty)
                                              Text(body, style: const TextStyle(fontSize: 10, color: mutedColor)),
                                          ],
                                        ),
                                      ),
                                      if (!isRead)
                                        IconButton(
                                          icon: const Icon(Icons.check, size: 14, color: mutedColor),
                                          tooltip: 'Mark read',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            setState(() => _locallyReadIds.add(id));
                                            await widget.onMarkRead(id);
                                          },
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
                // Tab 2: Public Activity Feed
                widget.events.isEmpty
                    ? const Center(
                        child: Text('No recent simulation activity recorded.', style: TextStyle(fontSize: 11, color: mutedColor)),
                      )
                    : ListView.separated(
                        itemCount: widget.events.length.clamp(0, 40),
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (ctx, i) {
                          final evt = widget.events[i];
                          if (evt is! Map<String, dynamic>) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Text(
                              _formatEventSummary(evt),
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
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
}
