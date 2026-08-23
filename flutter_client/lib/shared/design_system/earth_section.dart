import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

/// Standardized modal for showing contextual explanations and gameplay info.
void showEarthInfoModal(
  BuildContext context, {
  required String title,
  required String content,
  List<String>? bulletPoints,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.panelColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ctx.radiusPanel),
        side: BorderSide(color: ctx.primaryColor.withValues(alpha: .35)),
      ),
      title: Row(
        children: [
          Icon(Icons.info_outline, size: ctx.iconSize, color: ctx.primaryColor),
          SizedBox(width: ctx.spacingInline),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: ctx.topicTitleStyle.copyWith(color: ctx.primaryColor),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(content, style: ctx.bodyStyle),
              if (bulletPoints != null && bulletPoints.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...bulletPoints.map(
                  (pt) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ',
                            style: TextStyle(
                                color: ctx.primaryColor,
                                fontWeight: FontWeight.bold)),
                        Expanded(child: Text(pt, style: ctx.bodyStyle)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('CLOSE', style: ctx.controlStyle.copyWith(color: ctx.mutedColor)),
        ),
      ],
    ),
  );
}

/// Standardized Section and Topic container for all Earth panels.
class EarthSection extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  final String? infoDescription;
  final List<String>? infoBulletPoints;
  final VoidCallback? onInfoTap;
  final Widget? trailing;
  final bool showSurface;
  final bool showHeader;
  final EdgeInsetsGeometry? padding;
  final Color? surfaceColor;
  final Color? borderColor;

  const EarthSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.infoDescription,
    this.infoBulletPoints,
    this.onInfoTap,
    this.trailing,
    this.showSurface = true,
    this.showHeader = true,
    this.padding,
    this.surfaceColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasInfo = onInfoTap != null ||
        (infoDescription != null && infoDescription!.isNotEmpty) ||
        (infoBulletPoints != null && infoBulletPoints!.isNotEmpty);

    final header = showHeader
        ? Padding(
            padding: EdgeInsets.only(bottom: context.spacingInline),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: context.iconSize, color: context.primaryColor),
                        SizedBox(width: context.spacingInline),
                      ],
                      Flexible(
                        child: Text(
                          title,
                          style: context.topicTitleStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasInfo) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            Icons.info_outline,
                            size: context.iconSize,
                            color: context.primaryColor,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Info',
                          onPressed: onInfoTap ??
                              () => showEarthInfoModal(
                                    context,
                                    title: title,
                                    content: infoDescription ?? '',
                                    bulletPoints: infoBulletPoints,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          )
        : null;

    final contentWidget = showSurface
        ? Container(
            width: double.infinity,
            padding: padding ?? EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: surfaceColor ?? context.surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(
                color: borderColor ?? context.subtleBorderColor,
              ),
            ),
            child: child,
          )
        : child;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) header,
        contentWidget,
      ],
    );
  }
}
