import 'package:flutter/material.dart';
import '../../core/models/live_connection_status.dart';
import '../../core/notification_classifier.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

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
  final VoidCallback? onClose;

  const ActivityPanel({
    super.key,
    this.panelKey,
    this.events = const [],
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLiveConnected = true,
    this.isReconnecting = false,
    this.connectionStatus,
    this.onClose,
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoRead();
    });
  }

  void _triggerAutoRead() {
    final validNotifications = widget.notifications
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((n) => !isCorpOrCityNotification(n))
        .toList();

    bool hasUnread = false;
    for (final n in validNotifications) {
      final id = n['id']?.toString();
      if (id != null && id.isNotEmpty && !_isNotificationRead(n)) {
        _locallyReadIds.add(id);
        hasUnread = true;
      }
    }

    if (hasUnread) {
      if (mounted) setState(() {});
      widget.onMarkAllRead();
    }
  }

  String? _formatNotificationDate(Map<String, dynamic> n) {
    final rawDate = n['created_at'] ?? n['createdAt'] ?? n['timestamp'] ?? n['date'];
    if (rawDate == null) return null;
    final formatted = formatRealToGameDateTime(rawDate);
    return formatted != 'unknown' ? formatted : null;
  }

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
        .where((n) => !isCorpOrCityNotification(n))
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
      title: 'DIRECT ALERTS & NOTIFICATIONS',
      showSurface: false,
      trailing: Tooltip(
        message: 'Close notifications',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('notifications_close_button'),
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: context.primaryColor.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.inkColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'CLOSE',
                    style: context.captionStyle.copyWith(
                      color: context.inkColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                    final title = n['title']?.toString() ?? 'Notification';
                    final body = n['body']?.toString() ?? '';
                    final isRead = _isNotificationRead(n);
                    final dateTimeStr = _formatNotificationDate(n);

                    return EarthDataRow(
                      leading: !isRead
                          ? Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: context.primaryColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: context.primaryColor.withValues(alpha: 0.8),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            )
                          : null,
                      title: title,
                      subtitle: body.isNotEmpty ? body : null,
                      secondarySubtitle: dateTimeStr,
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
