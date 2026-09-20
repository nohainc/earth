import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/technology_models.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/design_system/building_function.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'technology_dialogs.dart';

BigInt? _parseTechnologyCreditUnits(dynamic value) =>
    value == null ? null : BigInt.tryParse(value.toString().trim());

String _formatTechnologyCreditUnits(dynamic value) => formatCreditUnits(value);

String _buildingBlueprintScope(Map<String, dynamic> blueprint) {
  final raw = (blueprint['ownership_scope'] ?? blueprint['ownership_class'] ?? '')
      .toString()
      .trim()
      .toUpperCase();
  return raw == 'PRIVATE' ? 'PRIVATE' : 'PUBLIC';
}

class CorporateBuildingResearchPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CorporateBuildingResearchPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<CorporateBuildingResearchPanel> createState() =>
      _CorporateBuildingResearchPanelState();
}

class _CorporateBuildingResearchPanelState
    extends State<CorporateBuildingResearchPanel> {
  int _selectedScope = 0; // 0 = ALL, 1 = PRIVATE, 2 = PUBLIC
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Research progress is a persisted settlement/read-model fact. The client
  /// deliberately does not infer it from wall-clock time or a fallback
  /// duration between refreshes.
  double? _authoritativeResearchProgress(Map<String, dynamic> project) {
    final raw = project['progressBps'];
    if (raw == null) return null;
    final parsed = double.tryParse(raw.toString());
    return parsed == null ? null : (parsed / 100).clamp(0.0, 100.0);
  }

  bool _hasAuthoritativeResearchBlueprint(Map<String, dynamic> blueprint) {
    final type = (blueprint['building_type'] ?? blueprint['type'])?.toString();
    return type != null && type.isNotEmpty;
  }

  String _buildingAssetPath(String type) {
    return EarthBuildingMeta.getAssetPath(type);
  }

  Widget _buildBuildingImage(BuildContext context, String type) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radiusControl),
      child: Image.asset(
        _buildingAssetPath(type),
        width: 92,
        height: 92,
        cacheWidth: 256,
        cacheHeight: 256,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 92,
          height: 92,
          color: context.subtleBorderColor,
          child: Icon(Icons.apartment_outlined, color: context.mutedColor),
        ),
      ),
    );
  }

  String _formatDecimal(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    final fixed = val.toStringAsFixed(2);
    if (fixed.endsWith('.00')) {
      return fixed.substring(0, fixed.length - 3);
    }
    return fixed;
  }

  BigInt? _creditUnits(dynamic value) =>
      value == null ? null : BigInt.tryParse(value.toString().trim());

  String _credit(dynamic value) => formatCreditUnits(value);

  @override
  Widget build(BuildContext context) {
    final data = widget.state.corporationBuildingResearch;
    final corporationId = data['corporationId']?.toString();
    final isCorporationMember =
        corporationId != null && corporationId.isNotEmpty;

    final projects =
        data['projects'] is List ? data['projects'] as List : const [];
    final unlocks =
        data['unlocks'] is List ? data['unlocks'] as List : const [];

    final activeProjects = projects
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList();

    final unlockedTiers = <String, int>{};
    for (final raw in unlocks) {
      if (raw is! Map) continue;
      final u = Map<String, dynamic>.from(raw);
      final type = u['building_type']?.toString();
      final tier = asIntOr(u['tier'], 1);
      if (type != null && type.isNotEmpty) {
        final current = unlockedTiers[type] ?? 1;
        if (tier > current) unlockedTiers[type] = tier;
      }
    }

    final activeProjectMap = <String, Map<String, dynamic>>{};
    for (final p in activeProjects) {
      final type = p['building_type']?.toString();
      if (type != null && type.isNotEmpty) {
        activeProjectMap[type] = p;
      }
    }

    final blueprintCatalogMap = <String, Map<String, dynamic>>{};
    for (final raw in widget.state.buildingCatalog) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final type = item['building_type']?.toString();
      if (type != null && type.isNotEmpty) {
        blueprintCatalogMap.putIfAbsent(type, () => item);
      }
    }

    final allBlueprints = blueprintCatalogMap.values
        .where(_hasAuthoritativeResearchBlueprint)
        .toList();

    final privateCount = allBlueprints
        .where((b) => _buildingBlueprintScope(b) == 'PRIVATE')
        .length;
    final publicCount = allBlueprints
        .where((b) => _buildingBlueprintScope(b) == 'PUBLIC')
        .length;

    final filteredBlueprints = allBlueprints.where((b) {
      final scope = _buildingBlueprintScope(b);
      if (_selectedScope == 1 && scope != 'PRIVATE') return false;
      if (_selectedScope == 2 && scope != 'PUBLIC') return false;
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = (b['name']?.toString() ?? '').toLowerCase();
        final category = (b['category']?.toString() ?? '').toLowerCase();
        final type = (b['building_type']?.toString() ?? '').toLowerCase();
        if (!name.contains(q) && !category.contains(q) && !type.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    filteredBlueprints.sort((a, b) {
      final aType = a['building_type']?.toString() ?? '';
      final bType = b['building_type']?.toString() ?? '';
      final aTier = (unlockedTiers[aType] ?? 1) + 1;
      final bTier = (unlockedTiers[bType] ?? 1) + 1;
      final aCost = _creditUnits(a['research_credit_units'] ??
              a['research_credit_cost_units'] ??
              a['researchCost'] ??
              a['research_cost']) ??
          BigInt.zero;
      final bCost = _creditUnits(b['research_credit_units'] ??
              b['research_credit_cost_units'] ??
              b['researchCost'] ??
              b['research_cost']) ??
          BigInt.zero;
      final costCmp = aCost.compareTo(bCost);
      if (costCmp != 0) return costCmp;
      return (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? '');
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildScopeFilterButton(
              context,
              index: 0,
              label: 'ALL BLUEPRINTS',
              count: allBlueprints.length,
              icon: Icons.dashboard_customize_outlined,
            ),
            _buildScopeFilterButton(
              context,
              index: 1,
              label: 'PRIVATE SECTOR',
              count: privateCount,
              icon: Icons.storefront_outlined,
            ),
            _buildScopeFilterButton(
              context,
              index: 2,
              label: 'PUBLIC',
              count: publicCount,
              icon: Icons.account_balance_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),

        EarthSearchInput(
          controller: _searchController,
          hintText: 'Search building blueprints by name or category...',
          fontSize: 12.5,
          onChanged: (val) => setState(() => _searchQuery = val),
          onClear: () => setState(() {
            _searchController.clear();
            _searchQuery = '';
          }),
        ),
        const SizedBox(height: 16),

        if (filteredBlueprints.isEmpty)
          const EarthEmptyState(
            icon: Icons.search_off_outlined,
            message: 'No building blueprints match your search or filter.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columnsCount = constraints.maxWidth >= 1150
                  ? 3
                  : (constraints.maxWidth >= 700 ? 2 : 1);
              final cards = filteredBlueprints
                  .map<Widget Function({bool fillHeight})>((bp) {
                final type = bp['building_type']?.toString() ?? '';
                final name = bp['name']?.toString() ?? type;
                final ownership = _buildingBlueprintScope(bp);

                final currentTier = unlockedTiers[type] ?? 1;
                final targetTier = currentTier + 1;

                final baseCostUnits = _creditUnits(bp['construction_credit_units'] ??
                        bp['cost_credits']) ??
                    BigInt.zero;
                final slots =
                    asInt(bp['slot_footprint'] ?? bp['slotFootprint']) ?? 1;
                final nextResearchCostUnits = _creditUnits(bp['research_credit_units'] ??
                        bp['research_credit_cost_units'] ??
                        bp['researchCost'] ??
                        bp['research_cost']) ??
                    BigInt.zero;
                final durationDays = asInt(bp['research_duration_game_days'] ??
                        bp['research_duration_days'] ??
                        bp['duration_days'] ??
                        bp['construction_days']) ??
                    1;

                final activeProject = activeProjectMap[type];
                final isResearching = activeProject != null;
                final projectProgress = isResearching
                    ? _authoritativeResearchProgress(activeProject)
                    : null;
                final category =
                    (bp['category']?.toString() ?? 'commercial').toUpperCase();
                final desc =
                    (bp['description'] ?? bp['catalog_description'] ?? '')
                        .toString();
                final purpose = buildingEconomicFunctionFromJson(bp);
                final publicBenefit = bp['publicBenefit']?.toString();

                // Show next-tier economics only when the catalog publishes them.
                final costCreditsCur = baseCostUnits;
                final costCreditsNext =
                    _creditUnits(bp['next_construction_credit_units']);
                final matBase = 0.0;
                final compBase = 0.0;
                final computeBase = 0.0;

                final upkeepInputs =
                    <(IconData, Color, String, double, double)>[];

                final outputItems =
                    <(IconData, Color, String, double, double)>[];

                // Operating economics are read from the catalog, never scaled locally.
                final opCreditsBase = _creditUnits(
                        bp['operating_credit_units'] ?? bp['operating_credits']) ??
                    BigInt.zero;
                final opCreditsNext = _creditUnits(
                    bp['next_operating_credit_units'] ??
                        bp['next_operating_credits']);
                final opEnergyBase = 0.0;
                final opFoodBase = 0.0;
                final opMaterialsBase = 0.0;
                final opComponentsBase = 0.0;
                final opComputeBase = 0.0;

                final hasOperating = opCreditsBase > BigInt.zero ||
                    opEnergyBase > 0 ||
                    opFoodBase > 0 ||
                    opMaterialsBase > 0 ||
                    opComponentsBase > 0 ||
                    opComputeBase > 0;

                final constructionMinutes = asDouble(
                        bp['construction_minutes'] ??
                            bp['effective_construction_minutes']) ??
                    1440.0;
                final tierDaysCurrent = (constructionMinutes / 1440).ceil();
                final nextConstructionMinutes =
                    asDouble(bp['next_construction_minutes']);
                final tierDaysNext = nextConstructionMinutes == null
                    ? null
                    : (nextConstructionMinutes / 1440).ceil();

                Widget buildCardBody({bool fillHeight = false}) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(context.cardPadding),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(context.radiusCard),
                      border: Border.all(
                        color: isResearching
                            ? cyanAccentColor.withValues(alpha: .5)
                            : context.subtleBorderColor,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize:
                          fillHeight ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBuildingImage(context, type),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: context.widgetTitleStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      EarthBadge(
                                        label:
                                            'BUILDING TIER $currentTier -> $targetTier',
                                        variant: EarthBadgeVariant.primary,
                                      ),
                                      EarthBadge(
                                        label:
                                            '$slots ${slots == 1 ? "SPACE" : "SPACES"}',
                                        variant: EarthBadgeVariant.neutral,
                                      ),
                                      EarthBadge(
                                        label: category,
                                        variant: EarthBadgeVariant.neutral,
                                      ),
                                    ],
                                  ),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      desc,
                                      style: context.bodyStyle.copyWith(
                                        fontSize: 12,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    'Economic Function: $purpose',
                                    style: context.widgetFooterStyle,
                                  ),
                                  if (publicBenefit != null &&
                                      publicBenefit.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text('PUBLIC SERVICE',
                                            style: context.captionStyle),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.star_outline_rounded,
                                            size: 14,
                                            color: Colors.purpleAccent),
                                        Text(publicBenefit,
                                            style: context.widgetFooterStyle
                                                .copyWith(
                                              color: Colors.purpleAccent,
                                            )),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Row 1: authoritative construction cost and duration.
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('COST', style: context.captionStyle),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 14,
                              color: EarthResourceColors.credits,
                            ),
                            Text(
                              costCreditsNext == null
                                  ? _credit(costCreditsCur)
                                  : '${_credit(costCreditsCur)} -> ${_credit(costCreditsNext)}',
                              style: context.widgetFooterStyle,
                            ),
                            if (matBase > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                EarthResourceMeta.forCommodity('materials')
                                    .icon,
                                size: 14,
                                color: EarthResourceColors.materials,
                              ),
                              Text(
                                '${formatWholeNumber(matBase)} -> ${formatWholeNumber(matBase)}',
                                style: context.widgetFooterStyle,
                              ),
                            ],
                            if (compBase > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                EarthResourceMeta.forCommodity('components')
                                    .icon,
                                size: 14,
                                color: EarthResourceColors.components,
                              ),
                              Text(
                                '${formatWholeNumber(compBase)} -> ${formatWholeNumber(compBase)}',
                                style: context.widgetFooterStyle,
                              ),
                            ],
                            if (computeBase > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                EarthResourceMeta.forCommodity('compute').icon,
                                size: 14,
                                color: EarthResourceColors.compute,
                              ),
                              Text(
                                '${formatWholeNumber(computeBase)} -> ${formatWholeNumber(computeBase)}',
                                style: context.widgetFooterStyle,
                              ),
                            ],
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Colors.amber,
                            ),
                            Text(
                              tierDaysNext == null
                                  ? '${tierDaysCurrent}d'
                                  : '${tierDaysCurrent}d -> ${tierDaysNext}d',
                              style: context.widgetFooterStyle,
                            ),
                          ],
                        ),

                        // Row 2: DAILY UPKEEP (+12%)
                        if (upkeepInputs.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('DAILY UPKEEP', style: context.captionStyle),
                              const SizedBox(width: 2),
                              ...upkeepInputs.expand((input) => <Widget>[
                                    Icon(input.$1, size: 14, color: input.$2),
                                    Text(
                                      '${_formatDecimal(input.$4)} -> ${_formatDecimal(input.$5)} ${input.$3}',
                                      style: context.widgetFooterStyle,
                                    ),
                                  ]),
                            ],
                          ),
                        ],

                        // Row 3: OUTPUT (+25%)
                        if (outputItems.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('OUTPUT', style: context.captionStyle),
                              const SizedBox(width: 2),
                              ...outputItems.expand((out) => <Widget>[
                                    Icon(out.$1, size: 14, color: out.$2),
                                    Text(
                                      out.$3 == 'CREDITS'
                                          ? '${formatWholeNumber(out.$4)} -> ${formatWholeNumber(out.$5)} C / DAY'
                                          : '${_formatDecimal(out.$4)} -> ${_formatDecimal(out.$5)} ${out.$3} / DAY',
                                      style: context.widgetFooterStyle,
                                    ),
                                  ]),
                            ],
                          ),
                        ],

                        // Row 4: OPERATING (+12%)
                        if (hasOperating) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('OPERATING', style: context.captionStyle),
                              const SizedBox(width: 2),
                              if (opCreditsBase > BigInt.zero) ...[
                                const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 14,
                                  color: EarthResourceColors.credits,
                                ),
                                Text(
                                  opCreditsNext == null
                                      ? '-${_credit(opCreditsBase)} / DAY'
                                      : '-${_credit(opCreditsBase)} -> -${_credit(opCreditsNext)} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opEnergyBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('energy').icon,
                                  size: 14,
                                  color: EarthResourceColors.energy,
                                ),
                                Text(
                                  '-${_formatDecimal(opEnergyBase)} -> -${_formatDecimal(opEnergyBase)} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opMaterialsBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('materials')
                                      .icon,
                                  size: 14,
                                  color: EarthResourceColors.materials,
                                ),
                                Text(
                                  '-${_formatDecimal(opMaterialsBase)} -> -${_formatDecimal(opMaterialsBase)} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opComponentsBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('components')
                                      .icon,
                                  size: 14,
                                  color: EarthResourceColors.components,
                                ),
                                Text(
                                  '-${_formatDecimal(opComponentsBase)} -> -${_formatDecimal(opComponentsBase)} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opComputeBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('compute')
                                      .icon,
                                  size: 14,
                                  color: EarthResourceColors.compute,
                                ),
                                Text(
                                  '-${_formatDecimal(opComputeBase)} -> -${_formatDecimal(opComputeBase)} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                            ],
                          ),
                        ],

                        if (fillHeight) const Spacer(),
                        const SizedBox(height: 10),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color:
                              context.subtleBorderColor.withValues(alpha: .6),
                        ),
                        const SizedBox(height: 10),

                        // Action Bar: R&D cost / duration & Centered Research Button or Progress
                        if (isResearching) ...[
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: projectProgress == null
                                        ? null
                                        : projectProgress / 100,
                                    minHeight: 6,
                                    backgroundColor:
                                        context.inkColor.withValues(alpha: .1),
                                    valueColor: const AlwaysStoppedAnimation(
                                        cyanAccentColor),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cyanAccentColor.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: cyanAccentColor.withValues(
                                          alpha: .4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.science_outlined,
                                        size: 13, color: cyanAccentColor),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'R&D IN PROGRESS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: cyanAccentColor,
                                      ),
                                    ),
                                    Text(
                                      ': ${projectProgress == null ? '—' : '${projectProgress.toStringAsFixed(0)}%'}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: cyanAccentColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Builder(
                            builder: (context) {
                              final isPrivate = ownership == 'PRIVATE';
                              final canRequestResearch =
                                  isCorporationMember && nextResearchCostUnits > BigInt.zero;
                              final isButtonDisabled =
                                  widget.busy || !canRequestResearch;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'COST',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: context.mutedColor,
                                          letterSpacing: .5,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 14,
                                        color: canRequestResearch
                                            ? EarthResourceColors.credits
                                            : context.dangerColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _credit(nextResearchCostUnits),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: canRequestResearch
                                              ? context.inkColor
                                              : context.dangerColor,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Icon(
                                        Icons.timer_outlined,
                                        size: 14,
                                        color: cyanAccentColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$durationDays ${durationDays == 1 ? "day" : "days"} R&D',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: context.inkColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: EarthButton(
                                        label: isPrivate
                                            ? 'START CORPORATION R&D · BUILDING TIER $targetTier'
                                            : 'PROPOSE PUBLIC R&D · BUILDING TIER $targetTier',
                                        icon: isPrivate
                                            ? Icons.science_outlined
                                            : Icons.how_to_vote_outlined,
                                        variant: isButtonDisabled
                                            ? EarthButtonVariant.neutral
                                            : EarthButtonVariant.primary,
                                        height: 32,
                                        onPressed: isButtonDisabled
                                            ? null
                                            : () async {
                                                Map<String, dynamic> quote =
                                                    const {};
                                                try {
                                                  quote = await const EarthApi()
                                                      .quoteCorporationBuildingResearch(
                                                          type);
                                                } catch (_) {}
                                                if (!context.mounted) return;
                                                await _confirmAndStartResearch(
                                                  context,
                                                  type: type,
                                                  name: name,
                                                  corporationId: corporationId,
                                                  targetTier: targetTier,
                                                  currentTier: currentTier,
                                                  costCredits:
                                                      nextResearchCostUnits.toString(),
                                                  durationDays: durationDays,
                                                  costCreditsCur:
                                                      costCreditsCur,
                                                  costCreditsNext:
                                                      costCreditsNext,
                                                  upkeepInputs: upkeepInputs,
                                                  outputItems: outputItems,
                                                  opCreditsBase: opCreditsBase,
                                                  opCreditsNext: opCreditsNext,
                                                  opEnergyBase: opEnergyBase,
                                                  opMaterialsBase:
                                                      opMaterialsBase,
                                                  opComponentsBase:
                                                      opComponentsBase,
                                                  opComputeBase: opComputeBase,
                                                  tierDaysCurrent:
                                                      tierDaysCurrent,
                                                  tierDaysNext: tierDaysNext,
                                                  serverQuote: quote,
                                                );
                                              },
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return buildCardBody;
              }).toList();

              if (columnsCount <= 1) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards.map((c) => c(fillHeight: false)).toList(),
                );
              }

              final rowWidgets = <Widget>[];
              for (var i = 0; i < cards.length; i += columnsCount) {
                final rowCards = <Widget>[];
                for (var c = 0; c < columnsCount; c++) {
                  final idx = i + c;
                  if (idx < cards.length) {
                    rowCards.add(Expanded(child: cards[idx](fillHeight: true)));
                  } else {
                    rowCards.add(const Expanded(child: SizedBox.shrink()));
                  }
                }
                rowWidgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 0),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var c = 0; c < rowCards.length; c++) ...[
                            if (c > 0) const SizedBox(width: 12),
                            rowCards[c],
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rowWidgets,
              );
            },
          ),
        const SizedBox(height: 16),

        // UNLOCK HISTORY
        if (unlocks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('RESEARCHED UNLOCK HISTORY',
              style: context.widgetFooterStyle.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              )),
          const SizedBox(height: 6),
          ...unlocks.map((raw) {
            final item = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{};
            final type = item['building_type']?.toString() ?? '';
            final name = (item['catalog_name'] ??
                    blueprintCatalogMap[type]?['name'] ??
                    type)
                .toString();
            final tier = item['tier']?.toString();
            return EarthDataRow(
              leading: const Icon(Icons.lock_open_outlined,
                  size: 16, color: cyanAccentColor),
              title: name,
              subtitle: tier == null
                  ? 'Building Tier unlocked'
                  : 'Building Tier $tier unlocked',
              badges: const [
                Chip(
                    label: Text('BUILDING TIER UNLOCKED'),
                    visualDensity: VisualDensity.compact)
              ],
              padding: const EdgeInsets.symmetric(vertical: 5),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildScopeFilterButton(
    BuildContext context, {
    required int index,
    required String label,
    required int count,
    required IconData icon,
  }) {
    final isSelected = _selectedScope == index;
    return InkWell(
      onTap: () {
        EarthAudioEngine.instance.playClick();
        setState(() => _selectedScope = index);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: .15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                isSelected ? context.primaryColor : context.subtleBorderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? context.primaryColor : context.mutedColor,
            ),
            const SizedBox(width: 5),
            Text(
              '$label ($count)',
              style: context.controlStyle.copyWith(
                color: isSelected ? context.primaryColor : context.mutedColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndStartResearch(
    BuildContext context, {
    required String type,
    required String name,
    required int targetTier,
    required int currentTier,
    required String costCredits,
    required int durationDays,
    required BigInt costCreditsCur,
    required BigInt? costCreditsNext,
    required List<(IconData, Color, String, double, double)> upkeepInputs,
    required List<(IconData, Color, String, double, double)> outputItems,
    required BigInt opCreditsBase,
    required BigInt? opCreditsNext,
    required double opEnergyBase,
    required double opMaterialsBase,
    required double opComponentsBase,
    required double opComputeBase,
    required String corporationId,
    required int tierDaysCurrent,
    required int? tierDaysNext,
    required Map<String, dynamic> serverQuote,
  }) async {
    EarthAudioEngine.instance.playClick();
    final authorization = serverQuote['authorization'] is Map
        ? Map<String, dynamic>.from(serverQuote['authorization'] as Map)
        : const <String, dynamic>{};
    final blueprintScope =
        serverQuote['blueprintScope']?.toString().toUpperCase() ?? '';
    final isPrivate = blueprintScope == 'PRIVATE';
    final canStart = authorization['canStart'] == true;
    final canPropose = authorization['canPropose'] == true;
    final quote = serverQuote['quote'] is Map
        ? Map<String, dynamic>.from(serverQuote['quote'] as Map)
        : const <String, dynamic>{};
    final quotedCost =
        _creditUnits(quote['researchCostUnits']);
    final quotedDuration =
        int.tryParse(quote['durationDays']?.toString() ?? '');
    final effectiveCost = quotedCost?.toString() ?? costCredits;
    final effectiveDuration = quotedDuration ?? durationDays;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: cyanAccentColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: cyanAccentColor.withValues(alpha: .4)),
              ),
              child: Icon(
                isPrivate ? Icons.science_outlined : Icons.how_to_vote_outlined,
                size: 20,
                color: cyanAccentColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPrivate ? 'Start Corporation R&D' : 'Propose Public R&D',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  Text(
                    '$name · Building Tier $currentTier → Building Tier $targetTier',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.mutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPrivate
                    ? 'This Corporation-funded research will charge ${_credit(effectiveCost)} from the Corporation operations account to research Building Tier $targetTier.'
                    : 'This public blueprint research requires Corporation Governance approval. If passed, ${_credit(effectiveCost)} will be funded from the Corporation operations account to research Building Tier $targetTier.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: context.inkColor,
                ),
              ),
              const SizedBox(height: 14),

              // Overview Grid
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('Research Cost:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: EarthResourceColors.credits),
                        const SizedBox(width: 4),
                        Text(_credit(effectiveCost),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Project Duration:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.timer_outlined,
                            size: 14, color: cyanAccentColor),
                        const SizedBox(width: 4),
                        Text(
                            '$effectiveDuration ${effectiveDuration == 1 ? "Day" : "Days"}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Real Upgraded Values Section
              Text(
                'BLUEPRINT EVOLUTION (REAL VALUES)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: context.mutedColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Column(
                  children: [
                    // Construction Cost
                    Row(
                      children: [
                        Text('Build Cost:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 13, color: EarthResourceColors.credits),
                        const SizedBox(width: 4),
                        Text(
                          costCreditsNext == null
                              ? _credit(costCreditsCur)
                              : '${_credit(costCreditsCur)} → ${_credit(costCreditsNext)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),

                    // Construction Time
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Construction Time:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.timer_outlined,
                            size: 13, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          tierDaysNext == null
                              ? '$tierDaysCurrent d'
                              : '$tierDaysCurrent d → $tierDaysNext d',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),

                    // Output
                    if (outputItems.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...outputItems.map((out) {
                        final curStr = out.$3 == 'CREDITS' ||
                                out.$3 == 'CRD' ||
                                out.$3 == 'C'
                            ? formatWholeNumber(out.$4)
                            : _formatDecimal(out.$4);
                        final nextStr = out.$3 == 'CREDITS' ||
                                out.$3 == 'CRD' ||
                                out.$3 == 'C'
                            ? formatWholeNumber(out.$5)
                            : _formatDecimal(out.$5);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text('Daily Output:',
                                  style: TextStyle(
                                      fontSize: 12, color: context.mutedColor)),
                              const Spacer(),
                              Icon(out.$1, size: 13, color: out.$2),
                              const SizedBox(width: 4),
                              Text(
                                '$curStr → $nextStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: context.mutedColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Upkeep
                    if (upkeepInputs.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...upkeepInputs.map((input) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text('Daily Upkeep:',
                                  style: TextStyle(
                                      fontSize: 12, color: context.mutedColor)),
                              const Spacer(),
                              Icon(input.$1, size: 13, color: input.$2),
                              const SizedBox(width: 4),
                              Text(
                                '${_formatDecimal(input.$4)} → ${_formatDecimal(input.$5)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: context.mutedColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Operating expenses
                    if (opCreditsBase > BigInt.zero) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('Operating Expenses:',
                              style: TextStyle(
                                  fontSize: 12, color: context.mutedColor)),
                          const Spacer(),
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 13, color: EarthResourceColors.credits),
                          const SizedBox(width: 4),
                          Text(
                            opCreditsNext == null
                                ? '-${_credit(opCreditsBase)}'
                                : '-${_credit(opCreditsBase)} → -${_credit(opCreditsNext)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.mutedColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext, false),
          ),
          EarthButton(
            label: isPrivate ? 'CONFIRM CORPORATION R&D' : 'SUBMIT V5 PROPOSAL',
            icon:
                isPrivate ? Icons.science_outlined : Icons.how_to_vote_outlined,
            variant: (!canStart && !canPropose)
                ? EarthButtonVariant.neutral
                : EarthButtonVariant.primary,
            onPressed: (!canStart && !canPropose)
                ? null
                : () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (isPrivate && canStart) {
        await widget.action(
            () => const EarthApi().startCorporationBuildingResearch(type));
      } else if (!isPrivate && canPropose) {
        final startsGameDay = int.tryParse(
              quote['startsGameDay']?.toString() ?? '',
            ) ??
            0;
        await widget.action(() async {
          await const EarthApi().proposeCorporationBuildingResearch(
            corporationId: corporationId,
            buildingType: type,
            targetTier: targetTier,
            effectiveFromGameDay: startsGameDay,
            title: 'Research $name Building Tier $targetTier',
            body:
                'Authorize Corporation-funded research for the public $name Building Tier $targetTier blueprint.',
          );
          return const EarthApi().world();
        });
      }
    }
  }
}

class TechnologyOutcomePanel extends StatefulWidget {
  final EarthState state;

  const TechnologyOutcomePanel({super.key, required this.state});

  @override
  State<TechnologyOutcomePanel> createState() => _TechnologyOutcomePanelState();
}

class _TechnologyOutcomePanelState extends State<TechnologyOutcomePanel> {
  String _selectedBranch = 'ALL';
  String _selectedStatus = 'ALL';
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.state.technologyWorkspace.catalog;
    final branches = <String>[];
    for (final item in catalog) {
      final branch = item.category.replaceAll('_', ' ');
      if (!branches.contains(branch)) branches.add(branch);
    }
    final projectByTechnology = <String, CorporationResearchProject>{
      for (final project in widget.state.technologyWorkspace.projects)
        if (project.targetType.toUpperCase() == 'TECHNOLOGY')
          project.targetId: project,
    };
    final visibleItems = catalog
        .where((item) {
          final branch = item.category.replaceAll('_', ' ');
          final status = item.viewerStatus.toUpperCase();
          final query = _searchQuery.trim().toLowerCase();
          if (_selectedBranch != 'ALL' && branch != _selectedBranch) {
            return false;
          }
          if (_selectedStatus != 'ALL' && status != _selectedStatus) {
            return false;
          }
          if (query.isNotEmpty &&
              !item.name.toLowerCase().contains(query) &&
              !item.code.toLowerCase().contains(query) &&
              !item.description.toLowerCase().contains(query) &&
              !branch.toLowerCase().contains(query)) {
            return false;
          }
          return true;
        })
        .toList()
      ..sort((a, b) {
        final aCost = BigInt.tryParse(a.researchCostUnits) ?? BigInt.zero;
        final bCost = BigInt.tryParse(b.researchCostUnits) ?? BigInt.zero;
        final costCmp = aCost.compareTo(bCost);
        if (costCmp != 0) return costCmp;
        return a.name.compareTo(b.name);
      });
    final adoptedNames = widget.state.technologyWorkspace.adoptedCodes.toSet();
    final researchBudget = widget.state.technologyWorkspace.researchBudget;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CAPABILITY OUTCOMES', style: context.topicTitleStyle),
      const SizedBox(height: 5),
      const Text(
          'Browse Corporation-funded technology capabilities. Costs, access, status, and completion timing come from authoritative Corporation research data.',
          style: TextStyle(color: mutedColor, fontSize: 10.5)),
      const SizedBox(height: 12),
      if (researchBudget != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 15, color: cyanAccentColor),
              const SizedBox(width: 7),
              const Text('CORPORATION RESEARCH BUDGET',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(formatCreditUnits(researchBudget.availableUnits),
                  style: const TextStyle(
                      color: cyanAccentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 4),
              const Text('AVAILABLE',
                  style: TextStyle(color: mutedColor, fontSize: 8)),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      const Text('RESEARCH PATHS',
          style: TextStyle(
              color: mutedColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)),
      const SizedBox(height: 8),
      EarthSearchInput(
        controller: _searchController,
        hintText: 'Search technologies by name, code, domain, or effect...',
        fontSize: 12,
        onChanged: (value) => setState(() => _searchQuery = value),
        onClear: () => setState(() {
          _searchController.clear();
          _searchQuery = '';
        }),
      ),
      const SizedBox(height: 10),
      const Text('DOMAIN FILTER',
          style: TextStyle(
              color: mutedColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: ['ALL', ...branches]
            .map((branch) => OutlinedButton(
                  onPressed: () => setState(() => _selectedBranch = branch),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    side: BorderSide(
                        color: (_selectedBranch == branch
                                ? cyanAccentColor
                                : violetColor)
                            .withValues(alpha: .55)),
                    backgroundColor: (_selectedBranch == branch
                            ? cyanAccentColor
                            : surfaceColor)
                        .withValues(alpha: .18),
                  ),
                  child: Text(branch,
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ))
            .toList(),
      ),
      const SizedBox(height: 10),
      const Text('STATUS FILTER',
          style: TextStyle(
              color: mutedColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: const ['ALL', 'ACTIVE', 'AVAILABLE', 'ADOPTED', 'LOCKED']
            .map((status) => status)
            .map((status) => OutlinedButton(
                  onPressed: () => setState(() => _selectedStatus = status),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    side: BorderSide(color: violetColor.withValues(alpha: .55)),
                  ),
                  child: Text(status,
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700)),
                ))
            .toList(),
      ),
      const SizedBox(height: 14),
      if (visibleItems.isEmpty)
        const EarthEmptyState(
          icon: Icons.science_outlined,
          message: 'No authoritative technology catalog is available.',
        )
      else
        ...visibleItems.take(8).map((item) {
          final name = item.name;
          final description = item.description;
          final branch = item.category.replaceAll('_', ' ');
          final status = item.viewerStatus.toUpperCase();
          final adopted = status == 'ADOPTED' ||
              adoptedNames.contains(item.code) ||
              adoptedNames.contains(item.name);
          final statusColor = status == 'ADOPTED'
              ? cyanAccentColor
              : status == 'ACTIVE'
                  ? violetColor
                  : status == 'AVAILABLE'
                      ? Colors.green
                      : mutedColor;
          final statusTextStyle = TextStyle(
              color: statusColor,
              fontSize: 8,
              fontWeight: FontWeight.w800);
          final effectSummary = item.effects.isEmpty
              ? 'No typed effects published'
              : item.effects
                  .map((value) => value.effectType.replaceAll('_', ' '))
                  .join(' · ');
          final prerequisiteSummary = item.prerequisites.isEmpty
              ? 'NONE PUBLISHED'
              : item.prerequisites.join(' · ');
          final project = projectByTechnology[item.id];
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .65),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 16, color: cyanAccentColor),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                          child: Text(name,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800))),
                      Text(status, style: statusTextStyle)
                    ]),
                    const SizedBox(height: 3),
                    Text(description,
                        style:
                            const TextStyle(color: mutedColor, fontSize: 9.5)),
                    const SizedBox(height: 5),
                    Text('PATH: $branch · CODE: ${item.code}',
                        style: const TextStyle(
                            color: cyanAccentColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                        'COST: ${formatCreditUnits(item.researchCostUnits)} · DURATION: ${item.researchDurationGameDays} GAME DAYS',
                        style: const TextStyle(
                            color: mutedColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('PREREQUISITES: $prerequisiteSummary',
                        style: const TextStyle(
                            color: mutedColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('EFFECTS: $effectSummary',
                        style: const TextStyle(
                            color: mutedColor,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600)),
                    if (status == 'ACTIVE' && project != null) ...[
                      const SizedBox(height: 3),
                      Text(
                          'COMPLETION: DAY ${project.completionGameDay ?? 'UNAVAILABLE'} · ${project.remainingGameDays ?? 'UNAVAILABLE'} GAME DAYS REMAINING',
                          style: const TextStyle(
                              color: violetColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700)),
                    ],
                    if (item.accessSource != null) ...[
                      const SizedBox(height: 3),
                      Text('ACCESS: ${item.accessSource}',
                          style: const TextStyle(
                              color: cyanAccentColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700)),
                    ],
                    if (adopted) ...[
                      const SizedBox(height: 3),
                      const Text('ADOPTED · Currently affecting outcomes',
                          style: TextStyle(
                              color: cyanAccentColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700)),
                    ],
                  ])),
            ]),
          );
        }),
    ]);
  }

  List<String> _names(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((item) => item is Map
            ? (item['name'] ?? item['title'] ?? item['id'])?.toString()
            : item.toString())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
  }

  String _milestoneFor(Map<String, dynamic> item) {
    final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
    if (name.contains('civic')) return 'CIVIC INNOVATION';
    if (name.contains('energy') || name.contains('food')) {
      return 'APPLIED SYSTEMS';
    }
    return 'FOUNDATION';
  }

  String _branchFor(Map<String, dynamic> item) {
    final explicit = item['branch'] ?? item['category'] ?? item['domain'];
    if (explicit != null && explicit.toString().trim().isNotEmpty) {
      return explicit.toString().replaceAll('_', ' ');
    }
    final name = (item['name'] ?? item['title'] ?? '').toString().toLowerCase();
    if (name.contains('energy')) return 'Energy & Infrastructure';
    if (name.contains('food')) return 'Life Support';
    if (name.contains('civic')) return 'Civic Systems';
    if (name.contains('assembly') || name.contains('maintenance')) {
      return 'Construction & Industry';
    }
    return 'General Capability';
  }

  String _formatPrerequisites(dynamic raw) {
    if (raw == null) return 'None';
    if (raw is List) {
      if (raw.isEmpty) return 'None';
      return raw
          .map((item) => item is Map
              ? (item['name'] ?? item['title'] ?? item['id'])?.toString()
              : item.toString())
          .whereType<String>()
          .join(', ');
    }
    final text = raw.toString().trim();
    return text.isEmpty ? 'None' : text;
  }

  String _effectLabel(String effect) {
    switch (effect) {
      case 'assembly_output_bonus':
        return 'Higher building output';
      case 'energy_efficiency':
        return 'Lower energy upkeep';
      case 'food_output_bonus':
        return 'Stronger food supply';
      case 'maintenance_reduction':
        return 'Lower building upkeep';
      case 'civic_capacity_bonus':
        return 'Higher civic capacity';
      default:
        return effect.replaceAll('_', ' ');
    }
  }
}

class TechnologyPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final ValueChanged<String>? onNavigate;
  final Key? panelKey;
  final int initialTab;

  const TechnologyPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
    this.onNavigate,
    this.initialTab = 0,
  });

  @override
  State<TechnologyPanel> createState() => _TechnologyPanelState();
}

class _TechnologyPanelState extends State<TechnologyPanel> {
  BigInt? _creditUnits(dynamic value) =>
      value == null ? null : BigInt.tryParse(value.toString().trim());

  String _credit(dynamic value) => formatCreditUnits(value);

  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.state.technologyWorkspace;
    final techCatalog = workspace.catalog;
    final projectList = workspace.projects;
    final research = projectList.isNotEmpty ? projectList.first : null;
    final techName = research == null || research.name.isEmpty
        ? 'NO ACTIVE RESEARCH PROJECT'
        : research.name.toUpperCase();
    final techId = research?.id.isNotEmpty == true ? research!.id : '—';
    final corporationId =
        widget.state.membership?['corporation_id']?.toString();
    final isCorporationMember =
        corporationId != null && corporationId.isNotEmpty;
    final progressBps = research?.progressBps ?? 0;
    final progress = (progressBps / 100).clamp(0.0, 100.0);
    final remainingGameDays = research?.remainingGameDays;
    final completionGameDay = research?.completionGameDay;
    final isComplete = research?.status.toUpperCase() == 'COMPLETED' || progressBps >= 10000;
    final computeReserve = asDoubleOr(widget.state.resources['compute'], 0);
    final buildingCount = widget.state.buildings.length;
    final historyEvents = widget.state.history['events'] is List
        ? (widget.state.history['events'] as List).whereType<Map>().toList()
        : <Map>[];
    final researchEvents = historyEvents
        .where((event) {
          final text =
              '${event['event_type'] ?? ''} ${event['title'] ?? ''} ${event['details'] ?? ''}'
                  .toLowerCase();
          return text.contains('research') || text.contains('technology');
        })
        .take(4)
        .toList();

    final buildingResearchData = widget.state.corporationBuildingResearch;
    final buildingProjects = buildingResearchData['projects'] is List
        ? (buildingResearchData['projects'] as List)
        : const [];
    final activeBuildingResearchCount = buildingProjects
        .where((p) => p is Map && p['status'] == 'active')
        .length;
    final buildingUnlocks = buildingResearchData['unlocks'] is List
        ? (buildingResearchData['unlocks'] as List)
        : const [];
    final unlockedBuildingTiersCount = buildingUnlocks.length;

    final activeCommonResearchCount = projectList
        .where((p) => p.targetType == 'TECHNOLOGY' &&
            p.status.toUpperCase() != 'COMPLETED' &&
            (p.progressBps ?? 0) < 10000)
        .length;

    final corp = widget.state.institutions['corporation'];
    final corpTreasury = corp is Map
        ? _creditUnits(corp['treasury_units'] ?? corp['treasury'])
        : null;

    final cockpit = EarthPageCockpit(
      status: isCorporationMember
          ? (activeBuildingResearchCount > 0 || activeCommonResearchCount > 0
              ? 'ACTIVE RESEARCH'
              : 'CORPORATE R&D COMMONS')
          : 'INDEPENDENT OBSERVER',
      statusColor:
          isCorporationMember ? context.primaryColor : context.warningColor,
      infoTitle: 'RESEARCH & TECHNOLOGY ARCHITECTURE',
      infoDescription:
          '• Building Tier: The authored level of one building blueprint family (for example, Building Tier IV). Researching it unlocks that building blueprint; it does not advance Earth technology.\n\n• Domain Generation: The Earth frontier level of a technology domain (for example, Generation III ENERGY). It limits which technology generations a Corporation can access and advances through Governance.\n\n• Technology / Capability: A researched technology with a named effect. A completed Capability can improve Corporation outcomes, but it is not a Building Tier or a Domain Generation.\n\n• All R&D is Corporation-funded. Costs, duration, prerequisites, effects, and rules version come from authoritative server data.',
      title: 'RESEARCH & TECHNOLOGY',
      subtitle:
          'Building Tiers, Domain Generations, and researched Capabilities across Earth',
      metrics: [
        CockpitMetric(
          label: 'Building Tiers',
          value: '$unlockedBuildingTiersCount',
          icon: Icons.military_tech_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Common Tech',
          value: '$activeCommonResearchCount',
          icon: Icons.biotech_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Corp Treasury',
                          value: corpTreasury != null
              ? _credit(corpTreasury)
              : (isCorporationMember ? 'Corporate' : 'N/A'),
          icon: Icons.account_balance_outlined,
          color: const Color(0xFF10B981),
        ),
      ],
    );

    return EarthPanel(
      key: widget.panelKey,
      title: 'RESEARCH / CURRENT BREAKTHROUGH',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Building Tier research unlocks a specific level in a building blueprint family.\n\n• Technology / Capability research develops a named Corporation technology effect.\n\n• Domain Generation is the Earth-wide technology level available in a domain; advancing it requires a V5 Governance decision.\n\n• Independent characters can read the catalogue, but Corporation membership is required to fund research. Each project displays authoritative cost, duration, prerequisites, effects, and rules version.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cockpit,
          const SizedBox(height: 24),
          if (!isCorporationMember) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: .32)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 19),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You are currently independent. The technology catalogue is read-only for independent players. Corporation membership is required to start or fund research because projects use the Corporation research budget.',
                      style: TextStyle(
                          color: mutedColor, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Container(
            margin: EdgeInsets.only(bottom: context.spacingControl),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Row(
              children: [
                _researchTabButton(context, 0, Icons.domain, 'BUILDING TIERS'),
                _researchTabButton(context, 1, Icons.biotech_outlined,
                    'CORPORATION TECHNOLOGIES'),
                _researchTabButton(context, 2, Icons.public_outlined,
                    'EARTH DOMAIN GENERATION'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_selectedTab == 0)
            CorporateBuildingResearchPanel(
              state: widget.state,
              busy: widget.busy,
              action: widget.action,
            ),
          if (_selectedTab == 1) ...[
            const SizedBox(height: 14),
            // ACTIVE RESEARCH PROJECT COCKPIT
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: violetColor.withValues(alpha: .2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: violetColor.withValues(alpha: .4)),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.biotech_outlined,
                          size: 22,
                          color: cyanAccentColor,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    techName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: inkColor,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: (isComplete
                                            ? cyanAccentColor
                                            : Colors.lightBlueAccent)
                                        .withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: (isComplete
                                              ? cyanAccentColor
                                              : Colors.lightBlueAccent)
                                          .withValues(alpha: .4),
                                    ),
                                  ),
                                  child: Text(
                                    isComplete ? 'COMPLETED' : 'IN RESEARCH',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .8,
                                      color: isComplete
                                          ? cyanAccentColor
                                          : Colors.lightBlueAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'PROJECT ID: $techId  ·  STATUS: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}${completionGameDay == null ? '' : '  ·  COMPLETES DAY $completionGameDay'}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: mutedColor,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Progress Bar & Percentage
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'RESEARCH PROGRESSION',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .8,
                          color: mutedColor.withValues(alpha: .9),
                        ),
                      ),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.3,
                          color: isComplete ? cyanAccentColor : inkColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 8,
                      color:
                          isComplete ? cyanAccentColor : Colors.lightBlueAccent,
                      backgroundColor: Colors.white10,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Server-derived timing and funding facts.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          'Catalog cost: ${_credit(research?.creditCostUnits)} · Compute reserve: ${formatWholeNumber(computeReserve)} · ${isComplete ? 'Ready to deploy' : (remainingGameDays == null ? 'Completion day unavailable' : '$remainingGameDays game day${remainingGameDays == 1 ? '' : 's'} remaining')}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .04),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          'Corporation context: $buildingCount active building${buildingCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: mutedColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // R&D ACTIONS
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'RESEARCH DECISIONS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: mutedColor,
                ),
              ),
            ),
            const SizedBox(height: 8),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: inkColor,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.busy || !isCorporationMember
                        ? null
                        : () => showResearchComposerDialog(
                            context, widget.action, techCatalog),
                    icon: const Icon(Icons.science_outlined, size: 15),
                    label: const Text(
                      'NEW PROJECT · CATALOG COST',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (researchEvents.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'RESEARCH RECORD',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 8),
              ...researchEvents.map((event) {
                final title =
                    (event['title'] ?? event['event_type'] ?? 'Research event')
                        .toString()
                        .replaceAll('_', ' ');
                final day = event['game_day'] ?? event['day'];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 13, color: mutedColor),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          day == null ? title : 'Day $day · $title',
                          style:
                              const TextStyle(color: mutedColor, fontSize: 9.5),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 22),
            TechnologyOutcomePanel(state: widget.state),
          ],
          if (_selectedTab == 2)
            TechnologyFrontierPanel(
              state: widget.state,
              onNavigate: widget.onNavigate,
            ),
        ],
      ),
    );
  }

  Widget _researchTabButton(
    BuildContext context,
    int index,
    IconData icon,
    String label, {
    String? subtitle,
  }) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? context.primaryColor.withValues(alpha: .15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: context.primaryColor.withValues(alpha: .4))
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
                const SizedBox(width: 6),
                Text(
                  subtitle != null ? '$label ($subtitle)' : label,
                  maxLines: 1,
                  style: context.controlStyle.copyWith(
                    color:
                        isSelected ? context.primaryColor : context.mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TechnologyFrontierPanel extends StatelessWidget {
  final EarthState state;
  final ValueChanged<String>? onNavigate;

  const TechnologyFrontierPanel({
    super.key,
    required this.state,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final frontier = state.technologyWorkspace.frontier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPanel(
          title: 'EARTH DOMAIN GENERATION FRONTIER',
          showTitle: true,
          infoDescription:
              'Earth Domain Generations define the maximum technology level available to Corporations. Advancing the frontier is a V5 Governance decision; Corporation access is shown separately from Earth authorization.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (frontier.isEmpty)
                const EarthEmptyState(
                  icon: Icons.public_off_outlined,
                  message: 'Earth technology frontier data is unavailable.',
                )
              else
                ...frontier.map((domain) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.subtleBorderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.public_outlined,
                                  size: 17, color: context.primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  domain.name.isEmpty ? domain.code : domain.name,
                                  style: context.topicTitleStyle,
                                ),
                              ),
                              Text('DOMAIN GEN ${domain.frontierGeneration}',
                                  style: context.controlStyle.copyWith(
                                      color: context.primaryColor,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 18,
                            runSpacing: 7,
                            children: [
                              _frontierFact(context, 'EFFECTIVE DAY',
                                  '${domain.effectiveFromGameDay}'),
                              _frontierFact(
                                  context,
                                  'NEXT DOMAIN GENERATION',
                                  domain.nextGeneration == null
                                      ? 'UNAVAILABLE'
                                      : 'DOMAIN GEN ${domain.nextGeneration}'),
                              _frontierFact(
                                  context,
                                  'ELIGIBILITY',
                                  domain.nextGeneration == null
                                      ? 'NO NEXT DOMAIN GENERATION'
                                      : 'GOVERNANCE REQUIRED${domain.nextGenerationMinimumGameDay == null ? '' : ' · DAY ${domain.nextGenerationMinimumGameDay}'}'),
                              _frontierFact(
                                  context,
                                  'CORPORATION ACCESS',
                                  domain.corporationAccessibleGeneration == null
                                      ? 'JOIN A CORPORATION'
                                      : 'DOMAIN GEN ${domain.corporationAccessibleGeneration}'),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  domain.governanceStatus.replaceAll('_', ' '),
                                  style: context.widgetFooterStyle.copyWith(
                                      color: domain.nextGeneration == null
                                          ? context.mutedColor
                                          : context.warningColor,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (domain.nextGeneration != null)
                                TextButton.icon(
                                  onPressed: onNavigate == null
                                      ? null
                                      : () => onNavigate!.call('governance'),
                                  icon: const Icon(Icons.how_to_vote_outlined,
                                      size: 15),
                                  label: const Text('OPEN GOVERNANCE'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _frontierFact(BuildContext context, String label, String value) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: context.widgetFooterStyle.copyWith(letterSpacing: .6)),
          const SizedBox(height: 2),
          Text(value,
              style: context.controlStyle.copyWith(
                  color: context.inkColor, fontWeight: FontWeight.w700)),
        ],
      );
}
