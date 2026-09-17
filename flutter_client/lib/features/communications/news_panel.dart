import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class NewsPanel extends StatefulWidget {
  final List<dynamic> news;
  final bool hasMore;
  final VoidCallback? onLoadEarlier;
  final ValueChanged<String>? onNavigate;
  final List<dynamic> events;
  final List<dynamic> notifications;
  final VoidCallback? onRefresh;

  const NewsPanel({
    super.key,
    this.news = const [],
    this.hasMore = false,
    this.onLoadEarlier,
    this.onNavigate,
    this.events = const [],
    this.notifications = const [],
    this.onRefresh,
  });

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  String _filter = 'all';

  /// The server-owned news projection is authoritative; generic events and
  /// House notifications are intentionally not classified in the client.
  List<Map<String, dynamic>> _buildNewsFeed() {
    return widget.news.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      item['_source'] = 'news';
      return item;
    }).toList();
  }

  String _category(Map<String, dynamic> item) {
    if (item['_source'] == 'news') {
      final scope = (item['scope'] ?? 'EARTH').toString().toUpperCase();
      return scope == 'ORGANIZATION'
          ? 'organization'
          : scope == 'TERRITORY'
              ? 'territory'
              : 'world';
    }
    return 'world';
  }

  String _topic(Map<String, dynamic> item) =>
      (item['topic'] ?? 'WORLD').toString().toUpperCase();

  IconData _icon(String category) {
    switch (category) {
      case 'organization':
      case 'corporation':
        return Icons.domain_outlined;
      case 'territory':
        return Icons.location_city_outlined;
      default:
        return Icons.public_outlined;
    }
  }

  Color _categoryColor(BuildContext context, String category) {
    switch (category) {
      case 'organization':
      case 'corporation':
        return Colors.lightBlueAccent;
      case 'territory':
        return Colors.amberAccent;
      default:
        return context.primaryColor;
    }
  }

  void _showStory(BuildContext context, Map<String, dynamic> item) {
    final title = (item['headline'] ?? item['title'] ?? 'News').toString();
    final summary =
        (item['summary'] ?? item['details'] ?? item['body'] ?? '').toString();
    final day = item['game_day']?.toString() ?? '';
    final minute = item['game_minute']?.toString();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_category(item).toUpperCase()} · ${_topic(item)}',
                style: Theme.of(context).textTheme.labelMedium),
            if (day.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('DAY $day${minute != null ? ' · $minute' : ''}'),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(summary),
            ],
            if (item['related_entity_id'] != null) ...[
              const SizedBox(height: 16),
              Text(
                  'Related ${item['related_entity_type'] ?? 'system'}: ${item['related_entity_id']}'),
            ],
          ],
        ),
        actions: [
          if (item['related_route'] != null && widget.onNavigate != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onNavigate!(item['related_route'].toString());
              },
              child: const Text('OPEN RELATED SYSTEM'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CLOSE')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _buildNewsFeed();
    final filteredItems = allItems.where((item) {
      return _filter == 'all' || _category(item) == _filter;
    }).toList();

    // Pagination
    final pageItems = filteredItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── COCKPIT ─────────────────────────────────────────────
        EarthPageCockpit(
          tag: 'WORLD INTELLIGENCE',
          status: 'LIVE FEED',
          statusColor: context.primaryColor,
          infoTitle: 'ABOUT NEWS',
          infoDescription:
              'Follow important public developments across Earth. News covers world events, territories, organizations, technology and other public systems. Personal alerts remain in Notifications.',
          title: 'NEWS',
          subtitle:
              'Important developments and public intelligence across Earth',
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
                      })),
              _buildTabButton(context,
                  title: 'CORPORATIONS',
                  icon: Icons.domain_outlined,
                  isSelected: _filter == 'organization',
                  onTap: () => setState(() {
                        _filter = 'organization';
                      })),
              _buildTabButton(context,
                  title: 'GLOBAL (EARTH)',
                  icon: Icons.public_outlined,
                  isSelected: _filter == 'world',
                  onTap: () => setState(() {
                        _filter = 'world';
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
              final title = (item['headline'] ?? item['title'] ?? 'World event')
                  .toString();
              final details =
                  (item['summary'] ?? item['details'] ?? item['body'] ?? '')
                      .toString();
              final day = item['game_day']?.toString() ?? '';
              final catColor = _categoryColor(context, category);
              final isUnread = item['is_new'] == true ||
                  (item['read'] == false && item['read_at'] == null);

              return EarthDataRow(
                onTap: () => _showStory(context, item),
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
                    label:
                        '${category == 'organization' ? 'ORGANIZATION' : category.toUpperCase()} · ${_topic(item)}',
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
                    ? Text(
                        'DAY $day${item['game_minute'] != null ? ' · ${item['game_minute']}' : ''}',
                        style: context.captionStyle)
                    : null,
              );
            }).toList(),
          ),
          if (widget.hasMore && widget.onLoadEarlier != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.center,
              child: EarthButton(
                label: 'LOAD EARLIER NEWS',
                icon: Icons.history,
                onPressed: widget.onLoadEarlier,
              ),
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
                ? Border.all(color: context.primaryColor.withValues(alpha: .4))
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
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  maxLines: 1,
                  style: context.controlStyle.copyWith(
                    color:
                        isSelected ? context.primaryColor : context.mutedColor,
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
