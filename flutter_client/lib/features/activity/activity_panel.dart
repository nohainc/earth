import 'package:flutter/material.dart';
import '../../core/models/live_connection_status.dart';
import '../../shared/design_system/design_system.dart';

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
      return '${dayPrefix}World operating cycle advanced to Game Day $gameDay';
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

    final title = evt['title']?.toString() ?? evt['eventType']?.toString() ?? type;
    return '$dayPrefix$title';
  }

  IconData _getEventIcon(String type) {
    if (type.contains('market')) return Icons.storefront_outlined;
    if (type.contains('world') || type.contains('tick')) return Icons.public_rounded;
    if (type.contains('governance') || type.contains('vote')) return Icons.how_to_vote_outlined;
    if (type.contains('research')) return Icons.biotech_outlined;
    if (type.contains('business')) return Icons.domain_outlined;
    if (type.contains('contract')) return Icons.handshake_outlined;
    if (type.contains('tax')) return Icons.receipt_long_outlined;
    if (type.contains('bankrupt') || type.contains('insolvency')) {
      return Icons.warning_amber_rounded;
    }
    return Icons.notifications_none_rounded;
  }

  Color _getEventColor(BuildContext context, String type) {
    if (type.contains('bankrupt') ||
        type.contains('insolvency') ||
        type.contains('dispute') ||
        type.contains('penalty') ||
        type.contains('fail')) {
      return context.errorColor;
    }
    if (type.contains('settled') ||
        type.contains('cleared') ||
        type.contains('completed') ||
        type.contains('success')) {
      return context.successColor;
    }
    if (type.contains('tax') ||
        type.contains('warning') ||
        type.contains('alert') ||
        type.contains('policy')) {
      return context.warningColor;
    }
    return context.mutedColor;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveUnread = widget.unreadCount - _locallyReadIds.length;
    final displayUnread = effectiveUnread > 0 ? effectiveUnread : 0;

    return EarthSection(
      key: widget.panelKey,
      title: 'EVENT HISTORY & ARCHIVE',
      showSurface: false,
      infoBulletPoints: const [
        'Real-Time Operations Telemetry: Secondary archive for reviewing events after they leave Daily Priorities.',
        'Use domain pages for current decisions: Businesses for operations, Contracts for commitments, Trade for orders, Governance for civic actions, and Family for personal events.',
        'Personal alerts and public events remain available here for history, audit, and context.',
      ],
      trailing: Tooltip(
        message: 'Refresh events & notifications',
        child: EarthButton(
          label: 'REFRESH',
          icon: Icons.refresh_rounded,
          onPressed: widget.onRefresh,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              indicatorColor: context.primaryColor,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 2.5,
              dividerColor: context.subtleBorderColor,
              labelColor: context.inkColor,
              unselectedLabelColor: context.mutedColor,
              labelStyle: context.widgetTitleStyle,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active_outlined, size: 14),
                      const SizedBox(width: 6),
                      Text(displayUnread > 0 ? 'ALERTS ($displayUnread)' : 'ALERTS'),
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
            SizedBox(
              height: 420,
              child: Padding(
                padding: EdgeInsets.all(context.cardPadding),
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
                                  style: context.captionStyle.copyWith(color: context.mutedColor),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    for (final n in widget.notifications) {
                                      if (n is Map<String, dynamic> && n['id'] != null) {
                                        _locallyReadIds.add(n['id'].toString());
                                      }
                                    }
                                    setState(() {});
                                    await widget.onMarkAllRead();
                                  },
                                  icon: Icon(Icons.done_all_rounded, size: 13, color: context.primaryColor),
                                  label: Text(
                                    'MARK ALL READ',
                                    style: context.controlStyle.copyWith(color: context.primaryColor),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: widget.notifications.isEmpty
                              ? const EarthEmptyState(
                                  message: 'No notifications received yet.',
                                  icon: Icons.check_circle_outline_rounded,
                                )
                              : EarthDataList(
                                  children: widget.notifications.take(30).map((n) {
                                    if (n is! Map<String, dynamic>) {
                                      return const SizedBox.shrink();
                                    }
                                    final id = n['id']?.toString() ?? 'NOTIF';
                                    final title = n['title']?.toString() ?? 'Notification';
                                    final body = n['body']?.toString() ?? '';
                                    final isRead = n['read'] == true || _locallyReadIds.contains(id);

                                    return EarthDataRow(
                                      title: title,
                                      subtitle: body.isNotEmpty ? body : null,
                                      leading: Icon(
                                        isRead
                                            ? Icons.notifications_none_rounded
                                            : Icons.notifications_active_outlined,
                                        size: context.iconSize,
                                        color: isRead ? context.mutedColor : context.primaryColor,
                                      ),
                                      badges: [
                                        EarthBadge(
                                          label: isRead ? 'READ' : 'NEW',
                                          variant: isRead ? EarthBadgeVariant.neutral : EarthBadgeVariant.primary,
                                        ),
                                      ],
                                      trailing: !isRead
                                          ? Tooltip(
                                              message: 'Mark read',
                                              child: EarthButton(
                                                label: 'MARK READ',
                                                onPressed: () async {
                                                  setState(() => _locallyReadIds.add(id));
                                                  await widget.onMarkRead(id);
                                                },
                                              ),
                                            )
                                          : null,
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),

                    // TAB 2: PUBLIC ACTIVITY FEED
                    widget.events.isEmpty
                        ? const EarthEmptyState(
                            message: 'No recent World activity recorded.',
                            icon: Icons.sensors_off_rounded,
                          )
                        : EarthDataList(
                            children: widget.events.take(40).map((evt) {
                              if (evt is! Map<String, dynamic>) {
                                return const SizedBox.shrink();
                              }
                              final type = evt['type']?.toString() ?? 'event';
                              final color = _getEventColor(context, type);
                              final icon = _getEventIcon(type);
                              final summary = _formatEventSummary(evt);

                              return EarthDataRow(
                                title: summary,
                                leading: Icon(icon, size: context.iconSize, color: color),
                              );
                            }).toList(),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
