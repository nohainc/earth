import 'package:flutter/material.dart';
import '../../core/notification_classifier.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class NewsPanel extends StatefulWidget {
  final List<dynamic> events;
  final List<dynamic> notifications;
  final VoidCallback? onRefresh;

  const NewsPanel({
    super.key,
    this.events = const [],
    this.notifications = const [],
    this.onRefresh,
  });

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  String _filter = 'all';
  int _currentPage = 0;
  static const int _pageSize = 12;

  /// Merge public events + corporate/city notifications into a unified news feed.
  List<Map<String, dynamic>> _buildNewsFeed() {
    final feed = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    // 1. Add public events
    for (final raw in widget.events.whereType<Map>()) {
      final event = Map<String, dynamic>.from(raw);
      final eventType = (event['event_type'] ?? '').toString().toLowerCase();
      final title = (event['title'] ?? '').toString().toLowerCase();
      if (eventType == 'world_clock' ||
          eventType == 'scheduled_tick' ||
          title.contains('public world announcement')) {
        continue;
      }
      // The general activity endpoint also contains ledger, trade, and
      // proposal bookkeeping rows. They are not publishable news items.
      if ((event['title'] ?? '').toString().trim().isEmpty &&
          (event['details'] ?? '').toString().trim().isEmpty) {
        continue;
      }
      final id = (event['id'] ?? event['title'] ?? '').toString();
      if (id.isNotEmpty) seenIds.add(id);
      event['_source'] = 'event';
      feed.add(event);
    }

    // 2. Add corporate/city notifications (avoid duplicates by id)
    for (final raw in widget.notifications.whereType<Map>()) {
      final n = Map<String, dynamic>.from(raw);
      if (!isCorpOrCityNotification(n)) continue;
      final id = (n['id'] ?? '').toString();
      if (id.isNotEmpty && seenIds.contains(id)) continue;
      if (id.isNotEmpty) seenIds.add(id);

      // Normalize notification fields into event-like shape
      n['_source'] = 'notification';
      n['event_type'] ??= n['notification_type'] ?? 'world';
      n['title'] ??= 'News';
      n['details'] ??= n['body'] ?? '';
      n['game_day'] ??= '';
      feed.add(n);
    }

    // Sort newest first (by created_at or game_day descending)
    feed.sort((a, b) {
      final aTime = a['created_at']?.toString() ?? '';
      final bTime = b['created_at']?.toString() ?? '';
      if (aTime.isNotEmpty && bTime.isNotEmpty) {
        return bTime.compareTo(aTime);
      }
      final aDay = int.tryParse(a['game_day']?.toString() ?? '') ?? 0;
      final bDay = int.tryParse(b['game_day']?.toString() ?? '') ?? 0;
      return bDay.compareTo(aDay);
    });

    return feed;
  }

  String _category(Map<String, dynamic> item) {
    // If it came from a notification, use the classifier
    if (item['_source'] == 'notification') {
      return notificationNewsCategory(item);
    }
    final type = (item['event_type'] ?? '').toString().toLowerCase();
    if (type.contains('corporation') || type.contains('research')) {
      return 'corporation';
    }
    if (type.contains('city') || type.contains('civic')) {
      return 'city';
    }
    return 'world';
  }

  IconData _icon(String category) {
    switch (category) {
      case 'corporation':
        return Icons.domain_outlined;
      case 'city':
        return Icons.location_city_outlined;
      default:
        return Icons.public_outlined;
    }
  }

  Color _categoryColor(BuildContext context, String category) {
    switch (category) {
      case 'corporation':
        return Colors.lightBlueAccent;
      case 'city':
        return Colors.amberAccent;
      default:
        return context.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _buildNewsFeed();
    final filteredItems = allItems.where((item) {
      return _filter == 'all' || _category(item) == _filter;
    }).toList();

    // Category counts for cockpit metrics
    final corpCount =
        allItems.where((i) => _category(i) == 'corporation').length;
    final cityCount = allItems.where((i) => _category(i) == 'city').length;
    final worldCount = allItems.where((i) => _category(i) == 'world').length;

    // Pagination
    final totalPages =
        (filteredItems.length / _pageSize).ceil().clamp(1, 9999);
    if (_currentPage >= totalPages) _currentPage = totalPages - 1;
    if (_currentPage < 0) _currentPage = 0;
    final pageItems =
        filteredItems.skip(_currentPage * _pageSize).take(_pageSize).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── COCKPIT ─────────────────────────────────────────────
        EarthPageCockpit(
          tag: 'PUBLIC RECORD',
          status: 'LIVE',
          statusColor: context.primaryColor,
          infoTitle: 'PLANETARY NEWS ARCHITECTURE',
          infoDescription:
              '• News is the public record of meaningful corporation, city, and world events.\n\n'
              '• Corporate and city notifications are merged here automatically.\n\n'
              '• News is read-only; personal actions and private communication remain in their own pages.',
          title: 'NEWS',
          subtitle:
              'Public events, corporate updates, and municipal bulletins across Earth',
          metrics: [
            CockpitMetric(
              label: 'Total',
              value: '${allItems.length}',
              icon: Icons.newspaper_outlined,
              color: context.primaryColor,
            ),
            CockpitMetric(
              label: 'Corporate',
              value: '$corpCount',
              icon: Icons.domain_outlined,
              color: Colors.lightBlueAccent,
            ),
            CockpitMetric(
              label: 'City',
              value: '$cityCount',
              icon: Icons.location_city_outlined,
              color: Colors.amberAccent,
            ),
            CockpitMetric(
              label: 'World',
              value: '$worldCount',
              icon: Icons.public_outlined,
              color: context.secondaryColor,
            ),
          ],
          actions: widget.onRefresh == null
              ? []
              : [
                  EarthButton(
                    label: 'REFRESH',
                    icon: Icons.refresh,
                    onPressed: widget.onRefresh,
                  ),
                ],
        ),
        const SizedBox(height: 24),

        // ─── FILTER TABS (buildings-style) ───────────────────────
        Container(
          margin: EdgeInsets.only(bottom: context.spacingControl),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              _buildTabButton(context,
                  title: 'ALL',
                  icon: Icons.newspaper_outlined,
                  isSelected: _filter == 'all',
                  onTap: () => setState(() {
                        _filter = 'all';
                        _currentPage = 0;
                      })),
              _buildTabButton(context,
                  title: 'CORPORATE',
                  icon: Icons.domain_outlined,
                  isSelected: _filter == 'corporation',
                  onTap: () => setState(() {
                        _filter = 'corporation';
                        _currentPage = 0;
                      })),
              _buildTabButton(context,
                  title: 'CITY',
                  icon: Icons.location_city_outlined,
                  isSelected: _filter == 'city',
                  onTap: () => setState(() {
                        _filter = 'city';
                        _currentPage = 0;
                      })),
              _buildTabButton(context,
                  title: 'WORLD',
                  icon: Icons.public_outlined,
                  isSelected: _filter == 'world',
                  onTap: () => setState(() {
                        _filter = 'world';
                        _currentPage = 0;
                      })),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ─── NEWS ITEMS ──────────────────────────────────────────
        if (filteredItems.isEmpty)
          const EarthEmptyState(
            message: 'No public news is available yet.',
            icon: Icons.newspaper_outlined,
          )
        else ...[
          EarthDataList(
            children: pageItems.map((item) {
              final category = _category(item);
              final title = item['title']?.toString() ?? 'World event';
              final details = (item['details'] ?? item['body'] ?? '').toString();
              final day = item['game_day']?.toString() ?? '';
              final catColor = _categoryColor(context, category);
              final isUnread = item['read'] == false &&
                  item['read_at'] == null &&
                  item['_source'] == 'notification';

              return EarthDataRow(
                title: title,
                subtitle: details.isEmpty
                    ? 'Public ${category == 'world' ? 'world' : category} announcement'
                    : details,
                leading: Icon(
                  _icon(category),
                  size: context.iconSize,
                  color: catColor,
                ),
                badges: [
                  EarthBadge(
                    label: category.toUpperCase(),
                    variant: category == 'world'
                        ? EarthBadgeVariant.neutral
                        : EarthBadgeVariant.primary,
                  ),
                  if (isUnread)
                    const EarthBadge(
                      label: 'NEW',
                      variant: EarthBadgeVariant.primary,
                    ),
                ],
                trailing: day.isNotEmpty
                    ? Text('DAY $day', style: context.captionStyle)
                    : null,
              );
            }).toList(),
          ),

          // ─── PAGINATION ──────────────────────────────────────
          if (filteredItems.length > _pageSize) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PAGE ${_currentPage + 1} OF $totalPages (${filteredItems.length} TOTAL)',
                  style: context.captionStyle
                      .copyWith(color: context.mutedColor),
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
      ],
    );
  }

  // ─── Tab button matching buildings page style ──────────────────
  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? context.primaryColor.withValues(alpha: .15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: context.primaryColor.withValues(alpha: .4))
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color:
                      isSelected ? context.primaryColor : context.mutedColor,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  maxLines: 1,
                  style: context.controlStyle.copyWith(
                    color: isSelected
                        ? context.primaryColor
                        : context.mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
