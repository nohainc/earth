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
    final allRaw = snapshot['conditions'];
    final allConditions = allRaw is List
        ? allRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
        : const <Map<String, dynamic>>[];
    final legacyActiveRaw = snapshot['activeConditions'];
    final affectingConditions = allConditions.isNotEmpty
        ? allConditions
            .where((condition) => condition['appliesToViewer'] == true)
            .toList()
        : legacyActiveRaw is List
            ? legacyActiveRaw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : const <Map<String, dynamic>>[];
    final otherConditions = allConditions
        .where((condition) => condition['appliesToViewer'] != true)
        .toList();
    final gameDay = snapshot['authoritativeGameDay'];
    final worldState = snapshot['worldState']?.toString() ?? 'UNKNOWN';
    final globalCount = snapshot['globalConditionCount'];
    final affectedCount = snapshot['viewerApplicableConditionCount'];

    final cockpit = EarthPageCockpit(
      status: !available
          ? 'CONDITIONS UNAVAILABLE'
          : worldState == 'STABLE'
              ? 'STABLE'
              : 'ACTIVE CONDITIONS',
      statusColor: !available ? context.warningColor : context.primaryColor,
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
            value: available ? '${affectingConditions.length}' : '—',
            icon: Icons.tune_outlined,
            color: affectingConditions.isEmpty
                ? context.secondaryColor
                : context.warningColor),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),
          if (!available)
            _buildUnavailable(context)
          else ...[
            EarthSection(
              title: _conditionSectionTitle('AFFECTING YOU', affectingConditions.length),
              showHeader: true,
              showSurface: false,
              child: affectingConditions.isEmpty
                  ? _buildStableState(context, gameDay)
                  : Column(
                      children: affectingConditions
                          .map((condition) =>
                              _buildConditionCard(context, condition, gameDay))
                          .toList()),
            ),
            if (otherConditions.isNotEmpty) ...[
              const SizedBox(height: 24),
              EarthSection(
                title: _conditionSectionTitle(
                    'OTHER ACTIVE CONDITIONS', otherConditions.length),
                showHeader: true,
                showSurface: false,
                child: Column(
                  children: otherConditions
                      .map((condition) =>
                          _buildConditionCard(context, condition, gameDay))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildExposure(context, affectedCount, globalCount),
          ],
        ],
      ),
    );
  }

  Widget _buildUnavailable(BuildContext context) =>
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
                'The current world-condition snapshot could not be verified. No baseline or normal-state claims are shown.',
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

  String _conditionSectionTitle(String label, int count) =>
      '$label ($count ${count == 1 ? 'CONDITION' : 'CONDITIONS'})';

  Widget _buildConditionCard(BuildContext context,
      Map<String, dynamic> condition, dynamic authoritativeGameDay) {
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
        : const <Map<String, dynamic>>[];
    final severity = condition['severity']?.toString().toUpperCase() ?? 'INFO';
    final color = severity == 'CRITICAL'
        ? context.warningColor
        : severity == 'WATCH'
            ? context.secondaryColor
            : context.primaryColor;
    final title = (condition['title'] ?? condition['code'] ?? 'World Condition')
        .toString();
    final description = condition['description']?.toString() ?? '';
    final from = condition['effectiveFromGameDay'];
    final to = condition['effectiveToGameDay'];
    final currentDay = _number(authoritativeGameDay);
    final endDay = _number(to);
    final remainingDays = to == null || currentDay == null || endDay == null
        ? null
        : (endDay - currentDay + 1).clamp(0, 999999);
    final period = to == null
        ? 'Effective from Day ${from ?? '—'} · No scheduled end'
        : 'Effective Day ${from ?? '—'} → Day $to';
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
          if (remainingDays != null) ...[
            const SizedBox(height: 4),
            Text(
              '$remainingDays ${remainingDays == 1 ? 'day' : 'days'} remaining',
              style: context.captionStyle.copyWith(color: context.mutedColor),
            ),
          ],
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
          Text(
            'Subsystem: ${_subsystemFor(effects)}',
            style: context.captionStyle.copyWith(color: context.mutedColor),
          ),
          const SizedBox(height: 4),
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
    final type = (effect['type'] ?? 'EFFECT').toString();
    final target =
        (effect['target'] ?? effect['targetKey'] ?? effect['type'] ?? 'Effect')
            .toString()
            .replaceAll('_', ' ')
            .toUpperCase();
    final effectName = type.replaceAll('_', ' ');
    return Text('$effectName · $target $sign$value%',
        style: context.bodyStyle.copyWith(fontWeight: FontWeight.w700));
  }

  String _subsystemFor(List<Map<String, dynamic>> effects) {
    final types = effects.map((effect) => effect['type']?.toString()).toSet();
    if (types.contains('LABOR_INDEX') || types.contains('CONSTRUCTION_INDEX')) {
      return 'CONSTRUCTION TIMING';
    }
    if (types.contains('CAPACITY_MULTIPLIER')) return 'SERVICE CAPACITY';
    if (types.contains('SUPPLY_MULTIPLIER')) return 'BUILDING OUTPUT';
    if (types.contains('DEMAND_MULTIPLIER')) {
      return 'BUILDING INPUTS / SERVICE DEMAND';
    }
    return 'UNSPECIFIED';
  }

  int? _number(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildExposure(
          BuildContext context, dynamic affectedCount, dynamic globalCount) =>
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
              Text('SERVER-RESOLVED EXPOSURE', style: context.widgetValueStyle),
              const SizedBox(height: 6),
              Text(
                '${affectedCount ?? '—'} of ${globalCount ?? '—'} active conditions apply to your current player scope.',
                style: context.bodyStyle,
              ),
            ],
          ),
        ),
      );

}
