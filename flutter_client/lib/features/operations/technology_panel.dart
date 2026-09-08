import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import 'technology_dialogs.dart';

const _kDefaultBlueprints = <Map<String, dynamic>>[
  {
    'building_type': 'restaurant',
    'name': 'Molecular Bistro',
    'category': 'commercial',
    'ownership_class': 'private',
    'slot_footprint': 1,
    'cost_credits': 38000,
    'cost_materials': 80,
    'construction_days': 1,
    'output_credits': 120,
    'upkeep_credits': 20,
    'operating_credits': 120,
    'description': 'High-margin dining producing continuous municipal revenues.',
  },
  {
    'building_type': 'retail-store',
    'name': 'Retail & Tools Boutique',
    'category': 'commercial',
    'ownership_class': 'private',
    'slot_footprint': 1,
    'cost_credits': 32000,
    'cost_materials': 60,
    'construction_days': 1,
    'output_credits': 100,
    'upkeep_credits': 18,
    'operating_credits': 140,
    'description': 'Commercial storefront providing consumer goods and steady cash flow.',
  },
  {
    'building_type': 'commercial-mall',
    'name': 'Commercial Galleria',
    'category': 'commercial',
    'ownership_class': 'public_investment',
    'slot_footprint': 4,
    'cost_credits': 120000,
    'cost_materials': 240,
    'cost_components': 30,
    'construction_days': 4,
    'output_credits': 380,
    'upkeep_credits': 65,
    'operating_credits': 600,
    'description': 'Large-scale trade plaza yielding community commerce dividends.',
  },
  {
    'building_type': 'fabrication-plant',
    'name': 'CNC Fabrication Plant',
    'category': 'industrial',
    'ownership_class': 'private',
    'slot_footprint': 2,
    'cost_credits': 65000,
    'cost_materials': 180,
    'cost_components': 40,
    'construction_days': 2,
    'output_materials': 45,
    'upkeep_energy': 22,
    'operating_credits': 150,
    'description': 'Advanced precision manufacturing for industrial materials.',
  },
  {
    'building_type': 'chemical-foundry',
    'name': 'Polymer Foundry',
    'category': 'industrial',
    'ownership_class': 'private',
    'slot_footprint': 2,
    'cost_credits': 72000,
    'cost_materials': 220,
    'cost_components': 30,
    'construction_days': 2,
    'output_materials': 55,
    'upkeep_energy': 28,
    'operating_credits': 160,
    'description': 'Chemical synthesis foundry producing high-grade structural compounds.',
  },
  {
    'building_type': 'vertical-farm',
    'name': 'Aeroponic Vertical Farm',
    'category': 'agriculture',
    'ownership_class': 'private',
    'slot_footprint': 2,
    'cost_credits': 42000,
    'cost_materials': 90,
    'construction_days': 2,
    'output_food': 80,
    'upkeep_energy': 15,
    'operating_credits': 110,
    'description': 'Climate-controlled multi-tier agricultural food production facility.',
  },
  {
    'building_type': 'server-farm',
    'name': 'Neural Data Center',
    'category': 'technology',
    'ownership_class': 'private',
    'slot_footprint': 2,
    'cost_credits': 85000,
    'cost_materials': 120,
    'cost_components': 50,
    'cost_compute': 20,
    'construction_days': 2,
    'output_compute': 60,
    'upkeep_energy': 40,
    'operating_credits': 180,
    'description': 'High-density computational clusters powering automated systems.',
  },
  {
    'building_type': 'solar-array-complex',
    'name': 'Solar Array Complex',
    'category': 'energy',
    'ownership_class': 'public_investment',
    'slot_footprint': 2,
    'cost_credits': 55000,
    'cost_materials': 140,
    'cost_components': 20,
    'construction_days': 2,
    'output_energy': 120,
    'upkeep_credits': 15,
    'operating_credits': 80,
    'description': 'High-efficiency photovoltaic generation feeding regional grids.',
  },
  {
    'building_type': 'geothermal-grid',
    'name': 'Geothermal Core Grid',
    'category': 'energy',
    'ownership_class': 'civic',
    'slot_footprint': 3,
    'cost_credits': 140000,
    'cost_materials': 350,
    'cost_components': 60,
    'construction_days': 3,
    'output_energy': 320,
    'upkeep_credits': 45,
    'operating_credits': 300,
    'description': 'Deep borehole subterranean thermal energy tap for planetary power.',
  },
  {
    'building_type': 'medical-clinic',
    'name': 'Bionic Medical Center',
    'category': 'healthcare',
    'ownership_class': 'civic',
    'slot_footprint': 2,
    'cost_credits': 95000,
    'cost_materials': 160,
    'cost_components': 40,
    'construction_days': 2,
    'output_credits': 60,
    'upkeep_energy': 25,
    'operating_credits': 220,
    'description': 'Specialized bionic and cellular regeneration healthcare facility.',
  },
  {
    'building_type': 'transit-hyperloop',
    'name': 'Hyperloop Terminal',
    'category': 'transport',
    'ownership_class': 'civic',
    'slot_footprint': 3,
    'cost_credits': 160000,
    'cost_materials': 400,
    'cost_components': 80,
    'construction_days': 3,
    'output_credits': 150,
    'upkeep_energy': 50,
    'operating_credits': 500,
    'description': 'Pneumatic ultra-speed passenger and logistics transit connection.',
  },
  {
    'building_type': 'orbital-spaceport',
    'name': 'Orbital Spaceport',
    'category': 'transport',
    'ownership_class': 'public_investment',
    'slot_footprint': 6,
    'cost_credits': 280000,
    'cost_materials': 600,
    'cost_components': 120,
    'cost_compute': 80,
    'construction_days': 6,
    'output_credits': 500,
    'upkeep_energy': 90,
    'operating_credits': 1500,
    'description': 'Planetary surface-to-orbit launch and recovery operations hub.',
  },
  {
    'building_type': 'transit-terminus',
    'name': 'Transit Hub Terminus',
    'category': 'transport',
    'ownership_class': 'civic',
    'slot_footprint': 4,
    'cost_credits': 80000,
    'cost_materials': 180,
    'cost_components': 30,
    'construction_days': 4,
    'output_credits': 75,
    'upkeep_energy': 20,
    'operating_credits': 260,
    'description': 'Regional multimodal urban mobility terminal connecting districts.',
  },
  {
    'building_type': 'urban-district-module',
    'name': 'Urban District Module',
    'category': 'residential',
    'ownership_class': 'civic',
    'slot_footprint': 1,
    'cost_credits': 110000,
    'cost_materials': 250,
    'construction_days': 1,
    'output_credits': 110,
    'upkeep_energy': 35,
    'operating_credits': 100,
    'description': 'Modular civic habitat providing citizen housing and municipal capacity.',
  },
  {
    'building_type': 'private-estate-plot',
    'name': 'Private Estate Plot',
    'category': 'residential',
    'ownership_class': 'private',
    'slot_footprint': 1,
    'cost_credits': 50000,
    'cost_materials': 100,
    'construction_days': 1,
    'output_credits': 40,
    'upkeep_credits': 10,
    'operating_credits': 10,
    'description': 'Personal headquarters deed unlocking expanded private plot capacity.',
  },
];

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
  int _selectedScope = 0; // 0 = ALL, 1 = PRIVATE, 2 = CIVIC & UTILITIES
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _calculateResearchCost(dynamic baseCost, int targetTier, {String ownership = 'private'}) {
    final base = math.max(1000.0, asDoubleOr(baseCost, 1000.0));
    final double scopeMul = ownership == 'public_investment'
        ? 3.5
        : (ownership == 'civic' ? 2.5 : 2.0);
    final tierMul = math.pow(2.0, math.max(0, targetTier - 2)).toDouble();
    return math.max(1000, (base * scopeMul * tierMul).round());
  }

  int _calculateDurationDays(dynamic slotFootprint, int targetTier, {String ownership = 'private'}) {
    final slots = math.max(1, asIntOr(slotFootprint, 1));
    return (targetTier + 3) * slots;
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

  String _formatResourceDelta(dynamic rawVal, double multiplier, String unit) {
    final current = asDoubleOr(rawVal, 0);
    if (current <= 0) return 'None';
    final next = current * multiplier;
    final formattedCurrent = current == current.roundToDouble()
        ? current.toInt().toString()
        : current.toStringAsFixed(1);
    final formattedNext = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toStringAsFixed(1);
    return '$formattedCurrent ➔ $formattedNext $unit';
  }

  (String, String) _getPrimaryOutputAndUpkeep(Map<String, dynamic> bp) {
    String outputStr = 'None';
    if (asDoubleOr(bp['output_credits'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_credits'], 1.25, 'Cr/d');
    } else if (asDoubleOr(bp['output_materials'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_materials'], 1.25, 'Mat/d');
    } else if (asDoubleOr(bp['output_energy'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_energy'], 1.25, 'En/d');
    } else if (asDoubleOr(bp['output_food'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_food'], 1.25, 'Food/d');
    } else if (asDoubleOr(bp['output_compute'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_compute'], 1.25, 'Comp/d');
    } else if (asDoubleOr(bp['output_components'], 0) > 0) {
      outputStr = _formatResourceDelta(bp['output_components'], 1.25, 'Comp/d');
    }

    String upkeepStr = 'None';
    if (asDoubleOr(bp['upkeep_credits'], 0) > 0) {
      upkeepStr = _formatResourceDelta(bp['upkeep_credits'], 1.12, 'Cr/d');
    } else if (asDoubleOr(bp['upkeep_energy'], 0) > 0) {
      upkeepStr = _formatResourceDelta(bp['upkeep_energy'], 1.12, 'En/d');
    } else if (asDoubleOr(bp['upkeep_materials'], 0) > 0) {
      upkeepStr = _formatResourceDelta(bp['upkeep_materials'], 1.12, 'Mat/d');
    } else if (asDoubleOr(bp['upkeep_food'], 0) > 0) {
      upkeepStr = _formatResourceDelta(bp['upkeep_food'], 1.12, 'Food/d');
    } else if (asDoubleOr(bp['upkeep_compute'], 0) > 0) {
      upkeepStr = _formatResourceDelta(bp['upkeep_compute'], 1.12, 'Comp/d');
    }

    return (outputStr, upkeepStr);
  }


  String _formatDecimal(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    // Format to 2 decimal places, removing unnecessary trailing zeros if desired or keeping clean 2 digits
    final fixed = val.toStringAsFixed(2);
    if (fixed.endsWith('.00')) {
      return fixed.substring(0, fixed.length - 3);
    }
    return fixed;
  }

  Widget _buildResourceDeltaRow(
    BuildContext context, {
    required String resourceKey,
    required dynamic rawValue,
    required double multiplier,
    required bool isOutput,
  }) {
    final current = asDoubleOr(rawValue, 0);
    final meta = EarthResourceMeta.forCommodity(resourceKey);
    final icon = resourceKey == 'credits'
        ? Icons.account_balance_wallet_outlined
        : meta.icon;
    final color = meta.color;

    String currentStr;
    String nextStr;

    if (current > 0) {
      final next = current * multiplier;
      currentStr = _formatDecimal(current);
      nextStr = _formatDecimal(next);
    } else {
      currentStr = '0';
      nextStr = '0';
    }

    final hasValue = current > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: hasValue ? color : context.mutedColor.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '$currentStr -> $nextStr',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: hasValue ? FontWeight.w700 : FontWeight.w500,
                color: hasValue
                    ? context.inkColor
                    : context.mutedColor.withValues(alpha: 0.45),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

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

    for (final fb in _kDefaultBlueprints) {
      final type = fb['building_type']?.toString();
      if (type != null && type.isNotEmpty) {
        blueprintCatalogMap.putIfAbsent(type, () => fb);
      }
    }

    final allBlueprints = blueprintCatalogMap.values.toList();

    final privateCount = allBlueprints.where((b) {
      final oc = b['ownership_class']?.toString() ?? 'private';
      return oc == 'private';
    }).length;

    final civicCount = allBlueprints.where((b) {
      final oc = b['ownership_class']?.toString() ?? 'private';
      return oc == 'civic' || oc == 'public_investment';
    }).length;

    final filteredBlueprints = allBlueprints.where((b) {
      final oc = b['ownership_class']?.toString() ?? 'private';
      if (_selectedScope == 1 && oc != 'private') return false;
      if (_selectedScope == 2 && oc != 'civic' && oc != 'public_investment') {
        return false;
      }
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
      final aBaseCost = asDoubleOr(a['cost_credits'] ?? a['baseCreditCost'], 35000);
      final bBaseCost = asDoubleOr(b['cost_credits'] ?? b['baseCreditCost'], 35000);
      final aOwnership = a['ownership_class']?.toString() ?? 'private';
      final bOwnership = b['ownership_class']?.toString() ?? 'private';
      final aCost = _calculateResearchCost(aBaseCost, aTier, ownership: aOwnership);
      final bCost = _calculateResearchCost(bBaseCost, bTier, ownership: bOwnership);
      final costCmp = aCost.compareTo(bCost);
      if (costCmp != 0) return costCmp;
      return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (activeProjects.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: cyanAccentColor.withValues(alpha: .4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: cyanAccentColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.science_outlined,
                          size: 16, color: cyanAccentColor),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ACTIVE R&D PIPELINES (${activeProjects.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: cyanAccentColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...activeProjects.map((item) {
                  final progress = asDoubleOr(item['progress'], 0)
                      .clamp(0, 100)
                      .toDouble();
                  final type = item['building_type']?.toString() ?? '';
                  final name = (item['catalog_name'] ??
                          item['name'] ??
                          blueprintCatalogMap[type]?['name'] ??
                          type)
                      .toString();
                  final targetTier = item['target_tier']?.toString() ?? '2';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.panelColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.subtleBorderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$name · Tier $targetTier Progression',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.inkColor,
                                ),
                              ),
                            ),
                            Text(
                              '${progress.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: cyanAccentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress / 100,
                            minHeight: 6,
                            backgroundColor:
                                context.inkColor.withValues(alpha: .1),
                            valueColor: const AlwaysStoppedAnimation(
                                cyanAccentColor),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

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
              label: 'CIVIC & UTILITY',
              count: civicCount,
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
              final cards = filteredBlueprints.map<Widget Function({bool fillHeight})>((bp) {
                final type = bp['building_type']?.toString() ?? '';
                final name = bp['name']?.toString() ?? type;
                final ownership =
                    bp['ownership_class']?.toString() ?? 'private';

                final currentTier = unlockedTiers[type] ?? 1;
                final targetTier = currentTier + 1;

                final baseCost = asDoubleOr(bp['cost_credits'] ?? bp['baseCreditCost'], 35000);
                final slots = math.max(1, asIntOr(bp['slot_footprint'], 1));
                final nextResearchCost = _calculateResearchCost(
                  baseCost,
                  targetTier,
                  ownership: ownership,
                );
                final durationDays = _calculateDurationDays(
                  bp['slot_footprint'],
                  targetTier,
                  ownership: ownership,
                );

                final activeProject = activeProjectMap[type];
                final isResearching = activeProject != null;
                final projectProgress = isResearching
                    ? asDoubleOr(activeProject['progress'], 0)
                        .clamp(0, 100)
                        .toDouble()
                    : 0.0;
                final category =
                    (bp['category']?.toString() ?? 'commercial').toUpperCase();
                final desc = (bp['description'] ?? bp['catalog_description'] ?? '').toString();
                final rawPurpose = (bp['primary_economic_purpose'] ?? bp['primaryEconomicPurpose'])?.toString();
                final purpose = (rawPurpose != null && rawPurpose.trim().isNotEmpty)
                    ? rawPurpose
                    : EarthBuildingMeta.getEconomicPurpose(
                        bp,
                        ownership: ownership,
                        category: category,
                      );
                final civicBenefit = bp['civicBenefit']?.toString();

                // 1. Cost line entries (CapEx +70% per tier)
                final costCreditsCur = baseCost * math.pow(1.70, currentTier - 1);
                final costCreditsNext = baseCost * math.pow(1.70, targetTier - 1);
                final matBase = asDoubleOr(bp['cost_materials'] ?? bp['baseMaterialCost'], 0);
                final compBase = asDoubleOr(bp['cost_components'], 0);
                final computeBase = asDoubleOr(bp['cost_compute'], 0);

                // 2. Upkeep Inputs (Daily Upkeep +12% per tier)
                final upkeepInputs = <(IconData, Color, String, double, double)>[];
                void addUpkeep(String key, IconData icon, Color color) {
                  final raw = asDoubleOr(bp['upkeep_$key'], 0);
                  if (raw > 0) {
                    final cur = raw * math.pow(1.12, currentTier - 1);
                    final next = raw * math.pow(1.12, targetTier - 1);
                    upkeepInputs.add((icon, color, key.toUpperCase(), cur, next));
                  }
                }
                addUpkeep('energy', Icons.bolt_rounded, EarthResourceColors.energy);
                addUpkeep('food', Icons.eco_outlined, EarthResourceColors.food);
                addUpkeep('materials', Icons.terrain_outlined, EarthResourceColors.materials);
                addUpkeep('components', Icons.precision_manufacturing_outlined, EarthResourceColors.components);
                addUpkeep('compute', Icons.memory_rounded, EarthResourceColors.compute);

                // 3. Output entries (Output +25% per tier)
                final outputItems = <(IconData, Color, String, double, double)>[];
                void addOutput(String key, IconData icon, Color color) {
                  final raw = asDoubleOr(bp['output_$key'], 0);
                  if (raw > 0) {
                    final cur = raw * math.pow(1.25, currentTier - 1);
                    final next = raw * math.pow(1.25, targetTier - 1);
                    outputItems.add((icon, color, key.toUpperCase(), cur, next));
                  }
                }
                addOutput('credits', Icons.account_balance_wallet_outlined, EarthResourceColors.credits);
                addOutput('energy', Icons.bolt_rounded, EarthResourceColors.energy);
                addOutput('food', Icons.eco_outlined, EarthResourceColors.food);
                addOutput('materials', Icons.terrain_outlined, EarthResourceColors.materials);
                addOutput('components', Icons.precision_manufacturing_outlined, EarthResourceColors.components);
                addOutput('compute', Icons.memory_rounded, EarthResourceColors.compute);

                // 4. Operating Expenses (+12% per tier)
                final opCreditsBase = asDoubleOr(
                  bp['operating_credits'] ??
                      bp['dailyOperatingCredits'] ??
                      bp['dailyStaffingCredits'] ??
                      bp['daily_operating_credits'],
                  0,
                );
                final opEnergyBase = asDoubleOr(bp['operating_energy'], 0);
                final opFoodBase = asDoubleOr(bp['operating_food'], 0);
                final opMaterialsBase = asDoubleOr(bp['operating_materials'], 0);
                final opComponentsBase = asDoubleOr(bp['operating_components'], 0);
                final opComputeBase = asDoubleOr(bp['operating_compute'], 0);

                final hasOperating = opCreditsBase > 0 ||
                    opEnergyBase > 0 ||
                    opFoodBase > 0 ||
                    opMaterialsBase > 0 ||
                    opComponentsBase > 0 ||
                    opComputeBase > 0;

                // Build Time (Slot × Tier construction days)
                final tierDaysCurrent = slots * currentTier;
                final tierDaysNext = slots * targetTier;

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
                      mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
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
                                        label: 'TIER $currentTier -> $targetTier',
                                        variant: EarthBadgeVariant.primary,
                                      ),
                                      EarthBadge(
                                        label: '$slots ${slots == 1 ? "SPACE" : "SPACES"}',
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
                                    'Economic Purpose: $purpose',
                                    style: context.widgetFooterStyle,
                                  ),
                                  if (civicBenefit != null && civicBenefit.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text('CIVIC BENEFIT', style: context.captionStyle),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.star_outline_rounded,
                                            size: 14, color: Colors.purpleAccent),
                                        Text(civicBenefit,
                                            style: context.widgetFooterStyle.copyWith(
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

                        // Row 1: COST (CapEx +70% and Construction Time)
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
                              '${formatWholeNumber(costCreditsCur)} -> ${formatWholeNumber(costCreditsNext)} C',
                              style: context.widgetFooterStyle,
                            ),
                            if (matBase > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                EarthResourceMeta.forCommodity('materials').icon,
                                size: 14,
                                color: EarthResourceColors.materials,
                              ),
                              Text(
                                '${formatWholeNumber(matBase * math.pow(1.70, currentTier - 1))} -> ${formatWholeNumber(matBase * math.pow(1.70, targetTier - 1))}',
                                style: context.widgetFooterStyle,
                              ),
                            ],
                            if (compBase > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                EarthResourceMeta.forCommodity('components').icon,
                                size: 14,
                                color: EarthResourceColors.components,
                              ),
                              Text(
                                '${formatWholeNumber(compBase * math.pow(1.70, currentTier - 1))} -> ${formatWholeNumber(compBase * math.pow(1.70, targetTier - 1))}',
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
                                '${formatWholeNumber(computeBase * math.pow(1.70, currentTier - 1))} -> ${formatWholeNumber(computeBase * math.pow(1.70, targetTier - 1))}',
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
                              '${tierDaysCurrent}d -> ${tierDaysNext}d',
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
                              if (opCreditsBase > 0) ...[
                                const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 14,
                                  color: EarthResourceColors.credits,
                                ),
                                Text(
                                  '-${formatWholeNumber(opCreditsBase * math.pow(1.12, currentTier - 1))} -> -${formatWholeNumber(opCreditsBase * math.pow(1.12, targetTier - 1))} C / DAY',
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
                                  '-${_formatDecimal(opEnergyBase * math.pow(1.12, currentTier - 1))} -> -${_formatDecimal(opEnergyBase * math.pow(1.12, targetTier - 1))} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opMaterialsBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('materials').icon,
                                  size: 14,
                                  color: EarthResourceColors.materials,
                                ),
                                Text(
                                  '-${_formatDecimal(opMaterialsBase * math.pow(1.12, currentTier - 1))} -> -${_formatDecimal(opMaterialsBase * math.pow(1.12, targetTier - 1))} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opComponentsBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('components').icon,
                                  size: 14,
                                  color: EarthResourceColors.components,
                                ),
                                Text(
                                  '-${_formatDecimal(opComponentsBase * math.pow(1.12, currentTier - 1))} -> -${_formatDecimal(opComponentsBase * math.pow(1.12, targetTier - 1))} / DAY',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                              if (opComputeBase > 0) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  EarthResourceMeta.forCommodity('compute').icon,
                                  size: 14,
                                  color: EarthResourceColors.compute,
                                ),
                                Text(
                                  '-${_formatDecimal(opComputeBase * math.pow(1.12, currentTier - 1))} -> -${_formatDecimal(opComputeBase * math.pow(1.12, targetTier - 1))} / DAY',
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
                          color: context.subtleBorderColor.withValues(alpha: .6),
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
                                    value: projectProgress / 100,
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
                                      color: cyanAccentColor
                                          .withValues(alpha: .4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.science_outlined,
                                        size: 13,
                                        color: cyanAccentColor),
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
                                      ': ${projectProgress.toStringAsFixed(0)}%',
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
                              final userCredits = asDouble(
                                widget.state.human['credits'] ??
                                    widget.state.finance['balance'] ??
                                    widget.state.personalFinance['balance'],
                              ) ?? 0.0;
                              final isPrivate = ownership == 'private';
                              // Do not check corporation credits for corporate/public research proposals
                              final canAffordResearch = isPrivate
                                  ? (userCredits >= nextResearchCost)
                                  : true;
                              final isButtonDisabled = widget.busy ||
                                  (!isPrivate && !isCorporationMember) ||
                                  !canAffordResearch;

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
                                        color: canAffordResearch
                                            ? EarthResourceColors.credits
                                            : context.dangerColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${formatWholeNumber(nextResearchCost)} C',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: canAffordResearch
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
                                        label: 'RESEARCH TIER $targetTier',
                                        icon: Icons.science_outlined,
                                        variant: isButtonDisabled
                                            ? EarthButtonVariant.neutral
                                            : EarthButtonVariant.primary,
                                        height: 32,
                                        onPressed: isButtonDisabled
                                            ? null
                                            : () => _confirmAndStartResearch(
                                                  context,
                                                  type: type,
                                                  name: name,
                                                  targetTier: targetTier,
                                                  currentTier: currentTier,
                                                  costCredits: nextResearchCost,
                                                  durationDays: durationDays,
                                                  costCreditsCur: costCreditsCur,
                                                  costCreditsNext: costCreditsNext,
                                                  upkeepInputs: upkeepInputs,
                                                  outputItems: outputItems,
                                                  opCreditsBase: opCreditsBase,
                                                  opEnergyBase: opEnergyBase,
                                                  opMaterialsBase: opMaterialsBase,
                                                  opComponentsBase: opComponentsBase,
                                                  opComputeBase: opComputeBase,
                                                  ownership: ownership,
                                                  tierDaysCurrent: tierDaysCurrent,
                                                  tierDaysNext: tierDaysNext,
                                                ),
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
              subtitle:
                  tier == null ? 'Tier unlocked' : 'Tier $tier unlocked',
              badges: const [
                Chip(
                    label: Text('TIER UNLOCKED'),
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
            color: isSelected
                ? context.primaryColor
                : context.subtleBorderColor,
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
    required int costCredits,
    required int durationDays,
    required double costCreditsCur,
    required double costCreditsNext,
    required List<(IconData, Color, String, double, double)> upkeepInputs,
    required List<(IconData, Color, String, double, double)> outputItems,
    required double opCreditsBase,
    required double opEnergyBase,
    required double opMaterialsBase,
    required double opComponentsBase,
    required double opComputeBase,
    required String ownership,
    required int tierDaysCurrent,
    required int tierDaysNext,
  }) async {
    EarthAudioEngine.instance.playClick();
    final isPrivate = ownership == 'private';
    final fundingSource =
        isPrivate ? 'your personal account' : 'your corporation treasury';

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
              child: const Icon(Icons.science_outlined,
                  size: 20, color: cyanAccentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Initiate R&D Project',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  Text(
                    '$name · Tier $currentTier → Tier $targetTier',
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
                'Starting this research project will charge ${formatCreditsAmount(costCredits)} from $fundingSource to develop Tier $targetTier blueprints.',
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
                        Text('${formatWholeNumber(costCredits)} C',
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
                            '$durationDays ${durationDays == 1 ? "Day" : "Days"}',
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
                          '${formatWholeNumber(costCreditsCur)} → ${formatWholeNumber(costCreditsNext)}',
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
                          '$tierDaysCurrent d → $tierDaysNext d',
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
                        final curStr = out.$3 == 'CREDITS' || out.$3 == 'CRD' || out.$3 == 'C'
                            ? formatWholeNumber(out.$4)
                            : _formatDecimal(out.$4);
                        final nextStr = out.$3 == 'CREDITS' || out.$3 == 'CRD' || out.$3 == 'C'
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
                    if (opCreditsBase > 0) ...[
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
                            '-${formatWholeNumber(opCreditsBase * math.pow(1.12, currentTier - 1))} → -${formatWholeNumber(opCreditsBase * math.pow(1.12, targetTier - 1))}',
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
            label: 'CONFIRM R&D PROJECT',
            icon: Icons.science_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.action(
          () => const EarthApi().startCorporationBuildingResearch(type));
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

  @override
  Widget build(BuildContext context) {
    final rawCatalog = widget.state.technologyRegistry['catalog'];
    final catalog = rawCatalog is List && rawCatalog.isNotEmpty
        ? rawCatalog
        : const [
            {
              'name': 'Automated Assembly',
              'branch': 'Construction & Industry',
              'description':
                  'Improves building construction and component output for industrial facilities.',
              'effect': 'Higher building output',
              'target': 'Industrial buildings · Components',
            },
            {
              'name': 'Clean Energy Systems',
              'branch': 'Energy & Infrastructure',
              'description':
                  'Reduces energy demand across productive buildings and civic infrastructure.',
              'effect': 'Lower energy upkeep',
              'target': 'Utilities · Operating buildings',
            },
            {
              'name': 'Food Synthesis',
              'branch': 'Life Support',
              'description':
                  'Expands reliable food production and improves city resilience during shortages.',
              'effect': 'Stronger food supply',
              'target': 'Food buildings · City services',
            },
            {
              'name': 'Predictive Maintenance',
              'branch': 'Construction & Industry',
              'description':
                  'Reduces building upkeep pressure and protects productive capacity over time.',
              'effect': 'Lower upkeep pressure',
              'target': 'Industrial buildings · Estates',
            },
            {
              'name': 'Civic Network Infrastructure',
              'branch': 'Civic Systems',
              'description':
                  'Improves the coordination capacity of city services and civic institutions.',
              'effect': 'Better civic capacity',
              'target': 'Civic buildings · Public services',
            },
          ];
    final items = catalog
        .map((raw) => raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{'name': raw.toString()})
        .toList();
    final branches = <String>[];
    for (final item in items) {
      final branch = _branchFor(item);
      if (!branches.contains(branch)) branches.add(branch);
    }
    final visibleItems = (_selectedBranch == 'ALL'
        ? items
        : items.where((item) => _branchFor(item) == _selectedBranch).toList())
      ..sort((a, b) {
        final aCost = asDoubleOr(
            a['researchCost'] ??
                a['research_cost'] ??
                a['cost'] ??
                a['cost_credits'],
            0);
        final bCost = asDoubleOr(
            b['researchCost'] ??
                b['research_cost'] ??
                b['cost'] ??
                b['cost_credits'],
            0);
        final costCmp = aCost.compareTo(bCost);
        if (costCmp != 0) return costCmp;
        return (a['name'] ?? a['title'] ?? '')
            .toString()
            .compareTo((b['name'] ?? b['title'] ?? '').toString());
      });
    final adoptedNames = _names(widget.state.technologyRegistry['adopted'] ??
        widget.state.technologyRegistry['adoptedTechnologies'] ??
        widget.state.technologyRegistry['capabilities']);
    final resourceFlows = widget.state.json['resourceFlows'] is Map
        ? Map<String, dynamic>.from(widget.state.json['resourceFlows'] as Map)
        : const <String, dynamic>{};
    final pressuredResource = [
      'energy',
      'food',
      'material',
      'components',
      'compute'
    ]
        .map((key) {
          final raw = resourceFlows[key] ??
              (key == 'material' ? resourceFlows['materials'] : null);
          return MapEntry(key, asDoubleOr(raw is Map ? raw['net'] : raw, 0));
        })
        .where((entry) => entry.value < 0)
        .fold<MapEntry<String, double>?>(
            null,
            (current, entry) => current == null || entry.value < current.value
                ? entry
                : current);
    final recommendation = pressuredResource == null
        ? 'Choose the path that supports your next building milestone.'
        : 'Consider ${_recommendationFor(pressuredResource.key)} because ${pressuredResource.key} is in net decline.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CAPABILITY OUTCOMES', style: context.topicTitleStyle),
      const SizedBox(height: 5),
      const Text(
          'Research paths and their practical effects on Human-owned operations and civic systems.',
          style: TextStyle(color: mutedColor, fontSize: 10.5)),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: violetColor.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: violetColor.withValues(alpha: .28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline, size: 17, color: violetColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NEXT RESEARCH DIRECTION',
                      style: TextStyle(
                          color: violetColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8)),
                  const SizedBox(height: 3),
                  Text(recommendation,
                      style: const TextStyle(
                          color: inkColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text('RESEARCH PATHS',
          style: TextStyle(
              color: mutedColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1)),
      const SizedBox(height: 8),
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
      const SizedBox(height: 14),
      ...visibleItems.take(8).map((item) {
        final name =
            (item['name'] ?? item['title'] ?? 'Approved capability').toString();
        final description = (item['description'] ??
                'Approved capability with a defined gameplay effect.')
            .toString();
        final effect = (item['effect'] ?? 'Practical capability improvement')
            .toString()
            .replaceAll('_', ' ');
        final branch = _branchFor(item);
        final target = (item['target'] ??
                item['affected_buildings'] ??
                item['resource_effect'] ??
                'Buildings, businesses, or civic services')
            .toString()
            .replaceAll('_', ' ');
        final requirement = item['requirements'] ?? item['requirement'];
        final locked = item['locked'] == true;
        final prerequisite = item['prerequisites'] ?? item['requires'];
        final prerequisiteText = _formatPrerequisites(prerequisite);
        final researchCost = item['researchCost'] ??
            item['research_cost'] ??
            item['cost'] ??
            item['cost_credits'];
        final before =
            item['before'] ?? item['currentValue'] ?? item['current_value'];
        final after =
            item['after'] ?? item['projectedValue'] ?? item['projected_value'];
        final milestone =
            item['milestone'] ?? item['tier'] ?? _milestoneFor(item);
        final adopted = adoptedNames.contains(name);
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
                                fontSize: 10.5, fontWeight: FontWeight.w800))),
                    Text(_effectLabel(effect).toUpperCase(),
                        style: const TextStyle(
                            color: violetColor,
                            fontSize: 8,
                            fontWeight: FontWeight.w800))
                  ]),
                  const SizedBox(height: 3),
                  Text(description,
                      style: const TextStyle(color: mutedColor, fontSize: 9.5)),
                  const SizedBox(height: 5),
                  Text('PATH: $branch · $milestone · APPLIES TO: $target',
                      style: const TextStyle(
                          color: cyanAccentColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      'COST: ${researchCost == null ? 'Set by project' : '${researchCost.toString()} C'} · PREREQUISITE: $prerequisiteText',
                      style: const TextStyle(
                          color: mutedColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600)),
                  if (before != null || after != null) ...[
                    const SizedBox(height: 5),
                    Text(
                        'BEFORE → AFTER: ${before ?? 'Current'} → ${after ?? 'Improved'}',
                        style: const TextStyle(
                            color: Colors.tealAccent,
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
                  if (prerequisite != null) ...[
                    const SizedBox(height: 3),
                    Text('PREREQUISITE · $prerequisite',
                        style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w700)),
                  ],
                  if (locked || requirement != null) ...[
                    const SizedBox(height: 3),
                    Text(
                        locked
                            ? 'LOCKED · ${requirement ?? 'Complete the prerequisite research first.'}'
                            : 'REQUIREMENT · $requirement',
                        style: const TextStyle(
                            color: Colors.orangeAccent,
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

  String _recommendationFor(String resource) {
    switch (resource) {
      case 'energy':
        return 'Energy & Infrastructure';
      case 'food':
        return 'Life Support';
      case 'material':
      case 'components':
        return 'Construction & Industry';
      case 'compute':
        return 'Computing & Research';
      default:
        return 'the path matching your current bottleneck';
    }
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
  final Key? panelKey;
  final int initialTab;

  const TechnologyPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
    this.initialTab = 0,
  });

  @override
  State<TechnologyPanel> createState() => _TechnologyPanelState();
}

class _TechnologyPanelState extends State<TechnologyPanel> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final registry = widget.state.technologyRegistry;
    final projectList = registry['corporationProjects'] is List
        ? (registry['corporationProjects'] as List).whereType<Map>().toList()
        : <Map>[];
    final tech = widget.state.technology;
    final research = projectList.isNotEmpty
        ? Map<String, dynamic>.from(projectList.first)
        : (tech['research'] is Map<String, dynamic>
            ? (tech['research'] as Map<String, dynamic>)
            : tech);
    final techName = (research['name'] as String?)?.toUpperCase() ??
        (tech['name'] as String?)?.toUpperCase() ??
        'ADAPTIVE MAINTENANCE AI';
    final techId = research['id']?.toString() ?? 'TECH-001';
    final corporationId =
        widget.state.membership?['corporation_id']?.toString();
    final isCorporationMember =
        corporationId != null && corporationId.isNotEmpty;
    final progress =
        (asDouble(research['progress']) ?? asDouble(tech['progress']) ?? 0.0)
            .clamp(0.0, 100.0);
    final focus = (research['focus'] ?? tech['focus'] ?? 'efficiency')
        .toString()
        .toUpperCase();
    final budgetNum = research['budget'] ?? research['budgetPerDay'] ?? 240;
    final budget = asDoubleOr(budgetNum, 240.0);
    final isComplete = progress >= 100;
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

    Color focusColor = cyanAccentColor;
    if (focus == 'DURABILITY') focusColor = Colors.tealAccent;
    if (focus == 'SAFETY') focusColor = Colors.lightGreenAccent;
    if (focus == 'COST') focusColor = Colors.amberAccent;

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

    final activeCommonResearchCount = projectList.isNotEmpty
        ? projectList
            .where((p) =>
                asDoubleOr(p['progress'], 0) < 100 &&
                (p['status']?.toString().toLowerCase() != 'completed'))
            .length
        : (!isComplete ? 1 : 0);

    final corp = widget.state.institutions['corporation'];
    final corpTreasury = corp is Map ? asDouble(corp['treasury']) : null;

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
          '• Corporate R&D Sponsorship: Both industrial building tiers and general technologies are sponsored by corporations and funded from their corporate treasuries.\n\n• Capabilities & Breakthroughs: Choose and fund a capability that improves business outcomes. A completed capability can be activated for each business with a subscription.\n\n• Building Tiers: Researches the next technological tier for shared industrial, commercial, and utility buildings in Earth\'s catalog.\n\n• Blueprint Tier Progression Multipliers:\n  - Output Yield: +25% higher production per tier\n  - Upkeep Cost: +12% daily OpEx scaling per tier\n  - Build Cost: +70% installation CapEx per tier\n  - Build Time: Slot × Tier construction days',
      title: 'RESEARCH & TECHNOLOGY',
      subtitle:
          'Planetary patent trees, corporate capability breakthroughs, and industrial tech tiers across Earth',
      metrics: [
        CockpitMetric(
          label: 'Tiers Researched',
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
              ? '${formatWholeNumber(corpTreasury)} C'
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
          '• General technology research is owned and funded by corporations. Independent characters can read the research catalogue, but cannot start or fund a project until they join a corporation.\n\n• Choose and fund a capability that improves business outcomes. A completed capability can be activated for each business with a simple subscription.\n\n• Building-tier research remains a separate corporation-owned path and uses the same corporate treasury.\n\n• Blueprint Tier Progression Multipliers:\n  - Output Yield: +25% higher production per tier\n  - Upkeep Cost: +12% daily OpEx scaling per tier\n  - Build Cost: +70% installation CapEx per tier\n  - Build Time: Slot × Tier construction days',
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
                      'You are currently independent. Research is managed by corporations because it uses the corporate treasury. Join a corporation to start or fund technology research; the catalogue remains available here for reference.',
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
                              'PROJECT ID: $techId  ·  FOCUS: ${focus.toLowerCase()}  ·  STATUS: ${isComplete ? 'COMPLETED' : 'IN RESEARCH'}',
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

                  // Focus & Budget Breakdown Badges (Wrap to prevent horizontal overflow)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: focusColor.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: focusColor.withValues(alpha: .3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded,
                                size: 12, color: focusColor),
                            const SizedBox(width: 5),
                            Text(
                              'FOCUS: $focus',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: focusColor,
                                letterSpacing: .5,
                              ),
                            ),
                          ],
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
                          'Funding: ${formatWholeNumber(budget)} C · Compute reserve: ${formatWholeNumber(computeReserve)} · ${isComplete ? 'Ready to deploy' : '${(100 - progress).toStringAsFixed(0)}% remaining'}',
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
                          'City context: $buildingCount active building${buildingCount == 1 ? '' : 's'}',
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
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: cyanAccentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.busy || isComplete || !isCorporationMember
                        ? null
                        : () => widget
                            .action(() => const EarthApi().fundResearch()),
                    icon: const Icon(Icons.bolt_rounded, size: 15),
                    label: const Text(
                      'FUND 240 C · +4% MAX',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
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
                        : () =>
                            showResearchComposerDialog(context, widget.action),
                    icon: const Icon(Icons.science_outlined, size: 15),
                    label: const Text(
                      'NEW PROJECT · 240 C',
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
