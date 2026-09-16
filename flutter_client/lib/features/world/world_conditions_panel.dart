import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class WorldConditionsPanel extends StatelessWidget {
  final EarthState state;
  const WorldConditionsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final raw = state.json['worldConditions'];
    final snapshot =
        raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final status = snapshot['status']?.toString().toUpperCase();
    final available = status == 'AVAILABLE';
    final stale = status == 'STALE';
    final activeRaw = snapshot['activeConditions'];
    final conditions = activeRaw is List
        ? activeRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];
    final gameDay = snapshot['snapshotGameDay'];
    final rulesVersion = snapshot['rulesVersion']?.toString();
    final worldState = snapshot['worldState']?.toString() ?? 'UNKNOWN';
    final exposure = snapshot['playerExposure'] is Map
        ? Map<String, dynamic>.from(snapshot['playerExposure'] as Map)
        : const <String, dynamic>{};
    final territoryName = exposure['territoryName']?.toString() ??
        state.membership?['territory_name']?.toString() ??
        state.residency['territory_name']?.toString();
    final affectedCount = exposure['activeConditionCount'];

    final cockpit = EarthPageCockpit(
      status: !available
          ? 'CONDITIONS UNAVAILABLE'
          : stale
              ? 'STALE SNAPSHOT'
              : worldState == 'STABLE'
                  ? 'STABLE'
                  : 'ACTIVE CONDITIONS',
      statusColor:
          !available || stale ? context.warningColor : context.primaryColor,
      infoTitle: 'WORLD CONDITIONS',
      infoDescription:
          'World Conditions are authoritative temporary or persistent modifiers that affect gameplay across Earth. This page shows active conditions, affected systems, duration, and your local exposure. Missing data is never interpreted as normal.',
      title: 'WORLD CONDITIONS',
      subtitle: 'What is affecting the world and your House right now',
      metrics: [
        CockpitMetric(
            label: 'World State',
            value: available ? worldState.replaceAll('_', ' ') : 'UNAVAILABLE',
            icon: Icons.public_outlined,
            color: context.primaryColor),
        CockpitMetric(
            label: 'Active Conditions',
            value: available ? '${conditions.length}' : '—',
            icon: Icons.tune_outlined,
            color: conditions.isEmpty
                ? context.secondaryColor
                : context.warningColor),
        CockpitMetric(
            label: 'Updated Day',
            value: gameDay?.toString() ?? '—',
            icon: Icons.calendar_today_outlined,
            color: context.goldColor),
        CockpitMetric(
            label: 'Rules Version',
            value: rulesVersion ?? '—',
            icon: Icons.verified_outlined,
            color: context.primaryColor),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),
          if (!available)
            _buildUnavailable(context, stale: stale)
          else ...[
            EarthSection(
              title: 'ACTIVE CONDITIONS (${conditions.length})',
              showHeader: true,
              showSurface: false,
              child: conditions.isEmpty
                  ? _buildStableState(context, gameDay)
                  : Column(
                      children: conditions
                          .map((condition) =>
                              _buildConditionCard(context, condition))
                          .toList()),
            ),
            const SizedBox(height: 24),
            _buildExposure(context, territoryName, affectedCount),
            const SizedBox(height: 24),
            _buildTelemetryPlaceholder(context),
          ],
        ],
      ),
    );
  }

  Widget _buildUnavailable(BuildContext context, {required bool stale}) =>
      Container(
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.warningColor.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border:
              Border.all(color: context.warningColor.withValues(alpha: .35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_outlined, color: context.warningColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stale
                    ? 'Showing the last verified world-condition snapshot. A newer snapshot could not be confirmed.'
                    : 'The current world-condition snapshot could not be verified. No baseline or normal-state claims are shown.',
                style: context.bodyStyle,
              ),
            ),
          ],
        ),
      );

  Widget _buildStableState(BuildContext context, dynamic gameDay) => Container(
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(context.radiusCard),
          border:
              Border.all(color: context.primaryColor.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, color: context.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No active world conditions. The authoritative snapshot confirms that standard world rules currently apply${gameDay == null ? '' : ' on game day $gameDay'}.',
                style: context.bodyStyle,
              ),
            ),
          ],
        ),
      );

  Widget _buildConditionCard(
      BuildContext context, Map<String, dynamic> condition) {
    final source = condition['source'] is Map
        ? Map<String, dynamic>.from(condition['source'] as Map)
        : const <String, dynamic>{};
    final scope = condition['scope'] is Map
        ? Map<String, dynamic>.from(condition['scope'] as Map)
        : const <String, dynamic>{};
    final effects = condition['effects'] is List
        ? (condition['effects'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : <Map<String, dynamic>>[
            if (condition['effect'] is Map)
              Map<String, dynamic>.from(condition['effect'] as Map),
          ];
    final severity = condition['severity']?.toString().toUpperCase() ?? 'INFO';
    final impact = condition['impact']?.toString().toUpperCase() ?? 'NEUTRAL';
    final color = impact == 'BENEFICIAL'
        ? context.successColor
        : severity == 'CRITICAL' || impact == 'ADVERSE'
            ? context.warningColor
            : context.primaryColor;
    final title = (condition['title'] ?? condition['code'] ?? 'World Condition')
        .toString();
    final description = condition['description']?.toString() ?? '';
    final from = condition['effectiveFromGameDay'];
    final to = condition['effectiveToGameDay'];
    final period = to == null
        ? 'Active from day ${from ?? '—'}'
        : 'Day ${from ?? '—'} → Day $to';
    final scopeLabel =
        scope['type']?.toString().replaceAll('_', ' ').toUpperCase() ??
            'GLOBAL';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Icon(Icons.tune, color: color, size: 18),
              Text(title.toUpperCase(),
                  style: context.topicTitleStyle.copyWith(color: color)),
              EarthBadge(label: severity, customColor: color),
              EarthBadge(label: impact, customColor: color),
              EarthBadge(
                  label: scopeLabel, customColor: context.secondaryColor),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, style: context.bodyStyle),
          ],
          const SizedBox(height: 10),
          Text(period, style: context.captionStyle),
          if (effects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: effects
                  .map((effect) => _effectLabel(context, effect))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          Text('Source: ${source['type'] ?? 'SYSTEM'}',
              style: context.captionStyle.copyWith(color: context.mutedColor)),
        ],
      ),
    );
  }

  Widget _effectLabel(BuildContext context, Map<String, dynamic> effect) {
    final raw = effect['modifierBps'] ?? 0;
    final bps =
        raw is num ? raw.toDouble() : double.tryParse(raw.toString()) ?? 0;
    final sign = bps > 0 ? '+' : '';
    final percent = bps / 100;
    final value = percent == percent.roundToDouble()
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(2);
    final target =
        (effect['target'] ?? effect['targetKey'] ?? effect['type'] ?? 'Effect')
            .toString()
            .replaceAll('_', ' ')
            .toUpperCase();
    return Text('$target $sign$value%',
        style: context.bodyStyle.copyWith(fontWeight: FontWeight.w700));
  }

  Widget _buildExposure(
          BuildContext context, String? territoryName, dynamic affectedCount) =>
      EarthSection(
        title: 'YOUR EXPOSURE',
        showSurface: false,
        child: Container(
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(territoryName ?? 'Territory unavailable',
                  style: context.widgetValueStyle),
              const SizedBox(height: 6),
              Text(
                territoryName == null
                    ? 'Your primary Territory could not be resolved from the canonical snapshot.'
                    : '${affectedCount ?? '—'} active world conditions affect your Territory.',
                style: context.bodyStyle,
              ),
            ],
          ),
        ),
      );

  Widget _buildTelemetryPlaceholder(BuildContext context) => const EarthSection(
        title: 'WORLD TELEMETRY',
        showSurface: false,
        child: EarthEmptyState(
          message: 'No canonical planetary telemetry is currently published.',
          icon: Icons.insights_outlined,
        ),
      );
}
