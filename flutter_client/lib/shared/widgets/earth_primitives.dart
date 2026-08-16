import 'package:flutter/material.dart';

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
    return SizedBox(
      width: width,
      child: Card(
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
    );
  }
}

class EarthMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const EarthMetric({
    super.key,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      TextStyle(fontSize: 10, letterSpacing: 1, color: accent),
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
}

class EarthErrorState extends StatelessWidget {
  final String message;
  final VoidCallback retry;

  const EarthErrorState(
      {super.key, required this.message, required this.retry});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: retry, child: const Text('RECONNECT')),
        ],
      );
}
