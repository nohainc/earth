import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

/// Standardized entity row / list item used for citizens, candidates, milestones, and items.
class EarthDataRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? secondarySubtitle;
  final InlineSpan? secondarySubtitleSpan;
  final String? tertiarySubtitle;
  final InlineSpan? tertiarySubtitleSpan;
  final double? subtitleFontSize;
  final double? secondarySubtitleFontSize;
  final bool allowSubtitleWrap;
  final Widget? trailing;
  final List<Widget>? badges;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isHighlight;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;

  const EarthDataRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.secondarySubtitle,
    this.secondarySubtitleSpan,
    this.tertiarySubtitle,
    this.tertiarySubtitleSpan,
    this.subtitleFontSize,
    this.secondarySubtitleFontSize,
    this.allowSubtitleWrap = false,
    this.trailing,
    this.badges,
    this.onTap,
    this.isSelected = false,
    this.isHighlight = false,
    this.showDivider = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final rowContent = Container(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: context.tokens.number('pageTopics.cardPadding', 12),
            vertical: context.tokens.number('spacing.control', 10),
          ),
      decoration: BoxDecoration(
        color: isSelected
            ? context.primaryColor.withValues(alpha: .15)
            : (isHighlight
                ? context.primaryColor.withValues(alpha: .08)
                : Colors.transparent),
        borderRadius: isHighlight ? BorderRadius.circular(8) : null,
        border: isHighlight
            ? Border.all(
                color: context.primaryColor.withValues(alpha: .45),
                width: 1,
              )
            : Border(
                bottom: showDivider
                    ? BorderSide(color: context.subtleBorderColor)
                    : BorderSide.none,
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: context.spacingTitleOffset),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: context.widgetValueStyle.copyWith(
                        color: isHighlight
                            ? context.primaryColor
                            : context.inkColor,
                        fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badges != null) ...badges!,
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.widgetFooterStyle.copyWith(
                      color: isHighlight ? context.primaryColor.withValues(alpha: 0.85) : null,
                      fontSize: subtitleFontSize,
                    ),
                    maxLines: allowSubtitleWrap ? null : 1,
                    overflow: allowSubtitleWrap ? TextOverflow.visible : TextOverflow.ellipsis,
                  ),
                ],
                if ((secondarySubtitle != null && secondarySubtitle!.isNotEmpty) ||
                    secondarySubtitleSpan != null) ...[
                  const SizedBox(height: 2),
                  if (secondarySubtitleSpan != null)
                    Text.rich(
                      secondarySubtitleSpan!,
                      style: context.widgetFooterStyle.copyWith(
                        color: isHighlight ? context.primaryColor.withValues(alpha: 0.75) : null,
                        fontSize: secondarySubtitleFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      secondarySubtitle!,
                      style: context.widgetFooterStyle.copyWith(
                        color: isHighlight ? context.primaryColor.withValues(alpha: 0.75) : null,
                        fontSize: secondarySubtitleFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if ((tertiarySubtitle != null && tertiarySubtitle!.isNotEmpty) ||
                    tertiarySubtitleSpan != null) ...[
                  const SizedBox(height: 2),
                  if (tertiarySubtitleSpan != null)
                    Text.rich(
                      tertiarySubtitleSpan!,
                      style: context.widgetFooterStyle.copyWith(
                        color: isHighlight ? context.primaryColor.withValues(alpha: 0.75) : null,
                        fontSize: secondarySubtitleFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      tertiarySubtitle!,
                      style: context.widgetFooterStyle.copyWith(
                        color: isHighlight ? context.primaryColor.withValues(alpha: 0.75) : null,
                        fontSize: secondarySubtitleFontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: context.spacingControl),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: rowContent,
      );
    }
    return rowContent;
  }
}

/// Standardized container for a list of [EarthDataRow]s with rounded corners and border.
class EarthDataList extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const EarthDataList({
    super.key,
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
