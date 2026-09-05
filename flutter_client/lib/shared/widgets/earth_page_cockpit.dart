import 'package:flutter/material.dart';
import '../design_system/earth_theme_context.dart';
import '../widgets/earth_primitives.dart';

/// A single telemetry metric item for display in [EarthPageCockpit].
class CockpitMetric {
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final String? subtitle;

  const CockpitMetric({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.subtitle,
  });
}

/// A standard executive page header / cockpit banner used across Earth views.
///
/// Features:
/// - **Top line**: Left-aligned category scope tag, glowing status dot + dynamic status pill, and info button.
/// - **Center section**: Prominently centered title, subtitle metadata line, and primary telemetry metrics.
/// - **Actions**: Optional action buttons or alert badges.
class EarthPageCockpit extends StatelessWidget {
  final String? tag;
  final String? status;
  final Color? statusColor;
  final String? infoTitle;
  final String? infoDescription;
  final String title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<CockpitMetric> metrics;
  final List<Widget> metricWidgets;
  final Widget? centerWidget;
  final List<Widget> actions;
  final VoidCallback? onInfoTap;

  const EarthPageCockpit({
    super.key,
    this.tag,
    this.status,
    this.statusColor,
    this.infoTitle,
    this.infoDescription,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleWidget,
    this.metrics = const [],
    this.metricWidgets = const [],
    this.centerWidget,
    this.actions = const [],
    this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStatusColor = statusColor ?? context.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: context.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context.surfaceColor,
            Color.alphaBlend(
              context.secondaryColor.withValues(alpha: 0.16),
              context.surfaceColor,
            ),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: context.secondaryColor.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. FIRST TOP LINE (LEFT-ALIGNED SCOPE TAG & STATUS)
          _buildTopLine(context, effectiveStatusColor),

          const SizedBox(height: 10),

          // 2. CENTERED MAIN TITLE
          titleWidget ??
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: context.mutedColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),

          // 3. CENTERED SUBTITLE
          if (subtitleWidget != null) ...[
            const SizedBox(height: 4),
            subtitleWidget!,
          ] else if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              softWrap: true,
              style: TextStyle(
                color: context.mutedColor,
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],

          // 4. CENTERED METRICS
          if (metrics.isNotEmpty || centerWidget != null) ...[
            const SizedBox(height: 14),
            _buildMetricsSection(context),
          ],

          // 5. ACTIONS (IF PRESENT)
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopLine(BuildContext context, Color effectiveStatusColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: effectiveStatusColor,
                  boxShadow: [
                    BoxShadow(
                      color: effectiveStatusColor.withValues(alpha: 0.7),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tag != null && status != null
                      ? '$tag · $status'
                      : (status ?? tag ?? 'STATUS'),
                  style: TextStyle(
                    color: effectiveStatusColor,
                    fontSize: 10,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (infoTitle != null || infoDescription != null || onInfoTap != null)
          IconButton(
            icon: Icon(
              Icons.info_outline,
              size: 14,
              color: context.mutedColor.withValues(alpha: .8),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Info',
            onPressed: onInfoTap ??
                () {
                  if (infoTitle != null) {
                    showEarthInfoDialog(
                      context,
                      title: infoTitle!,
                      description: infoDescription,
                    );
                  }
                },
          ),
      ],
    );
  }

  Widget _buildMetricsSection(BuildContext context) {
    if (centerWidget != null) {
      return centerWidget!;
    }
    if (metrics.isEmpty && metricWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...metrics.map((m) => _buildMetricItem(context, m)),
        ...metricWidgets,
      ],
    );
  }

  Widget _buildMetricItem(BuildContext context, CockpitMetric m) {
    final accentColor = m.color ?? context.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (m.icon != null) ...[
                Icon(m.icon, size: 10, color: accentColor),
                const SizedBox(width: 4),
              ],
              Text(
                m.label.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: context.mutedColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            m.value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accentColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
