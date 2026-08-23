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

class _ActivityPanelState extends State<ActivityPanel> {
  final Set<String> _locallyReadIds = <String>{};
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  Widget build(BuildContext context) {
    final effectiveUnread = widget.unreadCount - _locallyReadIds.length;
    final displayUnread = effectiveUnread > 0 ? effectiveUnread : 0;

    final validNotifications = widget.notifications
        .whereType<Map<String, dynamic>>()
        .toList();

    final totalPages = (validNotifications.length / _pageSize).ceil().clamp(1, 9999);
    if (_currentPage >= totalPages) {
      _currentPage = totalPages - 1;
    }
    if (_currentPage < 0) {
      _currentPage = 0;
    }

    final pageItems = validNotifications
        .skip(_currentPage * _pageSize)
        .take(_pageSize)
        .toList();

    return EarthSection(
      key: widget.panelKey,
      title: displayUnread > 0
          ? 'DIRECT ALERTS & NOTIFICATIONS ($displayUnread)'
          : 'DIRECT ALERTS & NOTIFICATIONS',
      showSurface: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (validNotifications.isNotEmpty && displayUnread > 0) ...[
            TextButton.icon(
              onPressed: () async {
                for (final n in validNotifications) {
                  if (n['id'] != null) {
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
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: 'Refresh alerts',
            child: EarthButton(
              label: 'REFRESH',
              icon: Icons.refresh_rounded,
              onPressed: widget.onRefresh,
            ),
          ),
        ],
      ),
      child: validNotifications.isEmpty
          ? const EarthEmptyState(
              message: 'No pending notifications. All personal systems nominal.',
              icon: Icons.check_circle_outline_rounded,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EarthDataList(
                  children: pageItems.map((n) {
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

                // Pagination Footer
                if (validNotifications.length > _pageSize) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PAGE ${_currentPage + 1} OF $totalPages (${validNotifications.length} TOTAL)',
                        style: context.captionStyle.copyWith(color: context.mutedColor),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EarthButton(
                            label: 'PREVIOUS',
                            icon: Icons.chevron_left_rounded,
                            onPressed: _currentPage > 0
                                ? () => setState(() => _currentPage--)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          EarthButton(
                            label: 'NEXT',
                            icon: Icons.chevron_right_rounded,
                            onPressed: _currentPage < totalPages - 1
                                ? () => setState(() => _currentPage++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
