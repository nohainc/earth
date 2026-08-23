import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/ui_style_tokens.dart';

void showEarthInfoDialog(
  BuildContext context, {
  required String title,
  String subtitle = '',
  String? description,
  List<Map<String, String>> items = const [],
}) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF141A24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 16, color: cyanAccentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: inkColor,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 10.5, color: mutedColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (description != null && description.isNotEmpty) ...[
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: mutedColor,
                    height: 1.45,
                  ),
                ),
                if (items.isNotEmpty) const SizedBox(height: 14),
              ],
              if (items.isNotEmpty)
                ...items.map(
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
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CLOSE',
              style: TextStyle(
                  color: cyanAccentColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11)),
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
  final double? height;
  final VoidCallback? onInfoTap;
  final String? infoTooltip;
  final String? infoDescription;
  final bool showSurface;
  final bool showTitle;
  final EdgeInsetsGeometry contentPadding;
  final bool helpAfterTitle;
  final Color? titleColor;

  const EarthPanel({
    super.key,
    required this.title,
    required this.child,
    this.width,
    this.height,
    this.onInfoTap,
    this.infoTooltip,
    this.infoDescription,
    this.showSurface = true,
    this.showTitle = true,
    this.contentPadding = const EdgeInsets.all(20),
    this.helpAfterTitle = false,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = UiStyleTokens.current;
    final muted = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final hasInfo =
        onInfoTap != null || infoTooltip != null || infoDescription != null;

    final content = Padding(
      padding: contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Row(
              mainAxisAlignment: helpAfterTitle
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(title,
                      style: TextStyle(
                        color: titleColor ?? muted,
                        fontSize: tokens.number('typography.topicTitle.size', 10),
                        letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.1),
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis),
                ),
                if (hasInfo) ...[
                  const SizedBox(width: 5),
                  IconButton(
                    icon: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: mutedColor.withValues(alpha: .8),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onInfoTap ??
                        (infoDescription != null
                            ? () => showEarthInfoDialog(context,
                                title: title, description: infoDescription!)
                            : null),
                  ),
                ],
              ],
            ),
            SizedBox(height: tokens.number('spacing.topic', 14)),
          ],
          child,
        ],
      ),
    );
    return Semantics(
      container: true,
      label: title,
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: showSurface
            ? Card(
                color: tokens.color('colors.surface', surfaceColor).withValues(alpha: .72),
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
                  side: const BorderSide(color: Colors.white12),
                ),
                child: content,
              )
            : content,
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
    final tokens = UiStyleTokens.current;
    final metricCard = SizedBox(
      width: width ?? 210,
      child: Card(
        color: tokens.color('colors.surface', surfaceColor).withValues(alpha: .72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
          side: const BorderSide(color: Colors.white12),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 18)),
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
                              fontSize: tokens.number('typography.caption.size', 10),
                              letterSpacing: tokens.number('typography.caption.letterSpacing', 1),
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
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.5),
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
