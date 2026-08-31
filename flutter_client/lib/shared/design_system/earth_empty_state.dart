import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

/// Standardized empty placeholder widget.
class EarthEmptyState extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Widget? action;

  const EarthEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacingPage,
        vertical: context.spacingSection,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon ?? Icons.inbox_outlined,
            size: 32,
            color: context.mutedColor.withValues(alpha: .5),
          ),
          SizedBox(height: context.spacingInline),
          Text(
            message,
            style: context.bodyStyle.copyWith(color: context.mutedColor),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            SizedBox(height: context.spacingTitleOffset),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Standardized contextual alert banner for errors, successes, or notices.
class EarthAlertBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onClose;

  const EarthAlertBanner({
    super.key,
    required this.message,
    this.isError = false,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? context.errorColor : context.primaryColor;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: context.cardPadding,
        vertical: 6,
      ),
      color: color.withValues(alpha: .15),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 15,
          ),
          SizedBox(width: context.spacingInline),
          Expanded(
            child: Text(
              message,
              style: context.widgetFooterStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onClose != null)
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'OK',
                    style: context.widgetFooterStyle.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.close, size: 14, color: color),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
