import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

enum EarthBadgeVariant {
  primary,
  secondary,
  success,
  warning,
  error,
  danger,
  neutral,
}

/// Standardized high-contrast status badge.
class EarthBadge extends StatelessWidget {
  final String label;
  final EarthBadgeVariant variant;
  final Color? customColor;
  final IconData? icon;
  final VoidCallback? onTap;

  const EarthBadge({
    super.key,
    required this.label,
    this.variant = EarthBadgeVariant.primary,
    this.customColor,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(context);
    final isCustomOrNeutral = variant == EarthBadgeVariant.neutral;

    final badgeWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isCustomOrNeutral
            ? Colors.white.withValues(alpha: .08)
            : color.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(
          color: isCustomOrNeutral
              ? Colors.white24
              : color.withValues(alpha: .35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: context.captionStyle.copyWith(color: color),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.radiusControl),
        child: badgeWidget,
      );
    }
    return badgeWidget;
  }

  Color _resolveColor(BuildContext context) {
    if (customColor != null) return customColor!;
    switch (variant) {
      case EarthBadgeVariant.primary:
        return context.primaryColor;
      case EarthBadgeVariant.secondary:
        return context.secondaryColor;
      case EarthBadgeVariant.success:
        return context.successColor;
      case EarthBadgeVariant.warning:
        return context.warningColor;
      case EarthBadgeVariant.error:
      case EarthBadgeVariant.danger:
        return context.errorColor;
      case EarthBadgeVariant.neutral:
        return context.mutedColor;
    }
  }
}

/// Standardized stat pill with label, value, and icon (used in headers and summaries).
class EarthStatusPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  const EarthStatusPill({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? context.primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacingInline,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: activeColor.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: context.iconSize, color: activeColor),
            const SizedBox(width: 5),
          ],
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: context.widgetTitleStyle,
                ),
                TextSpan(
                  text: value,
                  style: context.widgetValueStyle.copyWith(color: activeColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Standardized generation / entity circular avatar.
class EarthAvatar extends StatelessWidget {
  final String text;
  final String? subtext;
  final IconData? icon;
  final double size;
  final bool isHighlight;

  const EarthAvatar({
    super.key,
    this.text = '',
    this.subtext,
    this.icon,
    this.size = 44,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        isHighlight ? context.primaryColor : context.secondaryColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: activeColor.withValues(alpha: isHighlight ? .2 : .12),
        border: Border.all(color: activeColor, width: 1.5),
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, size: size * 0.45, color: activeColor)
            : Text(
                subtext != null ? '$text\n$subtext' : text,
                textAlign: TextAlign.center,
                style: context.captionStyle.copyWith(
                  color: activeColor,
                  height: 1.1,
                ),
              ),
      ),
    );
  }
}
