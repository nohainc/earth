import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/building_models.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';
import 'building_detail_upgrade_dialog.dart';

class BuildingsHubScreen extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const BuildingsHubScreen({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<BuildingsHubScreen> createState() => _BuildingsHubScreenState();
}

class _BuildingsHubScreenState extends State<BuildingsHubScreen> {
  int _mainTab = 0; // 0 = HOUSE, 1 = CORPORATION/PUBLIC
  int _narrowSubTab = 0; // 0 = BUILT/ACTIVE, 1 = CATALOG
  String _selectedCategory = 'all';
  String _catalogFilter = 'all';
  String _sortMode = 'default';
  String _plannerSelectedBlueprint = 'restaurant';
  Set<String>? _expandedBuildingGroups;

  bool get _hasActiveCorporation {
    final corporationId = widget.state.membership?['corporation_id']
            ?.toString() ??
        widget.state.human['corporation_id']?.toString();
    return corporationId != null &&
        corporationId.isNotEmpty &&
        corporationId != 'null' &&
        corporationId != 'Independent';
  }

  String _buildingImageAsset(String buildingType) {
    return EarthBuildingMeta.getAssetPath(buildingType);
  }

  String? _currentHouseCapacityCostUnits() {
    final profile = widget.state.corporationProfile;
    final capacity = profile['capacity'];
    if (capacity is Map && capacity['houseBaseRateUnits'] != null) {
      return capacity['houseBaseRateUnits'].toString();
    }
    return widget.state.corporation['house_capacity_base_rate_units']?.toString();
  }

  String _lastSettlementFlow(List<Map<String, dynamic>> buildings) {
    final settled = buildings
        .where((building) => building['latest_settlement_game_day'] != null)
        .toList()
      ..sort((a, b) => asIntOr(b['latest_settlement_game_day'], 0)
          .compareTo(asIntOr(a['latest_settlement_game_day'], 0)));
    if (settled.isEmpty) return 'UNAVAILABLE';
    final latestDay = settled.first['latest_settlement_game_day'];
    final statuses = settled
        .where((building) => building['latest_settlement_game_day'] == latestDay)
        .map((building) => building['latest_settlement_status']?.toString())
        .whereType<String>()
        .toSet()
        .join(' · ');
    return 'Day $latestDay · ${statuses.isEmpty ? 'STATUS UNAVAILABLE' : statuses}';
  }

  Map<String, dynamic> _houseAssetRow(
      BuildingAsset asset, Map<String, dynamic>? legacyRow) {
    final row = <String, dynamic>{...?legacyRow};
    row.removeWhere((key, _) => key.startsWith('settlement_net_'));
    row.addAll({
      'id': asset.id,
      'catalog_id': asset.catalogId,
      'building_type': asset.buildingType,
      'owner_type': asset.ownerType,
      'owner_id': asset.ownerId,
      'ownership_scope': asset.ownershipScope,
      'ownership_class': asset.ownershipScope.toLowerCase(),
      'status': asset.status,
      'construction_state': asset.constructionState,
      'installed_generation': asset.installedGeneration,
      'started_game_day': asset.startedGameDay,
      'slot_footprint': asset.slotFootprintUnits,
      'utilization_bps': asset.utilizationBps ?? legacyRow?['utilization_bps'],
      'allowed_actions': asset.allowedActions,
      'can_build': asset.permissions.canBuild,
      'can_propose': asset.permissions.canPropose,
      'can_operate': asset.permissions.canOperate,
      'can_upgrade': asset.permissions.canUpgrade,
      'can_retrofit': asset.permissions.canRetrofit,
      'can_demolish': asset.permissions.canDemolish,
      'latest_settlement_game_day': asset.settlement.latestGameDay,
      'latest_settlement_status': asset.settlement.status,
      'operating_mode': asset.operatingPolicy.currentMode,
      'operating_policy': {
        'currentMode': asset.operatingPolicy.currentMode,
        'allowedModes': asset.operatingPolicy.allowedModes,
        'effectsByMode': asset.operatingPolicy.effectsByMode,
      },
      'settlement_operating_credit_units': asset.settlement.operatingCreditUnits,
      'settlement_input_units': asset.settlement.inputUnits,
      'settlement_output_units': asset.settlement.outputUnits,
    });
    return row;
  }

  Widget _buildingImage(BuildContext context, String buildingType) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radiusControl),
      child: Image.asset(
        _buildingImageAsset(buildingType),
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

  bool _isBuildingActive(Map<String, dynamic> b) {
    return b['status']?.toString() == 'active';
  }

  String _getInactiveReason(Map<String, dynamic> b) {
    final status = b['status']?.toString();
    final progress = _authoritativeBuildingProgress(b);
    if (status == 'under_construction') {
      return 'Construction in progress (${progress.toStringAsFixed(0)}% complete)';
    }
    if (status == 'closed') return 'Facility decommissioned / closed';
    if (status == 'foreclosed') return 'Facility foreclosed due to insolvency';
    if (status == 'halted') return 'Operations temporarily halted';
    if (status == 'inactive') {
      return 'Facility offline / awaiting commissioning';
    }
    return 'Inactive';
  }

  /// Progress is published by the construction/research read model. The
  /// client never derives it from local time or an assumed duration.
  double _authoritativeBuildingProgress(Map<String, dynamic> b) {
    final status = b['status']?.toString();
    if (status != 'under_construction') {
      return 100.0;
    }
    return (asDouble(b['construction_progress']) ??
            asDouble(b['progress']) ??
            0.0)
        .clamp(0.0, 100.0);
  }

  double _authoritativeResearchProgress(Map<String, dynamic> project) {
    final status = project['status']?.toString();
    if (status == 'completed') return 100.0;
    return (asDouble(project['progress']) ?? 0.0).clamp(0.0, 100.0);
  }

  void _showBuildingFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startCapitalProject(Map<String, dynamic> building) async {
    final buildingId = building['id']?.toString();
    if (buildingId == null || buildingId.isEmpty) return;
    String? selectedGeneration;
    String kind = 'OVERHAUL';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('CAPITAL PROJECT'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FutureBuilder<Map<String, dynamic>>(
                future: const EarthApi()
                    .getBuildingCapitalOptions(buildingId: buildingId),
                builder: (context, snapshot) {
                  final options = snapshot.data?['options'] is List
                      ? (snapshot.data!['options'] as List)
                          .whereType<Map>()
                          .toList()
                      : const <Map>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    );
                  }
                  if (options.isEmpty) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('AUTHORITATIVE INVESTMENT PROJECTION',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        ...options.map((option) {
                          final cost = formatCreditUnits(option['creditCostUnits']);
                          final payback = option['paybackGameDays'];
                          final label = option['type']?.toString() ?? 'OPTION';
                          final effect = option['effect']?.toString() ?? 'effect unavailable';
                          final minutes = option['constructionMinutes'];
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '$label · $cost · ${minutes == null ? 'time unavailable' : '$minutes min'} · $effect · ${payback == null ? 'payback unavailable' : '$payback game days'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'Project type'),
                items: const [
                  DropdownMenuItem(
                      value: 'OVERHAUL',
                      child: Text('Overhaul · reset major rebuild age')),
                  DropdownMenuItem(
                      value: 'GENERATION_RETROFIT',
                      child: Text('Technology retrofit · preserve age')),
                ],
                onChanged: (value) =>
                    setDialogState(() => kind = value ?? kind),
              ),
              if (kind == 'GENERATION_RETROFIT') ...[
                const SizedBox(height: 12),
                FutureBuilder<Map<String, dynamic>>(
                  future: const EarthApi().listEarthTechnologyGenerations(),
                  builder: (context, snapshot) {
                    final rows = snapshot.data?['generations'] is List
                        ? (snapshot.data!['generations'] as List)
                            .whereType<Map>()
                            .toList()
                        : const <Map>[];
                    final eligible = rows
                        .where((row) =>
                            row['eligibility'] is Map &&
                            (row['eligibility'] as Map)['eligible'] == true &&
                            row['discovered'] == true)
                        .toList();
                    return DropdownButtonFormField<String>(
                      value: eligible.any((row) =>
                              row['id']?.toString() == selectedGeneration)
                          ? selectedGeneration
                          : null,
                      decoration: const InputDecoration(
                          labelText: 'Effective technology generation'),
                      items: eligible
                          .map((row) => DropdownMenuItem(
                              value: row['id']?.toString(),
                              child: Text('${row['name'] ?? row['id']}')))
                          .toList(),
                      onChanged: snapshot.connectionState ==
                              ConnectionState.waiting
                          ? null
                          : (value) =>
                              setDialogState(() => selectedGeneration = value),
                      hint: snapshot.connectionState == ConnectionState.waiting
                          ? const Text('Loading eligible generations…')
                          : const Text('Select a discovered generation'),
                    );
                  },
                ),
                const SizedBox(height: 5),
                const Text(
                    'Only discovered and effective generations are selectable. The server still verifies ownership, price, and settlement eligibility.',
                    style: TextStyle(fontSize: 10)),
              ],
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: kind == 'GENERATION_RETROFIT' &&
                      (selectedGeneration == null ||
                          selectedGeneration!.isEmpty)
                  ? null
                  : () => Navigator.pop(dialogContext,
                      {'kind': kind, 'generation': selectedGeneration ?? ''}),
              child: const Text('START'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await widget.action(() async {
        await const EarthApi().startBuildingCapitalProject(
          buildingId: buildingId,
          projectKind: result['kind']!,
          targetGenerationId: result['kind'] == 'GENERATION_RETROFIT'
              ? result['generation']
              : null,
        );
        return const EarthApi().world();
      });
      _showBuildingFeedback(
          'Capital project started; completion is processed at the next settlement boundary.');
    } catch (error) {
      _showBuildingFeedback('Capital project unavailable: $error');
    }
  }

  Future<void> _showInfoDialog(
      BuildContext context, String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Future<void> _showCivicProposalDialog(
    BuildContext context, {
    required String buildingName,
    required String buildingType,
    String? buildingId,
    bool publicInvestment = false,
  }) async {
    EarthAudioEngine.instance.playClick();
    final Map<String, dynamic> quote;
    try {
      quote = buildingId == null
          ? await const EarthApi().quoteV5Building(buildingType)
          : await const EarthApi().quoteBuildingUpgrade(buildingId: buildingId);
    } catch (error) {
      _showBuildingFeedback(
          'Authoritative V5 construction quote unavailable: ${error.toString().replaceFirst('Exception: ', '')}');
      return;
    }
    final quotedCreditCost =
        int.tryParse(quote['creditCostUnits']?.toString() ?? '');
    final quotedFootprint = int.tryParse(
        (quote['footprintUnits'] ?? quote['targetFootprintUnits'])?.toString() ?? '');
    final quotedMinutes = int.tryParse(
        quote['effectiveConstructionMinutes']?.toString() ?? '');
    final resourceRequirements = (quote['resourceRequirements'] as List?)
        ?.whereType<Map>()
        .map((item) => '${item['code']}: ${item['requiredUnits']}')
        .toList(growable: false);
    final blockers = (quote['blockers'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (quote['ok'] != true ||
        quote['eligible'] != true ||
        quotedCreditCost == null ||
        quotedFootprint == null ||
        quotedMinutes == null) {
      _showBuildingFeedback(blockers.isEmpty
          ? 'V5 construction is not currently eligible.'
          : blockers.join(' · '));
      return;
    }
    final constructionDays = math.max(1, (quotedMinutes / 1440).ceil());
    final footprint = quotedFootprint;
    final title = TextEditingController(
        text: publicInvestment
            ? (buildingId == null
                ? 'Open Corporation project: $buildingName'
                : 'Authorize public upgrade for $buildingName')
            : (buildingId == null
                ? 'Build $buildingName'
                : 'Authorize Corporation/Public upgrade for $buildingName'));
    final body = TextEditingController(
        text: publicInvestment
            ? 'Corporation-governed public construction for $buildingName. The Corporation Treasury will fund the pooled-capacity project.'
            : 'Public construction for $buildingName requires an authoritative Corporation source and governance decision.');
    final iconColor =
        publicInvestment ? Colors.lightBlueAccent : Colors.purpleAccent;

    if (!context.mounted) return;
    await showDialog<void>(
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
                color: iconColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: iconColor.withValues(alpha: .4)),
              ),
              child: Icon(
                publicInvestment
                    ? Icons.account_balance_outlined
                    : Icons.how_to_vote_outlined,
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    buildingId != null
                        ? 'Authorize Civic Upgrade'
                        : publicInvestment
                            ? 'Authorize Public Investment'
                            : 'Authorize Civic Building',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  Text(
                    '$buildingName · $footprint ${footprint == 1 ? "Space" : "Spaces"}',
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
                'Corporation governance authorization is required before this pooled-capacity project can begin.',
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
                        Text('Estimated Cost:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: EarthResourceColors.credits),
                        const SizedBox(width: 4),
                        Text(formatCreditUnits(quotedCreditCost),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            )),
                        if (resourceRequirements?.isNotEmpty == true) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(resourceRequirements!.join(' · '),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.inkColor,
                                )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Construction Time:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.timer_outlined,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          '${constructionDays}d',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Pooled Capacity Footprint:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        Icon(Icons.layers_outlined, size: 14, color: iconColor),
                        const SizedBox(width: 4),
                        Text(
                          '$footprint ${footprint == 1 ? "Space" : "Spaces"}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              TextField(
                controller: title,
                maxLength: 140,
                decoration: InputDecoration(
                  labelText: 'Proposal Title',
                  labelStyle:
                      TextStyle(fontSize: 12, color: context.mutedColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radiusControl),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 5,
                maxLength: 4000,
                decoration: InputDecoration(
                  labelText: 'Proposal Details & Rationale',
                  labelStyle:
                      TextStyle(fontSize: 12, color: context.mutedColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(context.radiusControl),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          EarthButton(
            label: 'AUTHORIZE PROJECT',
            icon: Icons.account_balance_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              if (title.text.trim().length < 8 ||
                  body.text.trim().length < 20) {
                return;
              }
              try {
                await widget.action(() => buildingId == null
                    ? const EarthApi().purchaseV5Building(
                        buildingType: buildingType,
                        name: title.text.trim(),
                      )
                    : const EarthApi().upgradeBuilding(buildingId: buildingId));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (error) {
                _showBuildingFeedback(
                    error.toString().replaceFirst('Exception: ', ''));
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buildings = widget.state.buildings
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final catalog = widget.state.buildingCatalog;
    final isIndependent = !_hasActiveCorporation;
    final viewerId = widget.state.human['id']?.toString();
    final houseId = widget.state.house['id']?.toString() ??
        widget.state.house['house_id']?.toString() ??
        widget.state.human['house_id']?.toString();

    final canonicalHouseAssets = widget.state.houseBuildingAssets;
    final rawById = <String, Map<String, dynamic>>{
      for (final building in buildings)
        if (building['id'] != null) building['id'].toString(): building,
    };
    final privateBuildings = canonicalHouseAssets.isNotEmpty
        ? canonicalHouseAssets
            .map((asset) => _houseAssetRow(asset, rawById[asset.id]))
            .where((b) => b['status'] != 'closed')
            .toList()
        : buildings
        .where((b) =>
            b['owner_type']?.toString().toUpperCase() == 'HOUSE' &&
            houseId != null && b['owner_id']?.toString() == houseId &&
            b['status'] != 'closed')
        .toList();
    final corporationPublicBuildings = widget.state.corporationPublicBuildingAssets
        .map((asset) => _houseAssetRow(asset, null))
        .where((b) => b['status'] != 'closed')
        .toList();

    final personalUsedSlots =
        asInt(widget.state.settlementProfile['productive_capacity_units']);
    final capacityCostUnits = _currentHouseCapacityCostUnits();

    return EarthSection(
      title: 'BUILDINGS',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Buildings are the productive assets of the economy: they use resources, provide services, and generate returns.',
        'Private buildings belong to your House. Corporation/Public buildings are owned by the Corporation. Their available actions come from Corporation governance authorization; otherwise they remain read-only.',
        'Operating policy affects output and upkeep. Automatic upkeep keeps routine maintenance out of the main decision loop.',
      ],
      trailing: null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width >= 1100; // 3 columns
          final isMedium = width >= 720; // 2 columns

          final privatePanel = _buildPrivatePanel(
            context,
            privateBuildings: privateBuildings,
            catalog: catalog,
            usedPrivateSlots: personalUsedSlots,
            viewerId: viewerId,
            capacityCostUnits: capacityCostUnits,
          );

          final corporationPanel = _buildCorporationPanel(
            context,
            publicBuildings: corporationPublicBuildings,
            catalog: catalog,
            viewerId: viewerId,
          );

          final effectiveTab = _mainTab;
          final selectedCatalog = _buildCatalogTab(context,
              catalog: catalog,
              ownershipFilter: effectiveTab == 0 ? 'private' : 'public');
          final corporationBuildingsCount = corporationPublicBuildings.length;
          final mainTabs = _buildMainOwnershipTabs(context);

          final cockpit = EarthPageCockpit(
            status: isIndependent
                ? 'INDEPENDENT HOLDINGS'
                : 'REAL ESTATE & INFRASTRUCTURE',
            statusColor:
                isIndependent ? context.warningColor : context.primaryColor,
            infoTitle: 'REAL ESTATE & INFRASTRUCTURE ARCHITECTURE',
            infoDescription:
                '• Private buildings belong to your House. Construction, operation, capacity and settlement outcomes come from authoritative V5 read models and quotes.\n\n• Corporation/public construction is unavailable here until a complete Corporation source is provided.',
            title: 'BUILDINGS & REAL ESTATE',
            subtitle:
                'Productive House assets and authoritative pooled-capacity construction quotes',
            metrics: [
              CockpitMetric(
                label: 'Private Assets',
                value: '${privateBuildings.length}',
                icon: Icons.home_work_outlined,
                color: context.primaryColor,
              ),
              CockpitMetric(
                label: 'Corporation/Public Assets',
                value: '$corporationBuildingsCount',
                icon: Icons.account_balance_outlined,
                color: context.goldColor,
              ),
            ],
          );

          // Unified panel layout (both wide and narrow use active subtab: BUILT vs CATALOG)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cockpit,
              const SizedBox(height: 24),
              mainTabs,
              effectiveTab == 0
                  ? _buildPrivatePanel(context,
                      privateBuildings: privateBuildings,
                      catalog: catalog,
                      usedPrivateSlots: personalUsedSlots,
                      viewerId: viewerId,
                      capacityCostUnits: capacityCostUnits,
                      showSubTabs: true,
                      contentTab: _narrowSubTab,
                      showPanelTitle: false)
                  : _buildCorporationPanel(context,
                      publicBuildings: corporationPublicBuildings,
                      catalog: catalog,
                      viewerId: viewerId,
                      showSubTabs: true,
                      contentTab: _narrowSubTab,
                      showPanelTitle: false),
            ],
          );
        },
      ),
    );
  }

  // ─── Shared tab button (matches Memorial page style) ──────────────────────
  Widget _buildMainOwnershipTabs(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: context.spacingControl),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Row(children: [
        Expanded(
            child: _buildTabButton(context,
                title: 'PRIVATE',
                icon: Icons.storefront_outlined,
                isSelected: _mainTab == 0,
                onTap: () => setState(() => _mainTab = 0))),
        Expanded(
            child: _buildTabButton(context,
                title: 'CORPORATION / PUBLIC',
                icon: Icons.account_balance_outlined,
                isSelected: _mainTab == 1,
                onTap: () => setState(() => _mainTab = 1))),
      ]),
    );
  }

  Widget _buildTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
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
                subtitle != null ? '$title ($subtitle)' : title,
                maxLines: 1,
                style: context.controlStyle.copyWith(
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── PRIVATE panel ─────────────────────────────────────────────────────────
  Widget _buildPrivatePanel(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required List<dynamic> catalog,
    required int? usedPrivateSlots,
    required String? viewerId,
    required String? capacityCostUnits,
    bool showSubTabs = false,
    int contentTab = 0,
    bool showPanelTitle = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('PRIVATE BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        Text('HOUSE PORTFOLIO', style: context.captionStyle),
        SizedBox(height: context.spacingControl / 2),
        _buildAttributeGrid(
          context,
          [
            (
              'OCCUPIED CAPACITY',
              usedPrivateSlots?.toString() ?? 'UNAVAILABLE',
              Icons.layers_outlined,
              context.warningColor
            ),
            (
              'ACTIVE BUILDINGS',
              privateBuildings.where(_isBuildingActive).length.toString(),
              Icons.apartment_outlined,
              context.primaryColor
            ),
            (
              'LAST SETTLEMENT',
              _lastSettlementFlow(privateBuildings),
              Icons.receipt_long_outlined,
              context.successColor
            ),
            (
              'CAPACITY COST',
              capacityCostUnits == null
                  ? 'UNAVAILABLE'
                  : '${formatCreditUnits(capacityCostUnits)} / unit / day',
              Icons.payments_outlined,
              context.goldColor
            ),
          ],
        ),
        SizedBox(height: context.spacingControl / 2),
        Text(
          'CAPACITY STATUS · ${widget.state.settlementProfile.isEmpty ? 'UNAVAILABLE' : widget.state.settlementProfile['dirty'] == true ? 'STALE' : 'CURRENT'}',
          style: context.widgetFooterStyle.copyWith(color: context.mutedColor),
        ),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, privateBuildings),
        SizedBox(height: context.spacingControl),
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['BUILT', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0) ...[
          _buildEstatesTab(
            context,
            privateBuildings: privateBuildings,
            catalog: catalog,
            viewerId: viewerId,
          ),
        ] else
          _buildCatalogTab(context,
              catalog: catalog,
              ownershipFilter: 'private'),
      ],
    );
  }

  // ─── CORPORATION / PUBLIC panel ────────────────────────────────────────────
  Widget _buildCorporationPanel(
    BuildContext context, {
    required List<Map<String, dynamic>> publicBuildings,
    required List<dynamic> catalog,
    required String? viewerId,
    bool showSubTabs = false,
    int contentTab = 0,
    bool showPanelTitle = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('CORPORATION / PUBLIC BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildAttributeGrid(
          context,
          [
            (
              'CORPORATION CAPACITY',
              'UNAVAILABLE',
              Icons.domain_add_outlined,
              context.mutedColor
            ),
            (
              'OCCUPIED CAPACITY',
              publicBuildings.fold<int>(0, (sum, building) => sum + asIntOr(building['slot_footprint'], 0)).toString(),
              Icons.pie_chart_outline,
              context.warningColor
            ),
          ],
        ),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, publicBuildings),
        SizedBox(height: context.spacingControl),
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['BUILT', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0) ...[
          publicBuildings.isEmpty
              ? const EarthEmptyState(
          message: 'No Corporation/Public buildings are available.',
                  icon: Icons.account_balance_outlined)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = _buildGroupedBuildingCards(
                        context, publicBuildings, viewerId, catalog);
                    return _buildResponsiveBuildingCards(
                        cards, constraints.maxWidth);
                  },
                ),
        ] else
          _buildCatalogTab(context, catalog: catalog, ownershipFilter: 'public'),
        SizedBox(height: context.spacingTopic),
      ],
    );
  }

  // ─── CATALOG panel ─────────────────────────────────────────────────────────
  Widget _buildCatalogPanel(BuildContext context,
      {required List<dynamic> catalog}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CATALOG', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildCatalogTab(context, catalog: catalog),
      ],
    );
  }

  Widget _buildAttributeGrid(
    BuildContext context,
    List<(String, String, IconData, Color)> attributes,
  ) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < attributes.length; i++) {
      final item = attributes[i];
      final row = _buildAttributeRow(
        context,
        label: item.$1,
        value: item.$2,
        icon: item.$3,
        accentColor: item.$4,
      );
      (i.isEven ? left : right).add(row);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 450) {
          return Column(children: [...left, ...right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Column(children: left)),
            const SizedBox(width: 24),
            Expanded(child: Column(children: right)),
          ],
        );
      },
    );
  }

  Widget _buildAttributeRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(label,
              style: context.bodyStyle.copyWith(
                  color: context.mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodyStyle.copyWith(
                      color: context.inkColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  // ==================== TAB 1: MY BUILDINGS ====================
  Widget _buildEstatesTab(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required List<dynamic> catalog,
    required String? viewerId,
  }) {
    final filteredBuildings = _selectedCategory == 'all'
        ? privateBuildings.where((b) => b['status'] != 'closed').toList()
        : privateBuildings.where((b) {
            if (b['status'] == 'closed') return false;
            final cat = b['category']?.toString() ?? '';
            if (_selectedCategory == 'attention') {
              return b['status']?.toString() == 'under_construction';
            }
            if (_selectedCategory == 'active') return b['status'] == 'active';
            if (_selectedCategory == 'role') {
              return (b['economic_role']?.toString() ?? cat).isNotEmpty;
            }
            if (_selectedCategory == 'utilized') {
              return asInt(b['utilization_bps']) != null;
            }
            if (_selectedCategory == 'resource') {
              return b['settlement_input_units'] != null ||
                  b['settlement_output_units'] != null;
            }
            if (_selectedCategory == 'large') {
              return asInt(b['slot_footprint']) != null &&
                  asInt(b['slot_footprint'])! >= 10;
            }
            if (_selectedCategory == 'generation') {
              return b['installed_generation'] != null;
            }
            return true;
          }).toList();

    if (_sortMode == 'attention') {
      filteredBuildings.sort((a, b) {
        final aScore = a['status']?.toString() == 'under_construction' ? 0 : 1;
        final bScore = b['status']?.toString() == 'under_construction' ? 0 : 1;
        return aScore.compareTo(bScore);
      });
    } else if (_sortMode == 'resource') {
      filteredBuildings.sort((a, b) =>
          (b['settlement_output_units'] == null ? 1 : 0)
              .compareTo(a['settlement_output_units'] == null ? 1 : 0));
    } else if (_sortMode == 'capacity') {
      filteredBuildings.sort((a, b) => asIntOr(a['slot_footprint'], 1)
          .compareTo(asIntOr(b['slot_footprint'], 1)));
    } else if (_sortMode == 'newest') {
      filteredBuildings.sort((a, b) {
        final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildingListFilterChip(context, 'ALL', 'all'),
            _buildingListFilterChip(context, 'ACTIVE', 'active'),
            _buildingListFilterChip(context, 'ATTENTION', 'attention'),
            _buildingListFilterChip(context, 'ROLE', 'role'),
            _buildingListFilterChip(context, 'UTILIZATION', 'utilized'),
            _buildingListFilterChip(context, 'RESOURCE FLOW', 'resource'),
            _buildingListFilterChip(context, 'LARGE FOOTPRINT', 'large'),
            _buildingListFilterChip(context, 'GENERATION', 'generation'),
            _buildingListSortChip(context, 'DEFAULT', 'default'),
            _buildingListSortChip(context, 'UTILIZATION', 'capacity'),
            _buildingListSortChip(context, 'RESOURCE FLOW', 'resource'),
            _buildingListSortChip(context, 'NEWEST', 'newest'),
          ],
        ),
        SizedBox(height: context.spacingControl),
        // Active Buildings List
        if (filteredBuildings.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EarthEmptyState(
                message: _selectedCategory == 'attention'
                    ? 'All owned buildings are operating normally.'
                    : 'No House buildings match this filter.',
                icon: _selectedCategory == 'attention'
                    ? Icons.check_circle_outline
                    : Icons.location_city_outlined,
              ),
              if (_selectedCategory != 'attention') ...[
                const SizedBox(height: 8),
              ],
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = _buildGroupedBuildingCards(
                  context, filteredBuildings, viewerId, catalog);
              return _buildResponsiveBuildingCards(cards, constraints.maxWidth);
            },
          ),

        SizedBox(height: context.spacingTopic),
        _buildRecentBuildingActivity(context),
      ],
    );
  }

  Widget _buildingListFilterChip(
      BuildContext context, String label, String value) {
    return _buildFilterChip(
      context,
      label: label,
      isSelected: _selectedCategory == value,
      onTap: () => setState(() => _selectedCategory = value),
    );
  }

  Widget _buildingListSortChip(
      BuildContext context, String label, String value) {
    return _buildFilterChip(
      context,
      label: 'SORT: $label',
      isSelected: _sortMode == value,
      onTap: () => setState(() => _sortMode = value),
    );
  }

  Widget _buildResponsiveBuildingCards(List<Widget> cards, double maxWidth) {
    final columnsCount = maxWidth >= 1150 ? 3 : (maxWidth >= 700 ? 2 : 1);
    if (columnsCount <= 1 || cards.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards,
      );
    }
    final columns = List.generate(columnsCount, (_) => <Widget>[]);
    for (var i = 0; i < cards.length; i++) {
      columns[i % columnsCount].add(cards[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columnsCount; c++) ...[
          if (c > 0) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: columns[c],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildGroupedBuildingCards(
    BuildContext context,
    List<Map<String, dynamic>> buildings,
    String? viewerId,
    List<dynamic> catalog) {
    final expandedGroups = _expandedBuildingGroups ??= <String>{};
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final building in buildings) {
      final key =
          '${building['building_type'] ?? ''}|${building['name'] ?? ''}';
      groups.putIfAbsent(key, () => []).add(building);
    }
    return groups.values.map((items) {
      final first = items.first;
      final bType = first['building_type']?.toString() ?? '';
      final totalSpace =
          items.fold<int>(0, (sum, b) => sum + (asInt(b['slot_footprint']) ?? 0));
      final tiers = items.map((b) => asIntOr(b['tier'], 1)).toList()..sort();
      final hasConstruction =
          items.any((b) => b['status']?.toString() == 'under_construction');
      final hasIssue = items.any((b) {
        final status = b['status']?.toString();
        return status != 'active' &&
            status != 'under_construction' &&
            status != 'inactive';
      });
      final constructionItems = items
          .where((b) => b['status']?.toString() == 'under_construction')
          .toList();
      final avgProgress = constructionItems.isEmpty
          ? 100.0
          : constructionItems.fold<double>(
              0, (sum, b) => sum + _authoritativeBuildingProgress(b)) /
              constructionItems.length;
      final allConstructed = items.every((b) =>
        _authoritativeBuildingProgress(b) >= 100.0 &&
          b['status']?.toString() != 'under_construction');
      final aggregate = Map<String, dynamic>.from(first)
        ..['slot_footprint'] = totalSpace
        ..['tier'] = tiers.first
        ..['construction_progress'] = avgProgress
        ..['resource_output_amount'] = items.fold<double>(
            0, (sum, b) => sum + asDoubleOr(b['resource_output_amount'], 0))
        ..['daily_operating_credits'] = items.fold<double>(
            0, (sum, b) => sum + asDoubleOr(b['daily_operating_credits'], 0));
      for (final field in [
        'upkeep_energy',
        'upkeep_food',
        'upkeep_materials',
        'upkeep_components',
        'upkeep_compute'
      ]) {
        aggregate[field] =
            items.fold<double>(0, (sum, b) => sum + asDoubleOr(b[field], 0));
      }

      // Lookup catalog spec for description and economic purpose
      final catalogMatch = catalog.whereType<Map>().firstWhere(
            (c) => (c['building_type'] ?? c['type']) == bType,
            orElse: () => <String, dynamic>{},
          );
      final desc = (first['description'] ??
              first['catalog_description'] ??
              catalogMatch['description'] ??
              '')
          .toString();
      final isCorporationPublic = first['owner_type']?.toString().toUpperCase() == 'CORPORATION' &&
          first['ownership_scope']?.toString().toUpperCase() == 'PUBLIC';
      final category =
          (first['category'] ?? catalogMatch['category'] ?? 'facility')
              .toString()
              .toUpperCase();
      final purpose = (first['primary_economic_purpose'] ??
              first['primaryEconomicPurpose'] ??
              catalogMatch['primary_economic_purpose'] ??
              catalogMatch['primaryEconomicPurpose'] ??
              EarthBuildingMeta.getEconomicPurpose(
                first,
                ownership: first['ownership_class']?.toString(),
                category: category,
              ))
          .toString();

      final name = first['name']?.toString() ?? 'Building';
      final groupKey = '$bType|$name';
      final isExpanded = expandedGroups.contains(groupKey);
      final policies = items
          .map((b) => b['operating_mode']?.toString() ?? 'UNKNOWN')
          .toSet();
      final commonPolicy = policies.length == 1 ? policies.first : 'mixed';
      final isEstatePlot = false;
      final isOwner = first['owner_id']?.toString() == viewerId;
      void toggleGroup() => setState(() {
            if (isExpanded) {
              expandedGroups.remove(groupKey);
            } else {
              expandedGroups.add(groupKey);
            }
          });
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor)),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(context.radiusControl),
              onTap: toggleGroup,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildingImage(context, bType),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    '$name × ${items.length}',
                                    style: context.widgetTitleStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: context.primaryColor,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                EarthBadge(
                                  label:
                                      '$totalSpace CAPACITY UNITS',
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
                            if (hasConstruction) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Construction in progress ${avgProgress.toStringAsFixed(0)}% complete',
                                style: context.widgetFooterStyle.copyWith(
                                    color: context.warningColor, fontSize: 12),
                              ),
                            ],
                            if (hasIssue) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Building issue detected',
                                style: context.widgetFooterStyle.copyWith(
                                    color: context.errorColor, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: toggleGroup,
                    child: _buildSettlementFlowLineForBuildings(context, items),
                  ),
                  const SizedBox(height: 12),
                  if (isOwner && !isEstatePlot)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 8,
                          children: [
                            Text('POLICY',
                                style: context.captionStyle.copyWith(
                                    fontSize: 9, color: context.mutedColor)),
                            IconButton(
                                tooltip: 'Policy information',
                                icon: Icon(Icons.info_outline,
                                    size: 15, color: context.mutedColor),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _showInfoDialog(
                                    context,
                                    'Operating policy',
                                    'Available modes and their before/after effects are provided by the authoritative V5 operating-policy read model.')),
                            Wrap(
                              spacing: 4,
                              children: [
                                for (final policyOption in const [
                                  {'id': 'balanced', 'label': 'BALANCED', 'help': 'Server-defined effects'},
                                  {'id': 'frugal', 'label': 'CONSERVATIVE', 'help': 'Server-defined effects'},
                                  {'id': 'high_output', 'label': 'GROWTH', 'help': 'Server-defined effects'},
                                ])
                                  Tooltip(
                                    message: policyOption['help']!,
                                    child: InkWell(
                                      onTap: widget.busy ||
                                              commonPolicy == policyOption['id']
                                          ? null
                                          : () async {
                                              try {
                                                final preview = await const EarthApi()
                                                    .quoteBuildingOperatingPolicy(
                                                        buildingId: items.first['id'].toString());
                                                final allowed = (preview['allowedModes'] as List?)
                                                    ?.map((mode) => mode.toString().toLowerCase())
                                                    .toSet();
                                                if (allowed != null && allowed.isNotEmpty && !allowed.contains(policyOption['id']!.toLowerCase())) {
                                                  _showBuildingFeedback('This operating policy is not available for the group.');
                                                  return;
                                                }
                                              } catch (_) {}
                                              await Future.wait(items.map(
                                                  (item) => widget.action(() =>
                                                      const EarthApi()
                                                          .setBuildingOperatingPolicy(
                                                              buildingId: item[
                                                                      'id']
                                                                  .toString(),
                                                              policy:
                                                                  policyOption[
                                                                      'id']!))));
                                              _showBuildingFeedback(
                                                  '$name group: ${policyOption['label']} policy enabled for all ${items.length} buildings.');
                                            },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color:
                                              commonPolicy == policyOption['id']
                                                  ? context.primaryColor
                                                      .withValues(alpha: .15)
                                                  : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: commonPolicy ==
                                                      policyOption['id']
                                                  ? context.primaryColor
                                                  : context.subtleBorderColor),
                                        ),
                                        child: Text(policyOption['label']!,
                                            style: context.controlStyle
                                                .copyWith(
                                                    color: commonPolicy ==
                                                            policyOption['id']
                                                        ? context.primaryColor
                                                        : context.mutedColor)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 10),
              ...items.asMap().entries.map((entry) => _buildBuildingCard(
                    context,
                    entry.value,
                    viewerId,
                    catalog,
                    itemNumber: entry.key + 1,
                    showOperatingPolicy: false,
                  )),
            ],
          ],
        ),
      );
    }).toList();
  }

  // ==================== TAB 2: BUILD ====================
  Widget _buildPlannerTab(
    BuildContext context, {
    required List<dynamic> catalog,
    required int? availablePrivateSlots,
    required int? population,
    required double? creditsAvailable,
    required double? materialsAvailable,
  }) {
    final blueprints = catalog.whereType<Map>().where((b) {
      final bType = b['building_type'] ?? b['type'];
      if (bType == 'private-estate-plot') {
        return false;
      }
      final ownership = b['ownership_class'] ??
          b['defaultOwnershipClass'] ??
          b['ownershipClass'] ??
          'private';
      final tier = asIntOr(b['tier'], 1);
      final prevId = b['prev_catalog_id'];
      return ownership == 'private' &&
          tier == 1 &&
          (prevId == null || prevId.toString().isEmpty);
    }).toList()
      ..sort((a, b) {
        final aCost = asDoubleOr(a['cost_credits'] ?? a['baseCreditCost'], 0);
        final bCost = asDoubleOr(b['cost_credits'] ?? b['baseCreditCost'], 0);
        final costCompare = aCost.compareTo(bCost);
        if (costCompare != 0) return costCompare;
        return (a['name']?.toString() ?? 'Blueprint')
            .compareTo(b['name']?.toString() ?? 'Blueprint');
      });
    if (blueprints.isEmpty) {
      return const EarthEmptyState(
        message: 'No blueprints available for planning.',
        icon: Icons.architecture_outlined,
      );
    }

    final currentSpec = blueprints.firstWhere(
      (b) => (b['building_type'] ?? b['type']) == _plannerSelectedBlueprint,
      orElse: () => blueprints.first,
    );

    final name = currentSpec['name']?.toString() ?? 'Blueprint';
    final type =
        (currentSpec['building_type'] ?? currentSpec['type'])?.toString() ?? '';
    final category = currentSpec['category']?.toString() ?? 'commercial';
    final footprint = asInt(currentSpec['slot_footprint']);
    final creditCostUnits = currentSpec['construction_credit_units'];
    final materialCost = asInt(currentSpec['construction_material_units']);
    final paybackDays = asInt(currentSpec['estimatedPaybackDays']);
    final sensitivity =
        currentSpec['resourceSensitivity']?.toString().toUpperCase() ??
            'MEDIUM';
    final risk =
        currentSpec['maintenanceRisk']?.toString().toUpperCase() ?? 'LOW';
    final purpose =
        currentSpec['primaryEconomicPurpose']?.toString() ?? 'Economic Output';
    // Eligibility, cost and prerequisites are authoritative quote data. The
    // catalog is descriptive only; never block or approve construction from a
    // client-side capacity, population or balance calculation.
    final canConstruct = true;

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.architecture_outlined, color: context.primaryColor),
              const SizedBox(width: 8),
              Text('BUILD A BUILDING', style: context.topicTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a building, review its cost and expected performance, then commit the required credits, materials, and building capacity.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),

          // Building comparison cards
          Text('CHOOSE A BUILDING', style: context.captionStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: blueprints.map((b) {
              final bType = (b['building_type'] ?? b['type'])?.toString() ?? '';
              final bName = b['name']?.toString() ?? bType;
              final bSpace = asInt(b['slot_footprint']);
              final bCostUnits = b['construction_credit_units'];
              final bResourceType = b['resource_output_type']?.toString();
              final bResourceAmount = asDouble(
                  bResourceType == null ? null : b['output_$bResourceType']);
              final isSel = _plannerSelectedBlueprint == bType;
              return SizedBox(
                width: 230,
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radiusControl),
                  onTap: () {
                    EarthAudioEngine.instance.playClick();
                    setState(() => _plannerSelectedBlueprint = bType);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSel
                          ? context.primaryColor.withValues(alpha: .08)
                          : context.surfaceColor,
                      borderRadius:
                          BorderRadius.circular(context.radiusControl),
                      border: Border.all(
                        color: isSel
                            ? context.primaryColor
                            : context.subtleBorderColor,
                        width: isSel ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bName, style: context.widgetTitleStyle),
                        const SizedBox(height: 4),
                        Text(
                            '${bSpace?.toString() ?? 'UNAVAILABLE'} capacity unit${bSpace == 1 ? '' : 's'} · ${formatCreditUnits(bCostUnits)}',
                            style: context.widgetFooterStyle),
                        const SizedBox(height: 4),
                        Text(
                          'Net production: SERVER SETTLEMENT REQUIRED',
                          style: context.bodyStyle.copyWith(
                            color: context.mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Operating cost: SERVER SETTLEMENT REQUIRED',
                          style: context.widgetFooterStyle.copyWith(
                            color: context.mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'REVIEW SERVER QUOTE TO BUILD',
                          style: context.captionStyle.copyWith(
                            color: context.warningColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SizedBox(height: context.spacingControl),

          // Deep Financial Intelligence Analysis Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(context.radiusControl),
              border:
                  Border.all(color: context.primaryColor.withValues(alpha: .3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$name ($type)', style: context.widgetTitleStyle),
                    EarthBadge(
                      label:
                          '${footprint?.toString() ?? 'UNAVAILABLE'} CAPACITY UNITS',
                      variant: EarthBadgeVariant.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    'Category: ${category.toUpperCase()} • Primary Purpose: $purpose',
                    style: context.widgetFooterStyle),
                const Divider(height: 20),

                // Strategic Metric Grid
                EarthMetricGrid(
                  metrics: [
                    EarthMetricTile(
                      label: 'ESTIMATED PAYBACK',
                      value: paybackDays == null ? 'UNAVAILABLE' : '~ $paybackDays DAYS',
                      icon: Icons.timer_outlined,
                      accentColor: paybackDays != null && paybackDays <= 15
                          ? context.successColor
                          : context.primaryColor,
                    ),
                    EarthMetricTile(
                      label: 'SETTLEMENT RESULT',
                      value: 'SERVER SETTLEMENT REQUIRED',
                      icon: Icons.trending_up,
                      accentColor: context.successColor,
                    ),
                    EarthMetricTile(
                      label: 'RESOURCE SENSITIVITY',
                      value: sensitivity,
                      icon: Icons.water_drop_outlined,
                      accentColor: sensitivity == 'LOW'
                          ? context.successColor
                          : context.warningColor,
                    ),
                    EarthMetricTile(
                      label: 'MAINTENANCE WEAR RISK',
                      value: risk,
                      icon: Icons.build_outlined,
                      accentColor: risk == 'LOW'
                          ? context.successColor
                          : context.warningColor,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Strategic Requirements Checklist Box
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CONSTRUCTION PREREQUISITES CHECKLIST:',
                          style: context.captionStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _buildRequirementItem(
                            context,
                            'Building Capacity: ${footprint?.toString() ?? 'UNAVAILABLE'} units',
                            footprint != null,
                          ),
                          _buildRequirementItem(
                            context,
                            'CREDIT cost: ${formatCreditUnits(creditCostUnits)}',
                            creditCostUnits != null,
                          ),
                          _buildRequirementItem(
                            context,
                            'Materials: ${materialCost?.toString() ?? 'SERVER QUOTE REQUIRED'}',
                            materialCost != null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Direct Build / Licensing Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    EarthButton(
                      label: 'START CONSTRUCTION',
                      icon: Icons.domain_add_outlined,
                      variant: EarthButtonVariant.primary,
                      onPressed: widget.busy || !canConstruct
                          ? null
                          : () async {
                              EarthAudioEngine.instance.playClick();
                              final pDays = asInt(currentSpec['construction_days']);

                              await _confirmConstruction(
                                context,
                                buildingName: name,
                                buildingType: _plannerSelectedBlueprint,
                                creditCost: null,
                                materialCost: null,
                                capacityCost: footprint,
                                remainingCapacity: null,
                                constructionDays: pDays,
                                // Construction confirmation must not project
                                // game-day settlement from catalog fields.
                                netYields: const [],
                              );
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmConstruction(
    BuildContext context, {
    required String buildingName,
    required String buildingType,
    required int? creditCost,
    required int? materialCost,
    required int? capacityCost,
    required int? remainingCapacity,
    int? constructionDays,
    required List<(IconData, Color, String, bool)> netYields,
  }) async {
    EarthAudioEngine.instance.playClick();
    var quotedCapacityQuote = <String, dynamic>{};
    final quote = await const EarthApi().quoteV5Building(buildingType);
    if (!context.mounted) return;
    if (quote['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(quote['error']?.toString() ??
              'V5 construction quote unavailable.')));
      return;
    }
    final blockers = quote['blockers'] is List
        ? (quote['blockers'] as List).map((value) => value.toString()).toList()
        : <String>[];
    final eligible = quote['eligible'] == true;
    if (quote['capacity'] is Map) {
      quotedCapacityQuote = Map<String, dynamic>.from(quote['capacity'] as Map);
    }
    final requirements = quote['resourceRequirements'] is List
        ? (quote['resourceRequirements'] as List).whereType<Map>()
        : const <Map>[];
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
                color: context.primaryColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: context.primaryColor.withValues(alpha: .4)),
              ),
              child: Icon(Icons.domain_add_outlined,
                  size: 20, color: context.primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirm Construction',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  Text(
                    '$buildingName · Tier 1 Blueprint',
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
                'This review is based on the current authoritative V5 construction quote. Catalog cards do not decide eligibility.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: context.inkColor,
                ),
              ),
              const SizedBox(height: 14),

              if (blockers.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.dangerColor.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.dangerColor.withValues(alpha: .35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BLOCKERS', style: context.captionStyle.copyWith(color: context.dangerColor)),
                      const SizedBox(height: 4),
                      ...blockers.map((blocker) => Text('• $blocker', style: context.bodyStyle.copyWith(color: context.dangerColor))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
                        Text('Construction Cost:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: EarthResourceColors.credits),
                        const SizedBox(width: 4),
                        Text(formatCreditUnits(quote['creditCostUnits']),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            )),
                      ],
                    ),
                    if (quotedCapacityQuote.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Capacity: ${quotedCapacityQuote['currentUsage'] ?? 'UNAVAILABLE'} → ${quotedCapacityQuote['afterUsage'] ?? 'UNAVAILABLE'} units · daily rent current ${quotedCapacityQuote['currentChargeUnits'] ?? 'UNAVAILABLE'} · after ${quotedCapacityQuote['afterChargeUnits'] ?? 'UNAVAILABLE'} · marginal ${quotedCapacityQuote['incrementalChargeUnits'] ?? 'UNAVAILABLE'} CREDIT units',
                          style: TextStyle(fontSize: 11, color: context.mutedColor),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Construction Time:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.timer_outlined,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                              quote['effectiveConstructionMinutes'] == null ? 'UNAVAILABLE' : '${quote['effectiveConstructionMinutes']} game minutes',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Pooled Capacity:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        Icon(Icons.layers_outlined,
                            size: 14, color: context.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '${quote['footprintUnits']?.toString() ?? 'UNAVAILABLE'} capacity units',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.inkColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (requirements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('RESOURCE REQUIREMENTS', style: context.captionStyle),
                const SizedBox(height: 6),
                ...requirements.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${item['code']}: required ${item['requiredUnits']} · available ${item['availableUnits']} · missing ${item['missingUnits']}',
                        style: context.widgetFooterStyle,
                      ),
                    )),
              ],
              const SizedBox(height: 12),
              Text('TECHNOLOGY & SCALE', style: context.captionStyle),
              const SizedBox(height: 6),
              Text(
                'Scale: ${quote['minimumScaleCapability'] ?? 'UNAVAILABLE'} (${(quote['scaleAuthorization'] as Map?)?['authorized'] == true ? 'available' : 'blocked'}) · Technology: ${quote['technologyDomain'] ?? 'UNAVAILABLE'} · Generation: ${quote['installedGeneration'] ?? 'UNAVAILABLE'} (${(quote['generationAuthorization'] as Map?)?['authorized'] == true ? 'available' : 'blocked'})',
                style: context.widgetFooterStyle,
              ),
              const SizedBox(height: 12),

              Text(
                'SETTLEMENT RESULT',
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Net production:',
                        style:
                            TextStyle(fontSize: 12, color: context.mutedColor)),
                    const Spacer(),
                    Flexible(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('REPORTED AFTER GAME-DAY SETTLEMENT',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.mutedColor)),
                        ],
                      ),
                    ),
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          EarthButton(
            label: 'CONFIRM BUILD',
            icon: Icons.domain_add_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: eligible ? () => Navigator.of(dialogContext).pop(true) : null,
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.action(() => const EarthApi().purchaseV5Building(
            buildingType: buildingType,
            name: buildingName,
          ));
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('$buildingName construction started.')),
        );
      }
    }
  }

  Widget _buildRequirementItem(BuildContext context, String title, bool isMet) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.cancel,
          color: isMet ? context.successColor : context.dangerColor,
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          title,
          style: context.bodyStyle.copyWith(
            color: isMet ? null : context.dangerColor,
            fontWeight: isMet ? FontWeight.normal : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
                  : context.subtleBorderColor),
        ),
        child: Text(label,
            style: context.controlStyle.copyWith(
                color: isSelected ? context.primaryColor : context.mutedColor)),
      ),
    );
  }

  // ==================== TAB 4: BUILDING CATALOG ====================
  Widget _catalogFilterChip(
    BuildContext context, {
    required String label,
    required String filter,
  }) {
    final isSelected = _catalogFilter == filter;
    return _buildFilterChip(
      context,
      label: label,
      isSelected: isSelected,
      onTap: () => setState(() => _catalogFilter = filter),
    );
  }

  Widget _buildOwnershipSubTabs(BuildContext context,
      {required List<String> labels,
      required int selected,
      required ValueChanged<int> onChanged}) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacingControl),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            _buildFilterChip(
              context,
              label: labels[i],
              isSelected: selected == i,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }

  Color _resourceColor(BuildContext context, String value) {
    return EarthResourceMeta.forCommodity(value.split(' ').last).color;
  }

  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
    String? ownershipFilter,
  }) {
    final allCatalogMaps = catalog
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((item) {
          final bType = (item['building_type'] ?? item['type'])?.toString();
          return bType != 'private-estate-plot' &&
              bType != 'private-estate-plot';
        })
        .toList();

    // Only display root blueprints (tier 1 or prev_catalog_id is null) in the catalog blueprints view
    final rootBlueprints = allCatalogMaps.where((item) {
      final prevId = item['prev_catalog_id'];
      final tier = asInt(item['tier']) ?? 1;
      return (prevId == null || prevId.toString().isEmpty) && tier == 1;
    }).toList();

    rootBlueprints.sort((a, b) {
      return (a['name']?.toString() ?? 'Blueprint')
          .compareTo(b['name']?.toString() ?? 'Blueprint');
    });

    final privateCount = rootBlueprints.where((item) {
      final ownership = item['ownership_class']?.toString() ??
          item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString() ??
          'private';
      return ownership == 'private';
    }).length;

    final corporationPublicCount = rootBlueprints.where((item) {
      final ownership = item['ownership_class']?.toString() ??
          item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString();
      return ownership == 'public';
    }).length;

    String economicRole(Map<String, dynamic> item) =>
        (item['economic_role'] ?? item['economicRole'] ?? 'ESTATE')
            .toString()
            .toUpperCase();
    final roleCounts = <String, int>{
      for (final role in const [
        'PRODUCER',
        'TRANSFORMER',
        'SERVICE',
        'INFRASTRUCTURE',
        'ESTATE',
      ])
        role: rootBlueprints.where((item) => economicRole(item) == role).length,
    };

    final filteredList = rootBlueprints.where((item) {
      final ownership = item['ownership_class']?.toString() ??
          item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString() ??
          'private';

      if (ownershipFilter != null && ownership != ownershipFilter) {
        return false;
      }

      if (_catalogFilter == 'private') {
        return ownership == 'private';
      }
      if (_catalogFilter == 'public') {
        return ownership == 'public';
      }
      if (roleCounts.containsKey(_catalogFilter)) {
        return economicRole(item) == _catalogFilter;
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _catalogFilterChip(
              context,
              label: ownershipFilter == null
                  ? 'ALL (${rootBlueprints.length})'
                  : 'ALL',
              filter: 'all',
            ),
            if (ownershipFilter == null) ...[
              _catalogFilterChip(context,
                  label: 'PRIVATE ($privateCount)', filter: 'private'),
              _catalogFilterChip(context,
                  label: 'CORPORATION / PUBLIC ($corporationPublicCount)', filter: 'public'),
            ],
            ...roleCounts.entries.map((entry) => _catalogFilterChip(
                  context,
                  label: '${entry.key} (${entry.value})',
                  filter: entry.key,
                )),
          ],
        ),
        SizedBox(height: context.spacingControl),

        // Catalog List
        LayoutBuilder(
          builder: (context, constraints) {
            final columnsCount = constraints.maxWidth >= 1150
                ? 3
                : (constraints.maxWidth >= 700 ? 2 : 1);
            final cards =
                filteredList.map<Widget Function({bool fillHeight})>((item) {
              final bType = item['building_type']?.toString() ??
                  item['type']?.toString() ??
                  '';
              final name = item['name']?.toString() ?? 'Blueprint';
              final category =
                  (item['category']?.toString() ?? 'commercial').toUpperCase();
              final ownership = item['ownership_class']?.toString() ??
                  item['defaultOwnershipClass']?.toString() ??
                  item['ownershipClass']?.toString() ??
                  'private';
              final role = economicRole(item);
              final footprint =
                  asInt(item['slot_footprint'] ?? item['slotFootprint']);

              // Group count: total upgrades/tiers available in the catalog for this building type
              final groupBuildings = allCatalogMaps
                  .where((b) => (b['building_type'] ?? b['type']) == bType)
                  .toList();
              final tierCount = math.max(1, groupBuildings.length);

              final purpose = (item['primary_economic_purpose'] ??
                      item['primaryEconomicPurpose'] ??
                      EarthBuildingMeta.getEconomicPurpose(
                        item,
                        ownership: ownership,
                        category: category,
                      ))
                  .toString();
              final desc =
                  (item['description'] ?? item['catalog_description'] ?? '')
                      .toString();

              // Outputs (24-resource vector)
              final outputs = <(IconData, Color, String)>[];
              void addOutput(
                  String key, String label, IconData icon, Color color) {
                final val = asDoubleOr(item['output_$key'], 0);
                if (val > 0) {
                  outputs.add((
                    icon,
                    color,
                    key == 'credits'
                        ? '${formatCreditUnits(item['output_$key'])} / DAY'
                        : '${val.toStringAsFixed(1)} $label / DAY'
                  ));
                }
              }

              addOutput(
                  'credits',
                  'CREDITS',
                  Icons.account_balance_wallet_outlined,
                  EarthResourceColors.credits);
              addOutput('energy', 'ENERGY', Icons.bolt_rounded,
                  EarthResourceColors.energy);
              addOutput(
                  'food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
              addOutput('materials', 'MATERIALS', Icons.terrain_outlined,
                  EarthResourceColors.materials);
              addOutput(
                  'components',
                  'COMPONENTS',
                  Icons.precision_manufacturing_outlined,
                  EarthResourceColors.components);
              addOutput('compute', 'COMPUTE', Icons.memory_rounded,
                  EarthResourceColors.compute);

              // Inputs / Upkeep (24-resource vector)
              final inputs = <(IconData, Color, String)>[];
              void addInput(
                  String key, String label, IconData icon, Color color) {
                final val = asDoubleOr(item['input_$key'], 0);
                if (val > 0) {
                  inputs.add((
                    icon,
                    color,
                    key == 'credits'
                        ? '-${formatCreditUnits(item['input_$key'])}'
                        : '-${val.toStringAsFixed(1)} $label'
                  ));
                }
              }

              addInput(
                  'credits',
                  'CREDITS',
                  Icons.account_balance_wallet_outlined,
                  EarthResourceColors.credits);
              addInput('energy', 'ENERGY', Icons.bolt_rounded,
                  EarthResourceColors.energy);
              addInput(
                  'food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
              addInput('materials', 'MATERIALS', Icons.terrain_outlined,
                  EarthResourceColors.materials);
              addInput(
                  'components',
                  'COMPONENTS',
                  Icons.precision_manufacturing_outlined,
                  EarthResourceColors.components);
              addInput('compute', 'COMPUTE', Icons.memory_rounded,
                  EarthResourceColors.compute);

              final operatingCredits = asDoubleOr(
                  item['operating_credits'],
                  0);
              final operatingEnergy = asDoubleOr(
                  item['operating_energy'] ??
                      item['operatingCostEnergy'] ??
                      item['operating_cost_energy'],
                  0);
              final operatingFood = asDoubleOr(
                  item['operating_food'] ??
                      item['operatingCostFood'] ??
                      item['operating_cost_food'],
                  0);
              final operatingMaterials = asDoubleOr(
                  item['operating_materials'] ??
                      item['operatingCostMaterials'] ??
                      item['operating_cost_materials'],
                  0);
              final operatingComponents = asDoubleOr(
                  item['operating_components'] ??
                      item['operatingCostComponents'] ??
                      item['operating_cost_components'],
                  0);
              final operatingCompute = asDoubleOr(
                  item['operating_compute'] ??
                      item['operatingCostCompute'] ??
                      item['operating_cost_compute'],
                  0);

              final outCreditsVal = asDoubleOr(item['output_credits'], 0);

              final isCorporationPublic = ownership == 'public';
              final corporationPermissions =
                  widget.state.buildingPortfolio?.corporationPermissions;
              final canProposePublic = isCorporationPublic &&
                  corporationPermissions?.canPropose == true;
              // The server quote owns affordability, capacity and all
              // prerequisites. Catalog cards are informational only.

              Widget buildCardBody({bool fillHeight = false}) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: context.subtleBorderColor,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 38, right: 38),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize:
                              fillHeight ? MainAxisSize.max : MainAxisSize.min,
                          children: [
                            // Header row: Image on left, Name/Badges/Desc/Purpose on right
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildingImage(context, bType),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style:
                                            context.widgetTitleStyle.copyWith(
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
                                                '${footprint?.toString() ?? 'UNAVAILABLE'} CAPACITY UNITS',
                                            variant: EarthBadgeVariant.neutral,
                                          ),
                                          EarthBadge(
                                            label: category,
                                            variant: EarthBadgeVariant.neutral,
                                          ),
                                          EarthBadge(
                                            label: role,
                                            variant: role == 'INFRASTRUCTURE'
                                                ? EarthBadgeVariant.warning
                                                : EarthBadgeVariant.neutral,
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
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Cost line
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
                                    color: EarthResourceColors.credits),
                                Text('SELECT FOR AUTHORITATIVE QUOTE',
                                    style: context.widgetFooterStyle),
                              ],
                            ),

                            // Upkeep line
                            if (false && inputs.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('DAILY UPKEEP',
                                      style: context.captionStyle),
                                  const SizedBox(width: 2),
                                  ...inputs.expand((input) => <Widget>[
                                        Icon(input.$1,
                                            size: 14, color: input.$2),
                                        Text(input.$3,
                                            style: context.widgetFooterStyle),
                                      ]),
                                ],
                              ),
                            ],

                            // Output line
                            if (false && outputs.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('OUTPUT', style: context.captionStyle),
                                  const SizedBox(width: 2),
                                  ...outputs.expand((out) => <Widget>[
                                        Icon(out.$1, size: 14, color: out.$2),
                                        Text(out.$3,
                                            style: context.widgetFooterStyle),
                                      ]),
                                ],
                              ),
                            ],

                            // Operating Cost line
                            if (false && (operatingCredits > 0 ||
                                operatingEnergy > 0 ||
                                operatingFood > 0 ||
                                operatingMaterials > 0 ||
                                operatingComponents > 0 ||
                                operatingCompute > 0)) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('OPERATING COST',
                                      style: context.captionStyle),
                                  const SizedBox(width: 2),
                                  if (operatingCredits > 0) ...[
                                    const Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 14,
                                        color: EarthResourceColors.credits),
                                    Text(
                                        '-${formatCreditUnits(item['operating_credit_units'])} / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                  if (operatingEnergy > 0) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                        EarthResourceMeta.forCommodity('energy')
                                            .icon,
                                        size: 14,
                                        color: EarthResourceColors.energy),
                                    Text(
                                        '-${operatingEnergy.toStringAsFixed(1)} ENERGY / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                  if (operatingFood > 0) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                        EarthResourceMeta.forCommodity('food')
                                            .icon,
                                        size: 14,
                                        color: EarthResourceColors.food),
                                    Text(
                                        '-${operatingFood.toStringAsFixed(1)} FOOD / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                  if (operatingMaterials > 0) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                        EarthResourceMeta.forCommodity(
                                                'materials')
                                            .icon,
                                        size: 14,
                                        color: EarthResourceColors.materials),
                                    Text(
                                        '-${operatingMaterials.toStringAsFixed(1)} MATERIALS / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                  if (operatingComponents > 0) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                        EarthResourceMeta.forCommodity(
                                                'components')
                                            .icon,
                                        size: 14,
                                        color: EarthResourceColors.components),
                                    Text(
                                        '-${operatingComponents.toStringAsFixed(1)} COMPONENTS / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                  if (operatingCompute > 0) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                        EarthResourceMeta.forCommodity(
                                                'compute')
                                            .icon,
                                        size: 14,
                                        color: EarthResourceColors.compute),
                                    Text(
                                        '-${operatingCompute.toStringAsFixed(1)} COMPUTE / DAY',
                                        style: context.widgetFooterStyle),
                                  ],
                                ],
                              ),
                            ],

                          ],
                        ),
                      ),

                      // Floating big action icon on bottom right
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Builder(
                          builder: (context) {
                            final tooltip = isCorporationPublic
                                ? canProposePublic
                                    ? 'Use Corporation Governance to propose construction'
                                    : 'Read-only: Corporation authorization required'
                                : 'Review authoritative construction quote';

                            final isActionEnabled = !isCorporationPublic || canProposePublic;
                            final buttonColor = isActionEnabled
                                ? context.primaryColor
                                : context.mutedColor;

                            return Tooltip(
                              message: tooltip,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: isCorporationPublic
                                      ? () => _showBuildingFeedback(
                                          canProposePublic
                                              ? 'Use V5 Corporation Governance to propose or approve this Corporation/Public construction.'
                                              : 'This Corporation/Public blueprint is read-only for your current permissions.')
                                      : () => _confirmConstruction(
                                                context,
                                                buildingName: name,
                                                buildingType: bType,
                                                creditCost: null,
                                                materialCost: null,
                                                capacityCost: null,
                                                remainingCapacity: null,
                                                constructionDays: null,
                                                netYields: const [],
                                              ),
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isActionEnabled
                                          ? buttonColor.withValues(alpha: 0.18)
                                          : Colors.white10,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isActionEnabled
                                            ? buttonColor.withValues(alpha: 0.8)
                                            : Colors.white24,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      isCorporationPublic
                                          ? Icons.how_to_vote_outlined
                                          : Icons.construction_outlined,
                                      size: 24,
                                      color: isActionEnabled
                                          ? buttonColor
                                          : Colors.white38,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
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
      ],
    );
  }

  Widget _buildRecentBuildingActivity(BuildContext context) {
    final events = widget.state.publicActivity
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((event) {
          final text = [
            event['title'],
            event['body'],
            event['message'],
            event['description']
          ].whereType<Object>().join(' ').toLowerCase();
          return text.contains('building') ||
              text.contains('construction') ||
              text.contains('upgrade') ||
              text.contains('repair');
        })
        .take(5)
        .toList();

    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECENT BUILDING ACTIVITY', style: context.topicTitleStyle),
          const SizedBox(height: 8),
          ...events.map((event) {
            final title = event['title']?.toString() ?? 'Building update';
            final detail = event['body']?.toString() ??
                event['message']?.toString() ??
                event['description']?.toString() ??
                '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.domain_outlined,
                      size: 16, color: context.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      detail.isEmpty ? title : '$title · $detail',
                      style: context.widgetFooterStyle,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== BUILDING CARD ====================
  Widget _buildBuildingCard(BuildContext context, Map<String, dynamic> b,
      String? viewerId, List<dynamic> catalog,
      {int? itemNumber,
      bool showOperatingPolicy = true,
      }) {
    final id = b['id']?.toString() ?? '';
    final name = b['name']?.toString() ?? 'Facility';
    final bType = b['building_type']?.toString() ?? '';
    final tier = asIntOr(b['tier'], 1);
    final policy = b['operating_mode']?.toString() ?? 'UNKNOWN';
    final ownershipClass = b['ownership_class']?.toString() ?? 'private';
    final isOwner = b['owner_id']?.toString() == viewerId;
    final isCorporationPublic =
        b['owner_type']?.toString().toUpperCase() == 'CORPORATION' &&
        ownershipClass == 'public';
    final canOperate = b['can_operate'] == true || isOwner;
    final canUpgrade = b['can_upgrade'] == true || isOwner;
    final canRetrofit = b['can_retrofit'] == true || isOwner;
    final canDemolish = b['can_demolish'] == true || isOwner;
    final viewerActions = (b['allowed_actions'] as List?)
            ?.map((action) => action.toString().toUpperCase())
            .toList(growable: false) ??
        const <String>[];
    final bActive = _isBuildingActive(b);
    final progressVal = _authoritativeBuildingProgress(b);
    final isUnderConstruction = !bActive &&
        (b['status']?.toString() == 'under_construction' ||
            progressVal < 100.0);
    final hasIssue = !bActive && !isUnderConstruction;
    final inactiveReason = _getInactiveReason(b);

    final corpProjects =
        (widget.state.corporationBuildingResearch['projects'] as List?)
                ?.whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList() ??
            [];
    final activeResearchProject = corpProjects.firstWhere(
      (p) =>
          p['building_type']?.toString() == bType &&
          (p['status']?.toString() == 'active' || p['status'] == null),
      orElse: () => <String, dynamic>{},
    );
    final hasActiveResearch = activeResearchProject.isNotEmpty;
    final researchProgressVal = hasActiveResearch
        ? _authoritativeResearchProgress(activeResearchProject)
        : 0.0;
    final researchTargetTier = hasActiveResearch
        ? asIntOr(activeResearchProject['target_tier'], tier + 1)
        : tier + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(
              color: isCorporationPublic
              ? context.secondaryColor.withValues(alpha: .4)
              : context.subtleBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isUnderConstruction) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Construction in progress (${progressVal.toStringAsFixed(1)}% complete)',
                        style: context.widgetFooterStyle.copyWith(
                            color: context.warningColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (progressVal / 100.0).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: context.subtleBorderColor,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              context.warningColor),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (hasActiveResearch)
                      Text(
                        'R&D in progress: Tier $researchTargetTier (${researchProgressVal.toStringAsFixed(0)}% complete)',
                        style: context.widgetFooterStyle.copyWith(
                            color: context.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    Text(
                      '${itemNumber == null ? '' : '#$itemNumber  ·  '}${asIntOr(b['slot_footprint'], 1)} capacity units  ·  Tier ${asIntOr(b['tier'], 1)}${b['installed_generation'] != null ? '  ·  Technology generation ${b['installed_generation']}' : ''}${b['technology_domain'] != null ? '  ·  ${b['technology_domain']}' : ''}',
                      style: context.widgetFooterStyle
                          .copyWith(color: context.mutedColor, fontSize: 12),
                    ),
                    if (hasIssue)
                      Text(
                        inactiveReason,
                        style: context.widgetFooterStyle
                            .copyWith(color: context.errorColor, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (isUnderConstruction) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'Construction in progress (${progressVal.toStringAsFixed(0)}%)',
                  child: EarthBadge(
                    label: 'BUILDING ${progressVal.toStringAsFixed(0)}%',
                    variant: EarthBadgeVariant.warning,
                  ),
                ),
              ],
              if (hasActiveResearch) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'Tier $researchTargetTier R&D in progress (${researchProgressVal.toStringAsFixed(0)}%)',
                  child: EarthBadge(
                    label: 'R&D ${researchProgressVal.toStringAsFixed(0)}%',
                    variant: EarthBadgeVariant.primary,
                  ),
                ),
              ],
              if (!bActive && !hasActiveResearch && !isUnderConstruction) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: inactiveReason,
                  child: const EarthBadge(
                    label: 'INACTIVE',
                    variant: EarthBadgeVariant.neutral,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _buildBuildingEconomicsSummary(
            context,
            building: b,
            effectiveOutputAmount: 0,
            effectiveOperatingCost: 0,
            isActive: bActive,
          ),
          const SizedBox(height: 10),
          _buildSettlementFlowLine(context, b),
          if (isCorporationPublic) ...[
            const SizedBox(height: 8),
            Text(
              viewerActions.isEmpty
                  ? 'VIEWER ACCESS · READ ONLY'
                  : 'AUTHORIZED ACTIONS · ${viewerActions.join(' · ')}',
              style: context.widgetFooterStyle.copyWith(
                color: viewerActions.isEmpty
                    ? context.mutedColor
                    : context.primaryColor,
              ),
            ),
          ],
          const SizedBox(height: 6),

          // Management actions
          if (canOperate || canUpgrade || canRetrofit || canDemolish)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canOperate &&
                    showOperatingPolicy &&
                    bType != 'private-estate-plot') ...[
                  Text(
                    'Operating policy modes and their effects are supplied by the authoritative V5 read model.',
                    style: context.widgetFooterStyle,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('OPERATING POLICY:',
                          style: context.captionStyle.copyWith(fontSize: 10)),
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final mode in ((b['operating_policy'] is Map)
                              ? ((b['operating_policy'] as Map)['allowedModes'] as List? ?? const [])
                              : const []))
                            ChoiceChip(
                              label: Text(mode.toString(),
                                  style: const TextStyle(fontSize: 10)),
                              selected: policy == mode.toString(),
                              visualDensity: VisualDensity.compact,
                              onSelected: widget.busy
                                  ? null
                                  : (selected) async {
                                      if (selected && policy != mode.toString()) {
                                        EarthAudioEngine.instance.playClick();
                                        final preview = await const EarthApi()
                                            .quoteBuildingOperatingPolicy(buildingId: id);
                                        final allowed = (preview['allowedModes'] as List?)
                                            ?.map((mode) => mode.toString())
                                            .toSet();
                                        if (allowed == null || !allowed.contains(mode.toString())) {
                                          _showBuildingFeedback('This operating policy is not available for the building.');
                                          return;
                                        }
                                        await widget.action(() =>
                                            const EarthApi()
                                                .setBuildingOperatingPolicy(
                                              buildingId: id,
                                              policy: mode.toString(),
                                            ));
                                        _showBuildingFeedback(
                                            '$name: ${mode.toString()} policy enabled.');
                                      }
                                    },
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (canRetrofit && bActive)
                        EarthButton(
                          label: 'CAPITAL OPTIONS',
                          icon: Icons.build_circle_outlined,
                          variant: EarthButtonVariant.secondary,
                          onPressed: widget.busy
                              ? null
                              : () => _startCapitalProject(b),
                        ),
                      if (tier >= 4)
                        const EarthButton(
                          label: 'MAX TIER REACHED',
                          icon: Icons.check_circle_outline,
                          variant: EarthButtonVariant.secondary,
                          onPressed: null,
                        )
                      else if (catalog.whereType<Map>().any((c) {
                        final type = c['building_type'] ?? c['type'];
                        return type?.toString() == bType &&
                            asIntOr(c['tier'], 1) == tier + 1;
                      }))
                        EarthButton(
                          label: isUnderConstruction
                              ? 'UNDER CONSTRUCTION'
                              : !canUpgrade
                                  ? 'READ ONLY'
                                  : 'UPGRADE TO TIER ${tier + 1}',
                          icon: isUnderConstruction
                              ? Icons.hourglass_top_outlined
                              : Icons.arrow_upward_outlined,
                          variant: isUnderConstruction
                              ? EarthButtonVariant.secondary
                              : EarthButtonVariant.primary,
                          onPressed: widget.busy || isUnderConstruction || !canUpgrade
                              ? null
                              : () async {
                                  EarthAudioEngine.instance.playClick();
                                  final started =
                                      await showBuildingDetailUpgradeDialog(
                                      context,
                                      widget.action,
                                      b,
                                      catalog,
                                    );
                                  if (started == true) {
                                    _showBuildingFeedback('$name upgrade started.');
                                  }
                                },
                        )
                      else
                        EarthButton(
                          label: isUnderConstruction
                              ? 'UNDER CONSTRUCTION'
                              : hasActiveResearch
                                  ? 'R&D IN PROGRESS (${researchProgressVal.toStringAsFixed(0)}%)'
                                  : !canRetrofit
                                      ? 'READ ONLY'
                                      : 'RESEARCH TIER ${tier + 1}',
                          icon: isUnderConstruction
                              ? Icons.hourglass_top_outlined
                              : hasActiveResearch
                                  ? Icons.hourglass_top_outlined
                                  : !canRetrofit
                                      ? Icons.visibility_outlined
                                      : Icons.science_outlined,
                          variant: (isUnderConstruction || hasActiveResearch)
                              ? EarthButtonVariant.secondary
                              : EarthButtonVariant.primary,
                          onPressed: widget.busy ||
                                  isUnderConstruction ||
                                  hasActiveResearch
                              ? null
                              : !canRetrofit
                                  ? () => _showBuildingFeedback(
                                      'This Corporation/Public asset is read-only for your current permissions.')
                                  : () => _showBuildingResearchDialog(
                                    context,
                                    building: b,
                                    targetTier: tier + 1,
                                    catalog: catalog,
                                  ),
                        ),
                      if (canDemolish &&
                          bType != 'private-estate-plot' &&
                          bType != 'private-estate-plot')
                        EarthButton(
                          label: 'DEMOLISH / RECYCLE',
                          icon: Icons.delete_outline,
                          variant: EarthButtonVariant.danger,
                          onPressed: widget.busy
                              ? null
                              : () async {
                                  EarthAudioEngine.instance.playClick();
                                  final demolished =
                                      await showDemolishConfirmDialog(
                                          context, widget.action, b);
                                  if (demolished == true) {
                                    _showBuildingFeedback(
                                        '$name was removed and its capacity was released.');
                                  }
                                },
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showBuildingResearchDialog(
    BuildContext context, {
    required Map<String, dynamic> building,
    required int targetTier,
    required List<dynamic> catalog,
  }) async {
    final bType = building['building_type']?.toString() ?? '';
    final bName = building['name']?.toString() ?? 'Facility';
    final quoteResponse = await const EarthApi()
        .quoteCorporationBuildingResearch(bType);
    if (!context.mounted) return;

    Map<String, dynamic> serverQuote = const <String, dynamic>{};
    Map<String, dynamic> currentBlueprint = const <String, dynamic>{};
    Map<String, dynamic> serverTarget = const <String, dynamic>{};
    int currentTier = asIntOr(building['tier'], 1);

    if (quoteResponse['ok'] == true) {
      serverQuote = quoteResponse['quote'] is Map
          ? Map<String, dynamic>.from(quoteResponse['quote'] as Map)
          : const <String, dynamic>{};
      targetTier = asIntOr(quoteResponse['targetTier'], targetTier);
      currentTier = asIntOr(quoteResponse['currentTier'], currentTier);
      currentBlueprint = quoteResponse['currentBlueprint'] is Map
          ? Map<String, dynamic>.from(quoteResponse['currentBlueprint'] as Map)
          : const <String, dynamic>{};
      serverTarget = quoteResponse['targetBlueprint'] is Map
          ? Map<String, dynamic>.from(quoteResponse['targetBlueprint'] as Map)
          : const <String, dynamic>{};
    }

    if (currentBlueprint.isEmpty) {
      final curMatch = catalog.whereType<Map>().firstWhere(
        (e) =>
            ((e['building_type'] ?? e['type'])?.toString() == bType) &&
            (asInt(e['tier']) ?? 1) == currentTier,
        orElse: () => const <String, dynamic>{},
      );
      if (curMatch.isNotEmpty) {
        currentBlueprint = Map<String, dynamic>.from(curMatch);
      } else {
        _showBuildingFeedback('Authoritative current-tier blueprint data is unavailable.');
        return;
      }
    }

    if (serverTarget.isEmpty) {
      final tgtMatch = catalog.whereType<Map>().firstWhere(
        (e) =>
            ((e['building_type'] ?? e['type'])?.toString() == bType) &&
            (asInt(e['tier']) ?? 1) == targetTier,
        orElse: () => const <String, dynamic>{},
      );
      if (tgtMatch.isNotEmpty) {
        serverTarget = Map<String, dynamic>.from(tgtMatch);
      } else {
        _showBuildingFeedback('Authoritative target-tier blueprint data is unavailable.');
        return;
      }
    }

    final ownership = building['ownership_class']?.toString() ?? 'private';
    final costCredits = asDouble(serverQuote['researchCostUnits']);
    final durationDays = asInt(serverQuote['durationDays']);
    if (costCredits == null || durationDays == null) {
      _showBuildingFeedback('Authoritative research quote is unavailable.');
      return;
    }

    final isPrivate = ownership == 'private';
    final fundingSource =
        isPrivate ? 'your personal account' : 'your corporation treasury';

    // Outputs
    final outputs = <(IconData, Color, String, double, double)>[];
    void addOutput(String key, String label, IconData icon, Color color) {
      final raw = asDouble(currentBlueprint['output_$key']);
      if (raw != null && raw > 0) {
        final cur = raw;
        final next = asDouble(serverTarget['output_$key'] ??
            serverTarget['output${key[0].toUpperCase()}${key.substring(1)}']);
        if (next != null) outputs.add((icon, color, label, cur, next));
      }
    }

    addOutput('credits', 'CRD', Icons.account_balance_wallet_outlined,
        EarthResourceColors.credits);
    addOutput(
        'energy', 'ENERGY', Icons.bolt_rounded, EarthResourceColors.energy);
    addOutput('food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
    addOutput('materials', 'MATERIALS', Icons.terrain_outlined,
        EarthResourceColors.materials);
    addOutput('components', 'COMPONENTS',
        Icons.precision_manufacturing_outlined, EarthResourceColors.components);
    addOutput('compute', 'COMPUTE', Icons.memory_rounded,
        EarthResourceColors.compute);

    // Upkeeps
    final upkeeps = <(IconData, Color, String, double, double)>[];
    void addUpkeep(String key, String label, IconData icon, Color color) {
      final raw = asDouble(currentBlueprint['upkeep_$key']);
      if (raw != null && raw > 0) {
        final cur = raw;
        final next = asDouble(serverTarget['upkeep_$key'] ??
            serverTarget['upkeep${key[0].toUpperCase()}${key.substring(1)}']);
        if (next != null) upkeeps.add((icon, color, label, cur, next));
      }
    }

    addUpkeep(
        'energy', 'ENERGY', Icons.bolt_rounded, EarthResourceColors.energy);
    addUpkeep('food', 'FOOD', Icons.eco_outlined, EarthResourceColors.food);
    addUpkeep('materials', 'MATERIALS', Icons.terrain_outlined,
        EarthResourceColors.materials);
    addUpkeep('components', 'COMPONENTS',
        Icons.precision_manufacturing_outlined, EarthResourceColors.components);
    addUpkeep('compute', 'COMPUTE', Icons.memory_rounded,
        EarthResourceColors.compute);

    final opCreditsBase = asDouble(
      currentBlueprint['operating_credit_units'] ??
          currentBlueprint['operating_credits'] ??
          currentBlueprint['daily_operating_credits'],
    );
    final opCreditsNext = asDouble(
        serverTarget['operating_credit_units'] ??
            serverTarget['operating_credits'] ??
            serverTarget['operating_cost_credits']);

    String formatVal(double val) {
      if (val == val.roundToDouble()) return val.toInt().toString();
      final fixed = val.toStringAsFixed(2);
      if (fixed.endsWith('.00')) return fixed.substring(0, fixed.length - 3);
      return fixed;
    }

    EarthAudioEngine.instance.playClick();
    // Construction days
    final currentMinutes = asDouble(currentBlueprint['construction_minutes']);
    final targetMinutes = asDouble(serverTarget['construction_minutes']);
    final tierDaysCurrent = currentMinutes == null
        ? null
        : math.max(1, (currentMinutes / 1440).ceil());
    final tierDaysNext = targetMinutes == null
        ? null
        : math.max(1, (targetMinutes / 1440).ceil());

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
                color: context.primaryColor.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: context.primaryColor.withValues(alpha: .4)),
              ),
              child: Icon(
                isPrivate ? Icons.science_outlined : Icons.how_to_vote_outlined,
                size: 20,
                color: context.primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isPrivate
                        ? 'Initiate R&D Project'
                        : 'Propose Civic Research',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.inkColor,
                    ),
                  ),
                  Text(
                    '$bName · Tier $currentTier → Tier $targetTier',
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
                    ? 'Starting this research project will charge ${formatCreditUnits(serverQuote['researchCostUnits'])} from $fundingSource to develop Tier $targetTier blueprints.'
                    : 'Submitting this proposal requires no upfront credits. Upon vote passage by the corporation, ${formatCreditUnits(serverQuote['researchCostUnits'])} will be funded from the corporation treasury to develop Tier $targetTier blueprints.',
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
                        Text(formatCreditUnits(serverQuote['researchCostUnits']),
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
                        Icon(Icons.timer_outlined,
                            size: 14, color: context.secondaryColor),
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
                          '${formatCreditUnits(currentBlueprint['construction_credit_units'])} → ${formatCreditUnits(serverTarget['construction_credit_units'])}',
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
                          '${tierDaysCurrent == null ? '—' : '$tierDaysCurrent d'} → ${tierDaysNext == null ? '—' : '$tierDaysNext d'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),

                    // Output
                    if (outputs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...outputs.map((out) {
                        final curStr = out.$3 == 'CRD' ||
                                out.$3 == 'CREDITS' ||
                                out.$3 == 'C'
                            ? formatWholeNumber(out.$4)
                            : formatVal(out.$4);
                        final nextStr = out.$3 == 'CRD' ||
                                out.$3 == 'CREDITS' ||
                                out.$3 == 'C'
                            ? formatWholeNumber(out.$5)
                            : formatVal(out.$5);
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
                    if (upkeeps.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...upkeeps.map((input) {
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
                                '${formatVal(input.$4)} → ${formatVal(input.$5)}',
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
                    if (opCreditsBase != null &&
                        opCreditsBase > 0 &&
                        opCreditsNext != null) ...[
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
                            '-${formatCreditUnits(currentBlueprint['operating_credit_units'])} → -${formatCreditUnits(serverTarget['operating_credit_units'])}',
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
            label: isPrivate ? 'CONFIRM R&D PROJECT' : 'SUBMIT CORPORATION PROPOSAL',
            icon:
                isPrivate ? Icons.science_outlined : Icons.how_to_vote_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (isPrivate) {
        await widget.action(
            () => const EarthApi().startCorporationBuildingResearch(bType));
        _showBuildingFeedback(
            '$bName Tier $targetTier research project initiated.');
      } else {
        _showBuildingFeedback(
            'Public research proposals are retired. Use V5 Corporation Governance to propose research.');
      }
    }
  }

  Widget _buildBuildingsResourceLine(
      BuildContext context, List<Map<String, dynamic>> buildings) {
    return _buildSettlementFlowLineForBuildings(context, buildings);
  }

  Map<String, String>? _stringUnitMap(dynamic value) {
    if (value is! Map || value.isEmpty) return null;
    return value.map((key, item) => MapEntry(key.toString(), item.toString()));
  }

  String _formatUnitMap(Map<String, String>? values) {
    if (values == null || values.isEmpty) return 'UNAVAILABLE';
    return values.entries.map((entry) {
      final formatted = entry.key.toUpperCase() == 'CREDITS'
          ? formatCreditUnits(entry.value)
          : entry.value;
      return '${entry.key.toUpperCase()} $formatted';
    }).join(' · ');
  }

  Widget _buildSettlementFlowLineForBuildings(
      BuildContext context, List<Map<String, dynamic>> buildings) {
    final inputs = <String, String>{};
    final outputs = <String, String>{};
    for (final building in buildings) {
      final inputMap = _stringUnitMap(building['settlement_input_units']);
      final outputMap = _stringUnitMap(building['settlement_output_units']);
      inputMap?.forEach((key, value) => inputs[key] = value);
      outputMap?.forEach((key, value) => outputs[key] = value);
    }
    if (inputs.isEmpty && outputs.isEmpty) {
      return Text('LATEST SETTLEMENT FLOWS: UNAVAILABLE',
          style: context.widgetFooterStyle.copyWith(color: context.mutedColor));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LATEST SETTLEMENT FLOWS',
            style: context.captionStyle.copyWith(color: context.mutedColor)),
        const SizedBox(height: 4),
        Text('INPUTS  ${_formatUnitMap(inputs.isEmpty ? null : inputs)}',
            style: context.widgetFooterStyle),
        Text('OUTPUTS  ${_formatUnitMap(outputs.isEmpty ? null : outputs)}',
            style: context.widgetFooterStyle),
      ],
    );
  }

  Widget _buildSettlementFlowLine(
      BuildContext context, Map<String, dynamic> building) {
    final inputs = _stringUnitMap(building['settlement_input_units']);
    final outputs = _stringUnitMap(building['settlement_output_units']);
    if (inputs == null && outputs == null) {
      return Text('LATEST SETTLEMENT FLOWS: UNAVAILABLE',
          style: context.widgetFooterStyle.copyWith(color: context.mutedColor));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LATEST SETTLEMENT FLOWS',
            style: context.captionStyle.copyWith(color: context.mutedColor)),
        const SizedBox(height: 4),
        Text('INPUTS  ${_formatUnitMap(inputs)}',
            style: context.widgetFooterStyle),
        Text('OUTPUTS ${_formatUnitMap(outputs)}',
            style: context.widgetFooterStyle),
      ],
    );
  }

  Widget _buildBuildingEconomicsSummary(
    BuildContext context, {
    required Map<String, dynamic> building,
    required double effectiveOutputAmount,
    required double effectiveOperatingCost,
    required bool isActive,
  }) {
    final settlementDay = building['latest_settlement_game_day'];
    final settlementStatus =
        building['latest_settlement_status']?.toString() ?? 'UNAVAILABLE';
    final operatingCreditUnits = building['settlement_operating_credit_units'];
    final utilizationBps = asInt(building['utilization_bps']);
    final utilization = utilizationBps == null
        ? 'UNAVAILABLE'
        : '${(utilizationBps / 100).toStringAsFixed(1)}%';
    final latestSettlement = settlementDay == null
        ? 'UNAVAILABLE'
        : 'Day $settlementDay · $settlementStatus';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding * .75),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: context.primaryColor.withValues(alpha: .18)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          _buildingClarityMetric(
            context,
            label: 'Latest settlement',
            value: latestSettlement,
            icon: Icons.event_available_outlined,
            color: context.primaryColor,
          ),
          _buildingClarityMetric(
            context,
            label: 'Operating CREDIT cost',
            value: formatCreditUnits(operatingCreditUnits),
            icon: Icons.payments_outlined,
            color: context.warningColor,
          ),
          _buildingClarityMetric(
            context,
            label: 'Utilization',
            value: utilization,
            icon: Icons.speed_outlined,
            color: utilizationBps == null
                ? context.mutedColor
                : context.successColor,
          ),
        ],
      ),
    );
  }

  Widget _buildingClarityMetric(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 145, maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: context.captionStyle
                        .copyWith(color: context.mutedColor)),
                const SizedBox(height: 2),
                Text(value,
                    style: context.bodyStyle
                        .copyWith(color: color, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        text,
        style: context.captionStyle.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

}

Future<bool?> showDemolishConfirmDialog(
  BuildContext context,
  dynamic action,
  dynamic building,
) async {
  final bMap = building is Map<String, dynamic>
      ? building
      : (building is Map ? Map<String, dynamic>.from(building) : <String, dynamic>{});
  final buildingId = bMap['id']?.toString() ?? '';
  final buildingName = bMap['name']?.toString() ?? 'Facility';
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Demolish Facility'),
      content: Text(
          'Are you sure you want to demolish $buildingName? Its House or Corporation capacity will be released according to the server settlement.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton(
          onPressed: () async {
            if (action is Function) {
              try {
                await (action as dynamic)('demolish_building', {'buildingId': buildingId});
              } catch (_) {
                try {
                  await (action as dynamic)(() async {
                    await const EarthApi().demolishBuilding(buildingId: buildingId);
                    return const EarthApi().world();
                  });
                } catch (_) {}
              }
            }
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          },
          child: const Text('DEMOLISH & RECYCLE'),
        ),
      ],
    ),
  );
}
