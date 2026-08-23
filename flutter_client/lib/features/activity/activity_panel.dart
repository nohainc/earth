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

  bool _isNotificationRead(Map<String, dynamic> n) {
    final id = n['id']?.toString() ?? '';
    if (_locallyReadIds.contains(id)) return true;

    final readAt = n['read_at'] ?? n['readAt'];
    if (readAt != null && readAt.toString().isNotEmpty && readAt.toString() != 'null') {
      return true;
    }

    final read = n['read'];
    if (read == true || read == 'true' || read == 1 || read == '1') {
      return true;
    }

    final status = n['status']?.toString().toLowerCase();
    if (status == 'read') return true;

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final validNotifications = widget.notifications
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();

    final unreadCount = validNotifications
        .where((n) => !_isNotificationRead(n))
        .length;

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
      title: unreadCount > 0
          ? 'DIRECT ALERTS & NOTIFICATIONS ($unreadCount)'
          : 'DIRECT ALERTS & NOTIFICATIONS',
      showSurface: false,
      trailing: validNotifications.isNotEmpty
          ? EarthButton(
              label: 'MARK ALL AS READ',
              icon: Icons.done_all_rounded,
              onPressed: unreadCount > 0
                  ? () async {
                      for (final n in validNotifications) {
                        final id = n['id']?.toString();
                        if (id != null && id.isNotEmpty) {
                          _locallyReadIds.add(id);
                        }
                      }
                      setState(() {});
                      await widget.onMarkAllRead();
                    }
                  : null,
            )
          : null,
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
                    final isRead = _isNotificationRead(n);

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
