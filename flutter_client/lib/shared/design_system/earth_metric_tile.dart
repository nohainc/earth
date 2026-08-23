import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

/// Standardized KPI/metric card conforming to design tokens and theme.
class EarthMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? accentColor;
  final String? hint;
  final String? subtitle;
  final double? width;
  final VoidCallback? onInfoTap;
  final VoidCallback? onTap;

  const EarthMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.accentColor,
    this.hint,
    this.subtitle,
    this.width,
    this.onInfoTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? context.primaryColor;
    final content = Container(
      width: width ?? 165,
      padding: EdgeInsets.all(context.tokens.number('pageTopics.cardPadding', 10)),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: context.iconSize, color: color),
                SizedBox(width: context.spacingInline),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: context.widgetTitleStyle.copyWith(color: context.mutedColor),
                ),
              ),
              if (hint != null || onInfoTap != null)
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    size: 13,
                    color: context.mutedColor.withValues(alpha: .7),
                  ),
                  tooltip: hint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onInfoTap,
                ),
            ],
          ),
          SizedBox(height: context.spacingInline),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: context.widgetValueStyle.copyWith(color: color),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              overflow: TextOverflow.ellipsis,
              style: context.widgetFooterStyle,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.radiusCard),
      child: content,
    );
  }
}

/// Standardized wrap layout for multiple [EarthMetricTile]s.
class EarthMetricGrid extends StatelessWidget {
  final List<Widget> metrics;
  final double spacing;
  final double runSpacing;

  const EarthMetricGrid({
    super.key,
    required this.metrics,
    this.spacing = 10,
    this.runSpacing = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: metrics,
    );
  }
}
