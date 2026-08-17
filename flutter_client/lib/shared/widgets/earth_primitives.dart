import 'package:flutter/material.dart';
import '../../app/theme.dart';

void showEarthInfoDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Map<String, String>> items,
}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: inkColor,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: mutedColor),
            ),
          ],
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['label'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: violetColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item['description'] ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          color: inkColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: violetColor)),
        ),
      ],
    ),
  );
}

/// Reusable presentation primitives shared by feature panels.
class EarthPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final double? width;
  final VoidCallback? onInfoTap;
  final String? infoTooltip;

  const EarthPanel({
    super.key,
    required this.title,
    required this.child,
    this.width,
    this.onInfoTap,
    this.infoTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label: title,
      child: SizedBox(
        width: width ?? double.infinity,
        child: Card(
          color: surfaceColor.withValues(alpha: .72),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: muted,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onInfoTap != null || infoTooltip != null)
                      IconButton(
                        icon: Icon(
                          Icons.info_outline,
                          size: 14,
                          color: mutedColor.withValues(alpha: .8),
                        ),
                        tooltip: infoTooltip ?? 'More information',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onInfoTap,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EarthMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final IconData? icon;
  final double? width;
  final String? hint;
  final VoidCallback? onInfoTap;

  const EarthMetric({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    this.icon,
    this.width,
    this.hint,
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final metricCard = SizedBox(
      width: width ?? 210,
      child: Card(
        color: surfaceColor.withValues(alpha: .72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(
                            icon,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hint != null || onInfoTap != null)
                    IconButton(
                      icon: Icon(
                        Icons.info_outline,
                        size: 13,
                        color: mutedColor.withValues(alpha: .7),
                      ),
                      tooltip: hint,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onInfoTap,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700, letterSpacing: -.5),
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      label: '$label: $value',
      child: metricCard,
    );
  }
}

class EarthErrorState extends StatelessWidget {
  final String message;
  final VoidCallback retry;

  const EarthErrorState(
      {super.key, required this.message, required this.retry});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: 'Error alert: $message',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: retry,
              child: const Text('RECONNECT'),
            ),
          ],
        ),
      );
}
