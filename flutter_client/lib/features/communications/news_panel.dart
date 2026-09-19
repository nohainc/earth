import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../core/models/news_story.dart';

class NewsPanel extends StatefulWidget {
  final List<NewsStory> news;
  final bool hasMore;
  final VoidCallback? onLoadEarlier;
  final String selectedScope;
  final ValueChanged<String>? onScopeChanged;
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onRefresh;

  const NewsPanel({
    super.key,
    this.news = const [],
    this.hasMore = false,
    this.onLoadEarlier,
    this.selectedScope = 'all',
    this.onScopeChanged,
    this.onNavigate,
    this.onRefresh,
  });

  @override
  State<NewsPanel> createState() => _NewsPanelState();
}

class _NewsPanelState extends State<NewsPanel> {
  /// The server-owned news projection is authoritative; generic events and
  /// House notifications are intentionally not classified in the client.
  List<NewsStory> _buildNewsFeed() => widget.news;

  String _category(NewsStory item) {
    switch (item.scope.type.toUpperCase()) {
      case 'CORPORATION':
        return 'corporation';
      case 'COMMUNITY':
        return 'community';
      default:
        return 'earth';
    }
  }

  String _topic(NewsStory item) => item.topic.toUpperCase();

  IconData _icon(String category) {
    switch (category) {
      case 'organization':
      case 'corporation':
        return Icons.domain_outlined;
      case 'community':
        return Icons.groups_outlined;
      default:
        return Icons.public_outlined;
    }
  }

  Color _categoryColor(BuildContext context, String category) {
    switch (category) {
      case 'organization':
      case 'corporation':
        return Colors.lightBlueAccent;
      case 'community':
        return context.secondaryColor;
      default:
        return context.primaryColor;
    }
  }

  void _showStory(BuildContext context, NewsStory item) {
    final title = item.headline;
    final summary = item.summary;
    final day = item.gameDay == 0 ? '' : item.gameDay.toString();
    final minute = item.gameMinute;
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
              Text('DAY $day${minute != null ? ' · ${formatGameMinute(minute)}' : ''}'),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(summary),
            ],
          ],
        ),
        actions: [
          if (item.action.route != null && widget.onNavigate != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onNavigate!(item.action.route!);
              },
              child: Text(item.action.label ?? 'OPEN RELATED SYSTEM'),
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
    // Pagination
    final pageItems = allItems;

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
            'Follow important public developments across Earth, corporations, communities and other public systems. Personal alerts remain in Notifications.',
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
                  isSelected: widget.selectedScope == 'all',
                  onTap: () => widget.onScopeChanged?.call('all')),
              _buildTabButton(context,
                  title: 'CORPORATIONS',
                  icon: Icons.domain_outlined,
                  isSelected: widget.selectedScope == 'corporation',
                  onTap: () => widget.onScopeChanged?.call('corporation')),
              _buildTabButton(context,
                  title: 'COMMUNITIES',
                  icon: Icons.groups_outlined,
                  isSelected: widget.selectedScope == 'community',
                  onTap: () => widget.onScopeChanged?.call('community')),
              _buildTabButton(context,
                  title: 'EARTH',
                  icon: Icons.public_outlined,
                  isSelected: widget.selectedScope == 'earth',
                  onTap: () => widget.onScopeChanged?.call('earth')),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ─── NEWS ITEMS ──────────────────────────────────────────
        if (pageItems.isEmpty)
          const EarthEmptyState(
            message: 'No public news is available yet.',
            icon: Icons.newspaper_outlined,
          )
        else ...[
          EarthDataList(
            children: pageItems.map((item) {
              final category = _category(item);
              final title = item.headline;
              final details = item.summary;
              final day = item.gameDay == 0 ? '' : item.gameDay.toString();
              final catColor = _categoryColor(context, category);
              final isUnread = item.viewer.isNew;

              return EarthDataRow(
                onTap: () => _showStory(context, item),
                title: title,
                subtitle: details.isEmpty
                    ? 'Public ${category == 'earth' ? 'Earth' : category} announcement'
                    : details,
                leading: Icon(
                  _icon(category),
                  size: context.iconSize,
                  color: catColor,
                ),
                badges: [
                  EarthBadge(
                    label:
                        '${category.toUpperCase()} · ${_topic(item)}',
                    variant: category == 'earth'
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
                        'DAY $day${item.gameMinute != null ? ' · ${formatGameMinute(item.gameMinute!)}' : ''}',
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
