import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Reusable presentation primitives shared by feature panels.
///
/// These widgets intentionally know nothing about routes, API clients,
/// PostgreSQL, or domain identifiers. Feature code supplies only display data
/// and callbacks.
class EarthPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const EarthPanel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final width =
        (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 360.0).toDouble();
    final muted = Theme.of(context).textTheme.bodySmall?.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label: title,
      child: SizedBox(
        width: width,
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
                Text(
                  title,
                  style: TextStyle(
                    color: muted,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
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
  final double? width;
  final String? hint;

  const EarthMetric({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
    this.width,
    this.hint,
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
                  if (hint != null)
                    Tooltip(
                      message: hint!,
                      preferBelow: false,
                      child: Icon(
                        Icons.info_outline,
                        size: 13,
                        color: mutedColor.withValues(alpha: .7),
                      ),
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
      child: hint != null
          ? Tooltip(
              message: hint!,
              preferBelow: false,
              child: metricCard,
            )
          : metricCard,
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
