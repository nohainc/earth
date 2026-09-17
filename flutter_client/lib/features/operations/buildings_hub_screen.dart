import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../core/nano_markup_helper.dart';
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
  int _mainTab = 0; // 0 = PRIVATE, 1 = CIVIC (single-column mode only)
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

  double? _settlementNetCredits(Map<String, dynamic> building) {
    return asDouble(building['settlement_net_credits']);
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
                          final cost =
                              option['creditCostUnits']?.toString() ?? '0';
                          final payback = option['paybackGameDays'];
                          final label = option['type']?.toString() ?? 'OPTION';
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              '$label · $cost credit units · ${payback == null ? 'no positive payback' : '$payback game days'}',
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
    bool publicInvestment = false,
  }) async {
    EarthAudioEngine.instance.playClick();
    final Map<String, dynamic> quote;
    try {
      quote = await const EarthApi().quoteV5Building(buildingType);
    } catch (error) {
      _showBuildingFeedback(
          'Authoritative V5 construction quote unavailable: ${error.toString().replaceFirst('Exception: ', '')}');
      return;
    }
    final quotedCreditCost =
        int.tryParse(quote['creditCostUnits']?.toString() ?? '');
    final quotedFootprint =
        int.tryParse(quote['footprintUnits']?.toString() ?? '');
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
            ? 'Open investment project: $buildingName'
            : 'Build $buildingName');
    final body = TextEditingController(
        text: publicInvestment
            ? 'Corporation-governed public construction for $buildingName. The Corporation Treasury will fund the pooled-capacity project.'
            : 'Corporation-governed civic construction for $buildingName. The Corporation Treasury will fund the pooled-capacity project.');
    final iconColor =
        publicInvestment ? Colors.lightBlueAccent : Colors.purpleAccent;

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
                    publicInvestment
                        ? 'Propose Public Investment'
                        : 'Propose Civic Building',
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
                        Text('${formatWholeNumber(quotedCreditCost)} C',
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
                await widget.action(() => const EarthApi().purchaseV5Building(
                      buildingType: buildingType,
                      name: title.text.trim(),
                    ));
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
    final shares = widget.state.investmentShares
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final dividends = widget.state.civicDividends
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final catalog = widget.state.buildingCatalog;
    final zoning = widget.state.districtZoning;
    final rawCityId = widget.state.membership?['territory_id']?.toString() ??
        // Read-only compatibility for older local snapshots; the backend V4
        // field remains territory_id and no synthetic ID is ever generated.
        widget.state.membership?['city_id']?.toString();
    final isIndependent =
        rawCityId == null || rawCityId.isEmpty || rawCityId == 'Independent';
    // V4 is territory-scoped. Never invent a location identifier when the
    // viewer has no active residency.
    final cityId = rawCityId ?? '';
    final viewerId = widget.state.human['id']?.toString();

    final privateBuildings = buildings
        .where((b) => b['owner_id'] == viewerId && b['status'] != 'closed')
        .toList();
    final publicBuildings = buildings
        .where((b) =>
            b['ownership_class'] == 'public_investment' &&
            b['status'] != 'closed')
        .toList();
    final civicBuildings = buildings
        .where(
            (b) => b['ownership_class'] == 'civic' && b['status'] != 'closed')
        .toList();

    // Personal estate plot capacity:
    // 10 slots per tier (Tier 1 = 10, Tier 2 = 20, Tier 3 = 30, Tier 4 = 40)
    final estateBuilding =
        privateBuildings.cast<Map<String, dynamic>?>().firstWhere(
              (b) => b?['building_type'] == 'private-estate-plot',
              orElse: () => null,
            );
    final estateTier = asIntOr(estateBuilding?['tier'], 1);
    final personalTotalSlots = estateTier * 10;
    // Calculate personal used slots from private buildings footprint (excluding the estate deed itself)
    final personalUsedSlots = privateBuildings.fold<int>(
      0,
      (sum, b) =>
          sum +
          (b['building_type'] == 'private-estate-plot'
              ? 0
              : asIntOr(b['slot_footprint'], 1)),
    );
    final personalAvailableSlots =
        math.max(0, personalTotalSlots - personalUsedSlots);

    final civicReservedSlots = asIntOr(zoning['civicReservedSlots'], 3);
    final usedCivicSlots = asIntOr(zoning['usedCivicSlots'], 0);
    final population = asIntOr(zoning['population'], 12);
    final creditsAvailable = asDouble(
      widget.state.human['credits'] ??
          widget.state.finance['balance'] ??
          widget.state.personalFinance['balance'],
    );
    final materialsAvailable = asDouble(
      widget.state.resources['materials'] ?? widget.state.resources['material'],
    );

    // Civic summary stats
    final lastDividend = dividends.isNotEmpty ? dividends.last : null;
    final lastUbi = lastDividend != null
        ? asDoubleOr(lastDividend['base_ubi_per_resident_crd'], 0)
        : 0.0;
    final totalMyShares =
        shares.fold<int>(0, (sum, s) => sum + asIntOr(s['shares_owned'], 0));

    return EarthSection(
      title: 'BUILDINGS',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Buildings are the productive assets of the economy: they use resources, provide services, and generate returns.',
        'Private buildings belong to you and generate personal income. Public and civic buildings are Corporation-governed assets that consume pooled capacity and follow Earth and Corporation fiscal rules.',
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
            totalSlots: personalTotalSlots,
            civicReservedSlots: civicReservedSlots,
            usedPrivateSlots: personalUsedSlots,
            usedCivicSlots: usedCivicSlots,
            availablePrivateSlots: personalAvailableSlots,
            population: population,
            cityId: cityId,
            creditsAvailable: creditsAvailable,
            materialsAvailable: materialsAvailable,
            viewerId: viewerId,
          );

          final civicPanel = _buildCivicPanel(
            context,
            publicBuildings: publicBuildings,
            civicBuildings: civicBuildings,
            catalog: catalog,
            viewerId: viewerId,
            shares: shares,
            dividends: dividends,
            usedCivicSlots: usedCivicSlots,
            civicReservedSlots: civicReservedSlots,
            totalMyShares: totalMyShares,
            lastUbi: lastUbi,
          );

          final effectiveTab = isIndependent ? 0 : _mainTab;
          final selectedBuilt = effectiveTab == 0 ? privatePanel : civicPanel;
          final selectedCatalog = _buildCatalogTab(context,
              catalog: catalog,
              availablePrivateSlots: personalAvailableSlots,
              ownershipFilter: effectiveTab == 0 ? 'private' : 'civic');
          final civicBuildingsCount = civicBuildings.length;
          final mainTabs = isIndependent
              ? const SizedBox.shrink()
              : _buildMainOwnershipTabs(context);

          final cockpit = EarthPageCockpit(
            status: isIndependent
                ? 'INDEPENDENT HOLDINGS'
                : 'REAL ESTATE & INFRASTRUCTURE',
            statusColor:
                isIndependent ? context.warningColor : context.primaryColor,
            infoTitle: 'REAL ESTATE & INFRASTRUCTURE ARCHITECTURE',
            infoDescription:
                '• Private Buildings: Belong to you. Their output goes to your account, while upkeep and operating costs are paid by you.\n\n• Public and Civic Buildings: Are Corporation-governed pooled-capacity assets. Construction, operation, and surplus follow authoritative Earth and Corporation rules; Territory records describe physical placement only.',
            title: 'BUILDINGS & REAL ESTATE',
            subtitle:
                'Productive property assets, personal estate capacity, and municipal civic zoning across Earth',
            metrics: [
              CockpitMetric(
                label: 'Private Assets',
                value: '${privateBuildings.length}',
                icon: Icons.home_work_outlined,
                color: context.primaryColor,
              ),
              CockpitMetric(
                label: 'Civic Assets',
                value: '$civicBuildingsCount',
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
                      totalSlots: personalTotalSlots,
                      civicReservedSlots: civicReservedSlots,
                      usedPrivateSlots: personalUsedSlots,
                      usedCivicSlots: usedCivicSlots,
                      availablePrivateSlots: personalAvailableSlots,
                      population: population,
                      cityId: cityId,
                      creditsAvailable: creditsAvailable,
                      materialsAvailable: materialsAvailable,
                      viewerId: viewerId,
                      showSubTabs: true,
                      contentTab: _narrowSubTab,
                      showPanelTitle: false)
                  : _buildCivicPanel(context,
                      publicBuildings: publicBuildings,
                      civicBuildings: civicBuildings,
                      catalog: catalog,
                      viewerId: viewerId,
                      shares: shares,
                      dividends: dividends,
                      usedCivicSlots: usedCivicSlots,
                      civicReservedSlots: civicReservedSlots,
                      totalMyShares: totalMyShares,
                      lastUbi: lastUbi,
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
                title: 'CIVIC',
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
    required int totalSlots,
    required int civicReservedSlots,
    required int usedPrivateSlots,
    required int usedCivicSlots,
    required int availablePrivateSlots,
    required int population,
    required String cityId,
    required double? creditsAvailable,
    required double? materialsAvailable,
    required String? viewerId,
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
        // Private stat header
        _buildAttributeGrid(
          context,
          [
            (
              'OPEN SPACES',
              '$availablePrivateSlots',
              Icons.domain_add_outlined,
              availablePrivateSlots > 0
                  ? context.successColor
                  : context.dangerColor
            ),
            (
              'SPACES USED',
              '$usedPrivateSlots',
              Icons.pie_chart_outline,
              context.warningColor
            ),
          ],
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
            totalSlots: totalSlots,
            civicReserved: civicReservedSlots,
            usedPrivate: usedPrivateSlots,
            usedCivic: usedCivicSlots,
            population: population,
            viewerId: viewerId,
          ),
        ] else
          _buildCatalogTab(context,
              catalog: catalog,
              availablePrivateSlots: availablePrivateSlots,
              ownershipFilter: 'private'),
      ],
    );
  }

  // ─── CIVIC panel ───────────────────────────────────────────────────────────
  Widget _buildCivicPanel(
    BuildContext context, {
    required List<Map<String, dynamic>> publicBuildings,
    required List<Map<String, dynamic>> civicBuildings,
    required List<dynamic> catalog,
    required String? viewerId,
    required List<Map<String, dynamic>> shares,
    required List<Map<String, dynamic>> dividends,
    required int usedCivicSlots,
    required int civicReservedSlots,
    required int totalMyShares,
    required double lastUbi,
    bool showSubTabs = false,
    int contentTab = 0,
    bool showPanelTitle = true,
  }) {
    final allCivicBuildings = [...civicBuildings, ...publicBuildings];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('CIVIC BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        // Civic stat header
        _buildAttributeGrid(
          context,
          [
            (
              'OPEN SPACES',
              '${(civicReservedSlots - usedCivicSlots).clamp(0, civicReservedSlots)}',
              Icons.domain_add_outlined,
              usedCivicSlots < civicReservedSlots
                  ? context.successColor
                  : context.dangerColor
            ),
            (
              'SPACES USED',
              '$usedCivicSlots',
              Icons.pie_chart_outline,
              context.warningColor
            ),
          ],
        ),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, allCivicBuildings),
        if (publicBuildings.isNotEmpty) ...[
          SizedBox(height: context.spacingControl),
          _buildInvestmentPortfolioSummary(
              context, publicBuildings, shares, totalMyShares),
        ],
        SizedBox(height: context.spacingControl),
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['BUILT', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0) ...[
          allCivicBuildings.isEmpty
              ? const EarthEmptyState(
                  message: 'No civic or public investment buildings built.',
                  icon: Icons.account_balance_outlined)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = _buildGroupedBuildingCards(
                        context, allCivicBuildings, viewerId, catalog,
                        investmentShares: shares);
                    return _buildResponsiveBuildingCards(
                        cards, constraints.maxWidth);
                  },
                ),
        ] else
          _buildCatalogTab(context, catalog: catalog, ownershipFilter: 'civic'),
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
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _buildBuildingRecommendation(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required int availablePrivateSlots,
  }) {
    final needsAttention = privateBuildings.where((building) {
      return building['status']?.toString() == 'under_construction';
    }).toList();

    final String title;
    final String message;
    final IconData icon;
    final Color color;
    if (needsAttention.isNotEmpty) {
      final buildingName =
          needsAttention.first['name']?.toString() ?? 'A building';
      title = 'Review $buildingName';
      message =
          'A building needs attention. Open Manage Building to restore performance or finish commissioning.';
      icon = Icons.warning_amber_outlined;
      color = context.warningColor;
    } else if (privateBuildings.isEmpty) {
      title = 'Create your first productive asset';
      message =
          'Start with a building that matches your available Credits, Materials, and territory capacity.';
      icon = Icons.domain_add_outlined;
      color = context.primaryColor;
    } else if (availablePrivateSlots > 0) {
      title = 'Capacity is available';
      message =
          '$availablePrivateSlots private building space${availablePrivateSlots == 1 ? '' : 's'} remain. Compare the next building in Build.';
      icon = Icons.trending_up_outlined;
      color = context.successColor;
    } else {
      title = 'Buildings are operating normally';
      message =
          'Private capacity is full. Improve territory infrastructure before expanding further.';
      icon = Icons.check_circle_outline;
      color = context.successColor;
    }

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.widgetTitleStyle),
                const SizedBox(height: 3),
                Text(message, style: context.widgetFooterStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: MY BUILDINGS ====================
  Widget _buildEstatesTab(
    BuildContext context, {
    required List<Map<String, dynamic>> privateBuildings,
    required List<dynamic> catalog,
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
    required String? viewerId,
  }) {
    final filteredBuildings = _selectedCategory == 'all'
        ? privateBuildings.where((b) => b['status'] != 'closed').toList()
        : privateBuildings.where((b) {
            if (b['status'] == 'closed') return false;
            final cat = b['category']?.toString() ?? '';
            if (_selectedCategory == 'profitable') {
              final netCredits = _settlementNetCredits(b);
              return netCredits != null && netCredits > 0;
            }
            if (_selectedCategory == 'attention') {
              return b['status']?.toString() == 'under_construction';
            }
            if (_selectedCategory == 'commercial') return cat == 'commercial';
            if (_selectedCategory == 'energy') return cat == 'energy';
            if (_selectedCategory == 'manufacturing') {
              return cat == 'manufacturing' || cat == 'industrial';
            }
            if (_selectedCategory == 'compute') {
              return cat == 'compute' || cat == 'high_tech';
            }
            if (_selectedCategory == 'food') return cat == 'food';
            if (_selectedCategory == 'medical') return cat == 'medical';
            if (_selectedCategory == 'orbital') return cat == 'orbital';
            return true;
          }).toList();

    if (_sortMode == 'profit') {
      filteredBuildings.sort((a, b) {
        final aValue = _settlementNetCredits(a);
        final bValue = _settlementNetCredits(b);
        if (aValue == null && bValue == null) return 0;
        if (aValue == null) return 1;
        if (bValue == null) return -1;
        return bValue.compareTo(aValue);
      });
    } else if (_sortMode == 'upkeep') {
      filteredBuildings.sort((a, b) =>
          asDoubleOr(a['daily_operating_credits'], 0)
              .compareTo(asDoubleOr(b['daily_operating_credits'], 0)));
    } else if (_sortMode == 'attention') {
      filteredBuildings.sort((a, b) {
        final aScore = a['status']?.toString() == 'under_construction' ? 0 : 1;
        final bScore = b['status']?.toString() == 'under_construction' ? 0 : 1;
        return aScore.compareTo(bScore);
      });
    } else if (_sortMode == 'resource') {
      filteredBuildings.sort((a, b) =>
          asDoubleOr(b['resource_output_amount'], 0)
              .compareTo(asDoubleOr(a['resource_output_amount'], 0)));
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
            _buildingListFilterChip(context, 'PROFITABLE', 'profitable'),
            _buildingListFilterChip(context, 'ATTENTION', 'attention'),
            _buildingListSortChip(context, 'DEFAULT', 'default'),
            _buildingListSortChip(context, 'PROFIT', 'profit'),
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
                    : _selectedCategory == 'profitable'
                        ? 'No owned buildings are currently generating a positive daily credit margin.'
                        : 'No owned buildings match this category. Build one to expand your productive capacity.',
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
    List<dynamic> catalog, {
    List<Map<String, dynamic>>? investmentShares,
  }) {
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
          items.fold<int>(0, (sum, b) => sum + asIntOr(b['slot_footprint'], 1));
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
      final isCivic = first['ownership_class'] == 'civic' ||
          first['ownership_class'] == 'public_investment';
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
          .map((b) => b['operating_policy']?.toString() ?? 'balanced')
          .toSet();
      final commonPolicy = policies.length == 1 ? policies.first : 'mixed';
      final isEstatePlot = first['building_type'] == 'private-estate-plot';
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
                                      '$totalSpace ${totalSpace == 1 ? "SPACE" : "SPACES"}',
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
                    child: _buildNetResourceLine(context,
                        building: const {},
                        effectiveOutputAmount: 0,
                        effectiveOperatingCost: 0,
                        resourceChanges: _resourceChangesForBuildings(items),
                        settlementReadModelExpected: true),
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
                                    'Normal uses standard output and operating cost. Frugal reduces output by 25% and operating cost by 30%. High output increases output by 30% and operating cost by 40%.')),
                            Wrap(
                              spacing: 4,
                              children: [
                                for (final policyOption in const [
                                  {
                                    'id': 'BALANCED',
                                    'label': 'Normal',
                                    'help':
                                        'Standard output and operating cost.'
                                  },
                                  {
                                    'id': 'CONSERVATIVE',
                                    'label': 'Conservative',
                                    'help': 'Server-defined conservative operating policy.'
                                  },
                                  {
                                    'id': 'GROWTH',
                                    'label': 'Growth',
                                    'help': 'Server-defined growth operating policy.'
                                  },
                                ])
                                  Tooltip(
                                    message: policyOption['help']!,
                                    child: InkWell(
                                      onTap: widget.busy ||
                                              commonPolicy == policyOption['id']
                                          ? null
                                          : () async {
                                              final preview = await const EarthApi()
                                                  .quoteBuildingOperatingPolicy(
                                                      buildingId: items.first['id'].toString());
                                              final allowed = (preview['allowedModes'] as List?)
                                                  ?.map((mode) => mode.toString())
                                                  .toSet();
                                              if (allowed == null || !allowed.contains(policyOption['id'])) {
                                                _showBuildingFeedback('This operating policy is not available for the group.');
                                                return;
                                              }
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
                    investmentShares: investmentShares,
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
    required int availablePrivateSlots,
    required String cityId,
    required int population,
    required double? creditsAvailable,
    required double? materialsAvailable,
  }) {
    final blueprints = catalog.whereType<Map>().where((b) {
      final bType = b['building_type'] ?? b['type'];
      if (bType == 'private-estate-plot' || bType == 'urban-district-module') {
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
    final footprint = asIntOr(
        currentSpec['slot_footprint'] ?? currentSpec['slotFootprint'], 1);
    final creditCost = asInt(currentSpec['cost_credits']);
    final materialCost = asInt(currentSpec['cost_materials']);
    final dailyYield = asDouble(currentSpec['output_credits']);
    final opCost = asDouble(currentSpec['operating_credits']);
    final netDailyProfit = dailyYield != null && opCost != null
        ? dailyYield - opCost
        : null;
    final paybackDays = asInt(currentSpec['estimatedPaybackDays']);
    final sensitivity =
        currentSpec['resourceSensitivity']?.toString().toUpperCase() ??
            'MEDIUM';
    final risk =
        currentSpec['maintenanceRisk']?.toString().toUpperCase() ?? 'LOW';
    final purpose =
        currentSpec['primaryEconomicPurpose']?.toString() ?? 'Economic Output';
    final reqPop = asIntOr(currentSpec['minCityPopulation'], 0);

    final hasEnoughSlots = availablePrivateSlots >= footprint;
    final hasEnoughPop = reqPop == 0 || population >= reqPop;
    final hasEnoughCredits = creditCost != null &&
        (creditsAvailable == null || creditsAvailable >= creditCost);
    final hasEnoughMaterials = materialCost != null &&
        (materialsAvailable == null || materialsAvailable >= materialCost);
    final canConstruct = _hasActiveCorporation
        ? creditCost != null && materialCost != null
        : hasEnoughSlots &&
            hasEnoughPop &&
            hasEnoughCredits &&
            hasEnoughMaterials &&
            creditCost != null &&
            materialCost != null;

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
              final bSpace =
                  asIntOr(b['slot_footprint'] ?? b['slotFootprint'], 1);
              final bCost = asInt(b['cost_credits']);
              final bOutput = asDouble(b['output_credits']);
              final bUpkeep = asDouble(b['operating_credits']);
              final bResourceType = b['resource_output_type']?.toString();
              final bResourceAmount = asDouble(
                  bResourceType == null ? null : b['output_$bResourceType']);
              final cardHasCapacity = availablePrivateSlots >= bSpace;
              final cardHasCredits = bCost != null &&
                  (creditsAvailable == null || creditsAvailable >= bCost);
              final bMaterialCost = asInt(b['cost_materials']);
              final cardHasMaterials = bMaterialCost != null &&
                  (materialsAvailable == null ||
                      materialsAvailable >= bMaterialCost);
              final cardCanBuild =
                  cardHasCapacity && cardHasCredits && cardHasMaterials;
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
                            '$bSpace capacity space${bSpace > 1 ? 's' : ''} · ${bCost == null ? 'SERVER QUOTE REQUIRED' : '${formatWholeNumber(bCost)} CRD'}',
                            style: context.widgetFooterStyle),
                        const SizedBox(height: 4),
                        Text(
                          bResourceAmount != null &&
                                  bResourceAmount > 0 &&
                                  bResourceType != null &&
                                  bResourceType != 'credits'
                              ? 'Output: +${bResourceAmount.toStringAsFixed(1)} ${bResourceType.toUpperCase()}/day'
                              : bOutput != null && bUpkeep != null
                                  ? 'Net: ${bOutput - bUpkeep >= 0 ? '+' : ''}${formatWholeNumber(bOutput - bUpkeep)} CRD/day'
                                  : 'Net: SERVER QUOTE REQUIRED',
                          style: context.bodyStyle.copyWith(
                            color: bResourceAmount != null &&
                                    bResourceAmount > 0 &&
                                    bResourceType != null &&
                                    bResourceType != 'credits'
                                ? context.secondaryColor
                                : bOutput != null && bUpkeep != null &&
                                        bOutput - bUpkeep >= 0
                                    ? context.successColor
                                    : context.dangerColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Operating cost: ${bUpkeep == null ? 'SERVER QUOTE REQUIRED' : '-${formatWholeNumber(bUpkeep)} CRD/day'}',
                          style: context.widgetFooterStyle.copyWith(
                            color: bUpkeep != null && bUpkeep > 0
                                ? context.warningColor
                                : context.mutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cardCanBuild
                              ? 'AVAILABLE TO BUILD'
                              : !cardHasCapacity
                                  ? 'CAPACITY UNAVAILABLE'
                                  : !cardHasCredits
                                      ? 'CREDITS REQUIRED'
                                      : 'MATERIALS REQUIRED',
                          style: context.captionStyle.copyWith(
                            color: cardCanBuild
                                ? context.successColor
                                : context.warningColor,
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
                          '$footprint CAPACITY SPACE${footprint > 1 ? 'S' : ''}',
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
                      label: 'PROJECTED NET DAILY',
                                      value: netDailyProfit == null
                                          ? 'UNAVAILABLE'
                                          : '+${formatWholeNumber(netDailyProfit)} CRD',
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
                            'Building Capacity (Requires $footprint space${footprint > 1 ? 's' : ''})',
                            hasEnoughSlots,
                          ),
                          _buildRequirementItem(
                            context,
                            creditsAvailable == null
                                ? creditCost == null
                                    ? 'Credits: SERVER QUOTE REQUIRED'
                                    : 'Credits: ${formatWholeNumber(creditCost ?? 0)} required'
                                : creditCost == null
                                    ? 'Credits: SERVER QUOTE REQUIRED'
                                    : 'Credits: ${formatWholeNumber(creditCost ?? 0)} required · ${formatWholeNumber(creditsAvailable)} available',
                            hasEnoughCredits,
                          ),
                          _buildRequirementItem(
                            context,
                            materialsAvailable == null
                                ? materialCost == null
                                    ? 'Materials: SERVER QUOTE REQUIRED'
                                    : 'Materials: $materialCost required'
                                : materialCost == null
                                    ? 'Materials: SERVER QUOTE REQUIRED'
                                    : 'Materials: $materialCost required · ${formatWholeNumber(materialsAvailable)} available',
                            hasEnoughMaterials,
                          ),
                          if (reqPop > 0)
                            _buildRequirementItem(
                              context,
                              'City Population ($population / $reqPop)',
                              hasEnoughPop,
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
                              final pDays = math.max(
                                1,
                                asIntOr(
                                  currentSpec['construction_days'],
                                  footprint * asIntOr(currentSpec['tier'], 1),
                                ),
                              );

                              await _confirmConstruction(
                                context,
                                buildingName: name,
                                buildingType: _plannerSelectedBlueprint,
                                cityId: cityId,
                                creditCost: creditCost ?? 0,
                                materialCost: materialCost ?? 0,
                                capacityCost: footprint,
                                remainingCapacity:
                                    availablePrivateSlots - footprint,
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
    required String cityId,
    required int creditCost,
    required int materialCost,
    required int capacityCost,
    required int remainingCapacity,
    int constructionDays = 1,
    required List<(IconData, Color, String, bool)> netYields,
  }) async {
    EarthAudioEngine.instance.playClick();
    var quotedCreditCost = creditCost;
    var quotedMaterialCost = materialCost;
    var quotedCapacityCost = capacityCost;
    var quotedRemainingCapacity = remainingCapacity;
    var quotedConstructionDays = constructionDays;
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
        ? (quote['blockers'] as List).whereType<Object>().join('; ')
        : '';
    if (quote['eligible'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(blockers.isEmpty
              ? 'Construction is not currently eligible.'
              : blockers)));
      return;
    }
    quotedCreditCost = asInt(quote['creditCostUnits']) ?? 0;
    quotedCapacityCost = asInt(quote['footprintUnits']) ?? 0;
    if (quote['capacity'] is Map) {
      quotedCapacityQuote = Map<String, dynamic>.from(quote['capacity'] as Map);
    }
    quotedConstructionDays = math.max(
        1,
        ((asInt(quote['effectiveConstructionMinutes']) ?? 0) / 1440).ceil());
    final requirements = quote['resourceRequirements'] is List
        ? (quote['resourceRequirements'] as List).whereType<Map>()
        : const <Map>[];
    quotedMaterialCost = requirements
        .where((item) => (item['code']?.toString() ?? '').toUpperCase() == 'MATERIAL')
        .fold<int>(0, (sum, item) => sum + (asInt(item['requiredUnits']) ?? 0));
    quotedRemainingCapacity = math.max(0, remainingCapacity);
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
                'Review this property investment before starting construction on your private district plot.',
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
                        Text('Construction Cost:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 14, color: EarthResourceColors.credits),
                        const SizedBox(width: 4),
                        Text('${formatWholeNumber(quotedCreditCost)} C',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: context.inkColor,
                            )),
                        if (quotedMaterialCost > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.terrain_outlined,
                              size: 14, color: EarthResourceColors.materials),
                          const SizedBox(width: 3),
                          Text('${formatWholeNumber(quotedMaterialCost)} Mat',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: context.inkColor,
                              )),
                        ],
                      ],
                    ),
                    if (quotedCapacityQuote.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Capacity rent after construction: ${quotedCapacityQuote['afterChargeUnits'] ?? '—'} units/day · incremental ${quotedCapacityQuote['incrementalChargeUnits'] ?? '—'}',
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
                              '${quotedConstructionDays}d',
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
                        Text('Plot Capacity:',
                            style: TextStyle(
                                fontSize: 12, color: context.mutedColor)),
                        const Spacer(),
                        Icon(Icons.layers_outlined,
                            size: 14, color: context.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          '$quotedCapacityCost ${quotedCapacityCost == 1 ? "Space" : "Spaces"} ($quotedRemainingCapacity remaining)',
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
            onPressed: () => Navigator.of(dialogContext).pop(true),
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

  bool _hasActiveProposalForBuilding(String buildingType) {
    final proposals =
        (widget.state.governance['proposals'] as List<dynamic>?) ?? const [];
    for (final raw in proposals) {
      if (raw is! Map ||
          raw['target_category']?.toString() != 'megaproject_procurement') {
        continue;
      }
      final status = raw['status']?.toString().toLowerCase();
      final outcome = raw['outcome']?.toString().toLowerCase();
      final executionStatus = raw['execution_status']?.toString().toLowerCase();
      final isActive = status == 'open' ||
          (outcome == 'passed' &&
              raw['executed_at'] == null &&
              (executionStatus == 'ready' || executionStatus == 'queued'));
      if (!isActive) continue;
      final target = raw['target_value_json'];
      final decoded = target is Map
          ? Map<String, dynamic>.from(target)
          : target is String
              ? NanoMarkupHelper.decode(target)
              : null;
      if (decoded is Map &&
          decoded['buildingType']?.toString() == buildingType) {
        return true;
      }
    }
    return false;
  }

  bool _hasAuthoritativeCatalogEconomics(Map<String, dynamic> item) {
    return asInt(item['tier']) != null &&
        asInt(item['slot_footprint'] ?? item['slotFootprint']) != null &&
        asInt(item['cost_credits'] ?? item['baseCreditCost']) != null &&
        asInt(item['cost_materials'] ?? item['baseMaterialCost']) != null &&
        asInt(item['construction_days']) != null;
  }

  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
    int? availablePrivateSlots,
    String? ownershipFilter,
  }) {
    final allCatalogMaps = catalog
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((item) {
          final bType = (item['building_type'] ?? item['type'])?.toString();
          return bType != 'private-estate-plot' &&
              bType != 'urban-district-module';
        })
        .toList();

    // Construction decisions must never be based on fabricated client-side
    // economics. Incomplete catalog rows remain unavailable until the server
    // publishes the complete authoritative blueprint.
    allCatalogMaps.removeWhere((item) => !_hasAuthoritativeCatalogEconomics(item));

    // Only display root blueprints (tier 1 or prev_catalog_id is null) in the catalog blueprints view
    final rootBlueprints = allCatalogMaps.where((item) {
      final prevId = item['prev_catalog_id'];
      final tier = asInt(item['tier'])!;
      return (prevId == null || prevId.toString().isEmpty) && tier == 1;
    }).toList();

    final privateBuildings = widget.state.buildings
        .whereType<Map>()
        .where((b) =>
            b['owner_id'] == widget.state.human['id']?.toString() &&
            b['status'] != 'closed')
        .toList();
    final estateBuilding =
        privateBuildings.cast<Map<String, dynamic>?>().firstWhere(
              (b) => b?['building_type'] == 'private-estate-plot',
              orElse: () => null,
            );
    final estateTier = asIntOr(estateBuilding?['tier'], 1);
    final personalTotalSlots = estateTier * 10;
    final personalUsedSlots = privateBuildings.fold<int>(
      0,
      (sum, b) =>
          sum +
          (b['building_type'] == 'private-estate-plot'
              ? 0
              : asIntOr(b['slot_footprint'], 1)),
    );
    final personalAvailableSlots =
        math.max(0, personalTotalSlots - personalUsedSlots);

    final zoning = widget.state.districtZoning;
    final effAvailablePrivateSlots =
        availablePrivateSlots ?? personalAvailableSlots;
    final availableCivicSlots = asInt(zoning['public_slot_capacity']) == null
        ? null
        : math.max(
            0,
            asIntOr(zoning['public_slot_capacity'], 0) -
                asIntOr(zoning['public_slots_used'], 0));
    final cityId = widget.state.membership?['territory_id']?.toString() ??
        widget.state.membership?['city_id']?.toString();
    final creditsAvailable = asDouble(widget.state.human['credits'] ??
        widget.state.finance['balance'] ??
        widget.state.personalFinance['balance']);
    final materialsAvailable = asDouble(widget.state.resources['materials'] ??
        widget.state.resources['material']);

    rootBlueprints.sort((a, b) {
      final aCost = asDouble(a['cost_credits'] ?? a['baseCreditCost'])!;
      final bCost = asDouble(b['cost_credits'] ?? b['baseCreditCost'])!;
      final costCompare = aCost.compareTo(bCost);
      if (costCompare != 0) return costCompare;
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

    final civicCount = rootBlueprints.where((item) {
      final ownership = item['ownership_class']?.toString() ??
          item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString();
      return ownership == 'civic';
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
      if (_catalogFilter == 'civic') {
        return ownership == 'civic';
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
                  label: 'CIVIC ($civicCount)', filter: 'civic'),
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
                  asInt(item['slot_footprint'] ?? item['slotFootprint'])!;

              // Group count: total upgrades/tiers available in the catalog for this building type
              final groupBuildings = allCatalogMaps
                  .where((b) => (b['building_type'] ?? b['type']) == bType)
                  .toList();
              final tierCount = math.max(1, groupBuildings.length);

              // Costs (24-resource vector)
              final creditCost =
                  asInt(item['cost_credits'] ?? item['baseCreditCost'])!;
              final matCost = asInt(
                  item['cost_materials'] ?? item['baseMaterialCost'])!;
              final compCost = asIntOr(item['cost_components'], 0);
              final computeCost = asIntOr(item['cost_compute'], 0);

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
              final civicBenefit = item['civicBenefit']?.toString();

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
                        ? '${formatWholeNumber(val)} CRD / DAY'
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
                        ? '-${formatWholeNumber(val)} CRD'
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

              final isPublicInvest = ownership == 'public_investment';
              final isCivicMunicipal = ownership == 'civic';
              final componentsAvailable =
                  asDouble(widget.state.resources['components']);
              final computeAvailable =
                  asDouble(widget.state.resources['compute']);
              final canAfford = (creditsAvailable == null ||
                      creditsAvailable >= creditCost) &&
                  (materialsAvailable == null ||
                      materialsAvailable >= matCost) &&
                  (compCost == 0 ||
                      (componentsAvailable != null &&
                          componentsAvailable >= compCost)) &&
                  (computeCost == 0 ||
                      (computeAvailable != null &&
                          computeAvailable >= computeCost));
              final hasSlots = isCivicMunicipal
                  ? availableCivicSlots != null &&
                      availableCivicSlots >= footprint
                  : effAvailablePrivateSlots >= footprint;
              final canBuild = _hasActiveCorporation && !isCivicMunicipal
                  ? true
                  : canAfford && hasSlots;

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
                                                '$footprint ${footprint == 1 ? "SPACE" : "SPACES"}',
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
                                Text(formatWholeNumber(creditCost),
                                    style: context.widgetFooterStyle),
                                if (matCost > 0) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                      EarthResourceMeta.forCommodity(
                                              'materials')
                                          .icon,
                                      size: 14,
                                      color: EarthResourceColors.materials),
                                  Text('$matCost',
                                      style: context.widgetFooterStyle),
                                ],
                                if (compCost > 0) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                      EarthResourceMeta.forCommodity(
                                              'components')
                                          .icon,
                                      size: 14,
                                      color: EarthResourceColors.components),
                                  Text('$compCost',
                                      style: context.widgetFooterStyle),
                                ],
                                if (computeCost > 0) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                      EarthResourceMeta.forCommodity('compute')
                                          .icon,
                                      size: 14,
                                      color: EarthResourceColors.compute),
                                  Text('$computeCost',
                                      style: context.widgetFooterStyle),
                                ],
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                                Text(
                                  '${asInt(item['construction_days'])!}d',
                                  style: context.widgetFooterStyle,
                                ),
                              ],
                            ),

                            // Upkeep line
                            if (inputs.isNotEmpty) ...[
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
                            if (outputs.isNotEmpty) ...[
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
                            if (operatingCredits > 0 ||
                                operatingEnergy > 0 ||
                                operatingFood > 0 ||
                                operatingMaterials > 0 ||
                                operatingComponents > 0 ||
                                operatingCompute > 0) ...[
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
                                        '-${operatingCredits.toStringAsFixed(0)} CRD / DAY',
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

                            // Civic Benefit line
                            if (civicBenefit != null &&
                                civicBenefit.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text('CIVIC BENEFIT',
                                      style: context.captionStyle),
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

                      // Floating big action icon on bottom right
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Builder(
                          builder: (context) {
                            final isCivicOrInvest =
                                isCivicMunicipal || isPublicInvest;
                            final tooltip = isCivicOrInvest
                                ? (isPublicInvest
                                    ? 'Propose Public Project'
                                    : 'Propose Civic Project')
                                : canBuild
                                    ? 'Construct $name'
                                    : !hasSlots
                                        ? 'Insufficient Capacity'
                                        : 'Insufficient Resources';

                            final isActionEnabled = canBuild || isCivicOrInvest;
                            final buttonColor = isActionEnabled
                                ? (isCivicMunicipal
                                    ? Colors.purpleAccent
                                    : isPublicInvest
                                        ? Colors.lightBlueAccent
                                        : context.primaryColor)
                                : Colors.grey[700]!;

                            return Tooltip(
                              message: tooltip,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: isCivicOrInvest
                                      ? () {
                                          _showCivicProposalDialog(
                                            context,
                                            buildingName: name.trim(),
                                            buildingType: bType,
                                            publicInvestment: isPublicInvest,
                                          );
                                        }
                                      : canBuild
                                          ? () {
                                              final cDays =
                                                  asInt(item['construction_days'])!;
                                              final cNetYields = <(
                                                IconData,
                                                Color,
                                                String,
                                                bool
                                              )>[];
                                              final netCredits = outCreditsVal -
                                                  (asDoubleOr(
                                                          item['input_credits'],
                                                          0) +
                                                      operatingCredits);
                                              cNetYields.add((
                                                netCredits >= 0
                                                    ? Icons.trending_up
                                                    : Icons.trending_down,
                                                netCredits >= 0
                                                    ? context.successColor
                                                    : context.dangerColor,
                                                '${netCredits >= 0 ? '+' : ''}${formatWholeNumber(netCredits)} C',
                                                netCredits >= 0,
                                              ));

                                              void addCatalogNet(
                                                  String key,
                                                  String label,
                                                  IconData icon,
                                                  Color color,
                                                  double operatingVal) {
                                                final outVal = asDoubleOr(
                                                    item['output_$key'], 0);
                                                final inVal = asDoubleOr(
                                                        item['input_$key'], 0) +
                                                    operatingVal;
                                                final net = outVal - inVal;
                                                if (net != 0) {
                                                  cNetYields.add((
                                                    icon,
                                                    color,
                                                    '${net > 0 ? '+' : ''}${net.toStringAsFixed(1)} $label',
                                                    net > 0,
                                                  ));
                                                }
                                              }

                                              addCatalogNet(
                                                  'energy',
                                                  'Energy',
                                                  Icons.bolt_rounded,
                                                  EarthResourceColors.energy,
                                                  operatingEnergy);
                                              addCatalogNet(
                                                  'food',
                                                  'Food',
                                                  Icons.eco_outlined,
                                                  EarthResourceColors.food,
                                                  operatingFood);
                                              addCatalogNet(
                                                  'materials',
                                                  'Mat',
                                                  Icons.terrain_outlined,
                                                  EarthResourceColors.materials,
                                                  operatingMaterials);
                                              addCatalogNet(
                                                  'components',
                                                  'Comp',
                                                  Icons
                                                      .precision_manufacturing_outlined,
                                                  EarthResourceColors
                                                      .components,
                                                  operatingComponents);
                                              addCatalogNet(
                                                  'compute',
                                                  'Compute',
                                                  Icons.memory_rounded,
                                                  EarthResourceColors.compute,
                                                  operatingCompute);

                                              if (cNetYields.length == 1) {
                                                final legacyOutType = item[
                                                            'resourceOutputType']
                                                        ?.toString() ??
                                                    item['resource_output_type']
                                                        ?.toString();
                                                final legacyOutAmount = asDoubleOr(
                                                    item['resourceOutputAmount'] ??
                                                        item[
                                                            'resource_output_amount'],
                                                    0);
                                                final legacyInType = item[
                                                            'resourceInputType']
                                                        ?.toString() ??
                                                    item['resource_input_type']
                                                        ?.toString();
                                                final legacyInAmount = asDoubleOr(
                                                    item['resourceInputAmount'] ??
                                                        item[
                                                            'resource_input_amount'],
                                                    0);
                                                if (legacyOutType != null &&
                                                    legacyOutType !=
                                                        'credits' &&
                                                    legacyOutAmount > 0) {
                                                  final net = legacyOutAmount -
                                                      (legacyInType ==
                                                              legacyOutType
                                                          ? legacyInAmount
                                                          : 0);
                                                  cNetYields.add((
                                                    EarthResourceMeta
                                                            .forCommodity(
                                                                legacyOutType)
                                                        .icon,
                                                    EarthResourceMeta
                                                            .forCommodity(
                                                                legacyOutType)
                                                        .color,
                                                    '${net > 0 ? '+' : ''}${net.toStringAsFixed(1)} ${legacyOutType.toUpperCase()}',
                                                    net > 0,
                                                  ));
                                                } else if (legacyInType !=
                                                        null &&
                                                    legacyInType != 'credits' &&
                                                    legacyInAmount > 0) {
                                                  cNetYields.add((
                                                    EarthResourceMeta
                                                            .forCommodity(
                                                                legacyInType)
                                                        .icon,
                                                    EarthResourceMeta
                                                            .forCommodity(
                                                                legacyInType)
                                                        .color,
                                                    '-${legacyInAmount.toStringAsFixed(1)} ${legacyInType.toUpperCase()}',
                                                    false,
                                                  ));
                                                }
                                              }

                                              _confirmConstruction(
                                                context,
                                                buildingName: name,
                                                buildingType: bType,
                                                creditCost: creditCost,
                                                materialCost: matCost,
                                                capacityCost: footprint,
                                                remainingCapacity:
                                                    effAvailablePrivateSlots -
                                                        footprint,
                                                constructionDays: cDays,
                                                netYields: cNetYields,
                                              );
                                            }
                                          : null,
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
                                      isCivicOrInvest
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
      List<Map<String, dynamic>>? investmentShares}) {
    final id = b['id']?.toString() ?? '';
    final name = b['name']?.toString() ?? 'Facility';
    final bType = b['building_type']?.toString() ?? '';
    final tier = asIntOr(b['tier'], 1);
    final policy = b['operating_policy']?.toString() ?? 'balanced';
    final ownershipClass = b['ownership_class']?.toString() ?? 'private';
    final isOwner = b['owner_id']?.toString() == viewerId;
    final isCivic = ownershipClass == 'civic';

    final isPublicInvestment = ownershipClass == 'public_investment';
    Map<String, dynamic>? investmentHolding;
    if (investmentShares != null) {
      for (final share in investmentShares) {
        if (share['building_id']?.toString() == id) {
          investmentHolding = share;
          break;
        }
      }
    }
    final sharesOwned = asIntOr(investmentHolding?['shares_owned'], 0);
    final totalShares = asIntOr(investmentHolding?['total_shares_issued'],
        asIntOr(b['total_shares'], 1000));
    final sharesSold = asIntOr(investmentHolding?['shares_sold'], sharesOwned);
    final availableShares = math.max(0, totalShares - sharesSold);

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
          color: isCivic
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
                      '${itemNumber == null ? '' : '#$itemNumber  ·  '}${asIntOr(b['slot_footprint'], 1)} space${asIntOr(b['slot_footprint'], 1) == 1 ? '' : 's'}  ·  Tier ${asIntOr(b['tier'], 1)}',
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
          _buildNetResourceLine(
            context,
            building: b,
            effectiveOutputAmount: 0,
            effectiveOperatingCost: 0,
            resourceChanges: _settlementResourceChangesForBuilding(b),
          ),
          if (isPublicInvestment) ...[
            const SizedBox(height: 8),
            Text('Available shares: $availableShares / $totalShares',
                style: context.widgetFooterStyle),
            Text('You hold: $sharesOwned', style: context.widgetFooterStyle),
            if (bActive && availableShares > 0)
              Text(
                  'Purchase shares from the Public Projects & Dividends market section.',
                  style: context.widgetFooterStyle),
          ],
          const SizedBox(height: 6),

          // Management actions
          if (isOwner || isCivic || isPublicInvestment)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOwner &&
                    showOperatingPolicy &&
                    bType != 'private-estate-plot') ...[
                  Text(
                    'Operating policy tunes the daily trade-off: Balanced is standard, Frugal lowers upkeep and output, and High output increases both.',
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
                          for (final p in [
                            {'id': 'BALANCED', 'label': 'Balanced'},
                            {
                              'id': 'GROWTH',
                              'label': 'Growth'
                            },
                            {
                              'id': 'CONSERVATIVE',
                              'label': 'Conservative'
                            },
                          ])
                            ChoiceChip(
                              label: Text(p['label']!,
                                  style: const TextStyle(fontSize: 10)),
                              selected: policy == p['id'],
                              visualDensity: VisualDensity.compact,
                              onSelected: widget.busy
                                  ? null
                                  : (selected) async {
                                      if (selected && policy != p['id']) {
                                        EarthAudioEngine.instance.playClick();
                                        final preview = await const EarthApi()
                                            .quoteBuildingOperatingPolicy(buildingId: id);
                                        final allowed = (preview['allowedModes'] as List?)
                                            ?.map((mode) => mode.toString())
                                            .toSet();
                                        if (allowed == null || !allowed.contains(p['id'])) {
                                          _showBuildingFeedback('This operating policy is not available for the building.');
                                          return;
                                        }
                                        await widget.action(() =>
                                            const EarthApi()
                                                .setBuildingOperatingPolicy(
                                              buildingId: id,
                                              policy: p['id']!,
                                            ));
                                        _showBuildingFeedback(
                                            '$name: ${p['label']} policy enabled.');
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
                      if (isOwner && bActive)
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
                              : (isCivic || isPublicInvestment)
                                  ? 'PROPOSE UPGRADE TIER ${tier + 1}'
                                  : 'UPGRADE TO TIER ${tier + 1}',
                          icon: isUnderConstruction
                              ? Icons.hourglass_top_outlined
                              : Icons.arrow_upward_outlined,
                          variant: isUnderConstruction
                              ? EarthButtonVariant.secondary
                              : EarthButtonVariant.primary,
                          onPressed: widget.busy || isUnderConstruction
                              ? null
                              : () async {
                                  EarthAudioEngine.instance.playClick();
                                  if (isCivic || isPublicInvestment) {
                                    await _showCivicProposalDialog(
                                      context,
                                      buildingName:
                                          '$name (Tier ${tier + 1})',
                                      buildingType: bType,
                                      publicInvestment: isPublicInvestment,
                                    );
                                  } else {
                                    final started =
                                        await showBuildingDetailUpgradeDialog(
                                      context,
                                      widget.action,
                                      b,
                                      catalog,
                                    );
                                    if (started == true) {
                                      _showBuildingFeedback(
                                          '$name upgrade started.');
                                    }
                                  }
                                },
                        )
                      else
                        EarthButton(
                          label: isUnderConstruction
                              ? 'UNDER CONSTRUCTION'
                              : hasActiveResearch
                                  ? 'R&D IN PROGRESS (${researchProgressVal.toStringAsFixed(0)}%)'
                                  : (isCivic || isPublicInvestment)
                                      ? 'PROPOSE CIVIC RESEARCH TIER ${tier + 1}'
                                      : 'RESEARCH TIER ${tier + 1}',
                          icon: isUnderConstruction
                              ? Icons.hourglass_top_outlined
                              : hasActiveResearch
                                  ? Icons.hourglass_top_outlined
                                  : (isCivic || isPublicInvestment)
                                      ? Icons.how_to_vote_outlined
                                      : Icons.science_outlined,
                          variant: (isUnderConstruction || hasActiveResearch)
                              ? EarthButtonVariant.secondary
                              : EarthButtonVariant.primary,
                          onPressed: widget.busy ||
                                  isUnderConstruction ||
                                  hasActiveResearch
                              ? null
                              : () => _showBuildingResearchDialog(
                                    context,
                                    building: b,
                                    targetTier: tier + 1,
                                    catalog: catalog,
                                  ),
                        ),
                      if (isOwner &&
                          bType != 'private-estate-plot' &&
                          bType != 'urban-district-module')
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
    if (!context.mounted || quoteResponse['ok'] != true) {
      _showBuildingFeedback(quoteResponse['error']?.toString() ??
          'Authoritative building research quote unavailable.');
      return;
    }
    final serverQuote = quoteResponse['quote'] is Map
        ? Map<String, dynamic>.from(quoteResponse['quote'] as Map)
        : const <String, dynamic>{};
    targetTier = asIntOr(quoteResponse['targetTier'], targetTier);
    final currentTier = asIntOr(quoteResponse['currentTier'],
        asIntOr(building['tier'], 1));
    final currentBlueprint = quoteResponse['currentBlueprint'] is Map
        ? Map<String, dynamic>.from(quoteResponse['currentBlueprint'] as Map)
        : const <String, dynamic>{};
    final serverTarget = quoteResponse['targetBlueprint'] is Map
        ? Map<String, dynamic>.from(quoteResponse['targetBlueprint'] as Map)
        : const <String, dynamic>{};
    final ownership = building['ownership_class']?.toString() ?? 'private';
    if (currentBlueprint.isEmpty || serverTarget.isEmpty) {
      _showBuildingFeedback(
          'The authoritative blueprint comparison is unavailable.');
      return;
    }

    final currentConstructionCost =
        asDouble(currentBlueprint['construction_credit_units']);
    final targetConstructionCost =
        asDouble(serverTarget['construction_credit_units']);
    final costCredits = asDouble(serverQuote['researchCostUnits']);
    final durationDays = asInt(serverQuote['durationDays']);
    if (costCredits == null || durationDays == null) {
      _showBuildingFeedback('The authoritative research quote is incomplete.');
      return;
    }

    final isPrivate = ownership == 'private';
    final fundingSource =
        isPrivate ? 'your personal account' : 'your corporation treasury';

    // Real CapEx values
    final costCreditsCur = currentConstructionCost;
    final costCreditsNext = targetConstructionCost;

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
                    ? 'Starting this research project will charge ${formatCreditsAmount(costCredits)} from $fundingSource to develop Tier $targetTier blueprints.'
                    : 'Submitting this proposal requires no upfront credits. Upon vote passage by the corporation, ${formatCreditsAmount(costCredits)} will be funded from the corporation treasury to develop Tier $targetTier blueprints for the corporation\'s territories.',
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
                          '${costCreditsCur == null ? '—' : formatWholeNumber(costCreditsCur)} → ${costCreditsNext == null ? '—' : formatWholeNumber(costCreditsNext)}',
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
                            '-${formatWholeNumber(opCreditsBase)} → -${formatWholeNumber(opCreditsNext)}',
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
            label: isPrivate ? 'CONFIRM R&D PROJECT' : 'SUBMIT CIVIC PROPOSAL',
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
        final corpId = widget.state.membership?['corporation_id']?.toString() ??
            widget.state.human['corporation_id']?.toString();
        if (corpId == null || corpId.isEmpty) {
          _showBuildingFeedback(
              'A Corporation or Territory authority is required for civic research.');
          return;
        }
        await widget.action(() => const EarthApi().createProposal(
              'Research $bName (Tier $targetTier)',
              'Corporation proposal to research and unlock blueprints for $bName Tier $targetTier. Duration: $durationDays days, Authoritative R&D funding: ${formatWholeNumber(costCredits)} C from corporation treasury.',
              institutionId: corpId,
              targetCategory: 'technology',
              targetValue: {
                'buildingType': bType,
                'targetTier': targetTier,
                'ownershipClass': ownership,
              },
            ));
        _showBuildingFeedback(
            'Corporation proposal to research $bName Tier $targetTier submitted.');
      }
    }
  }

  Widget _buildBuildingsResourceLine(
      BuildContext context, List<Map<String, dynamic>> buildings) {
    return _buildNetResourceLine(context,
        building: const {},
        effectiveOutputAmount: 0,
        effectiveOperatingCost: 0,
        resourceChanges: _resourceChangesForBuildings(buildings),
        settlementReadModelExpected: true);
  }

  Widget _buildInvestmentPortfolioSummary(
      BuildContext context,
      List<Map<String, dynamic>> buildings,
      List<Map<String, dynamic>> shares,
      int totalMyShares) {
    final invested = shares.fold<double>(
        0, (sum, share) => sum + asDoubleOr(share['invested_credits'], 0));
    final reportedDividend = shares.fold<double?>(null, (value, share) {
      final amount = share['daily_dividend_credits'] ??
          share['last_dividend_credits'] ??
          share['dividend_credits'];
      return amount == null ? value : asDoubleOr(amount, value ?? 0);
    });
    final values = [
      (
        'SHARES HELD',
        totalMyShares > 0 ? '$totalMyShares' : 'NONE',
        Icons.bar_chart_outlined,
        totalMyShares > 0 ? context.successColor : context.mutedColor
      ),
      (
        'INVESTED',
        '${formatWholeNumber(invested)} C',
        Icons.payments_outlined,
        context.primaryColor
      ),
      (
        'DAILY DIVIDEND',
        reportedDividend == null
            ? 'SERVER REPORTED'
            : '+${formatWholeNumber(reportedDividend)} C',
        Icons.trending_up_outlined,
        reportedDividend == null || reportedDividend <= 0
            ? context.mutedColor
            : context.successColor
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 16) / 3;
      return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map((item) => SizedBox(
                  width: width,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: .07),
                        borderRadius:
                            BorderRadius.circular(context.radiusControl),
                        border: Border.all(
                            color:
                                context.primaryColor.withValues(alpha: .18))),
                    child: Column(children: [
                      Icon(item.$3, size: 16, color: item.$4),
                      const SizedBox(height: 4),
                      Text(item.$1,
                          textAlign: TextAlign.center,
                          style: context.captionStyle),
                      const SizedBox(height: 2),
                      Text(item.$2,
                          textAlign: TextAlign.center,
                          style:
                              context.widgetValueStyle.copyWith(color: item.$4))
                    ]),
                  )))
              .toList());
    });
  }

  Map<String, double>? _resourceChangesForBuildings(
      List<Map<String, dynamic>> buildings) {
    // Net production is produced by the game-day settlement. The client must
    // not reconstruct it from catalog fields or policy multipliers because
    // that can disagree with the authoritative settlement journal.
    final reported = <String, double>{};
    for (final key in [
      'credits',
      'energy',
      'food',
      'materials',
      'components',
      'compute'
    ]) {
      final field = 'settlement_net_$key';
      if (buildings.any((building) => building[field] != null)) {
        if (buildings.any((building) => building[field] == null)) return null;
        reported[key] = buildings.fold<double>(
            0, (sum, building) => sum + (asDouble(building[field]) ?? 0));
      }
    }
    return reported.length == 6 ? reported : null;
  }

  Map<String, double>? _settlementResourceChangesForBuilding(
      Map<String, dynamic> building) {
    const keys = [
      'credits',
      'energy',
      'food',
      'materials',
      'components',
      'compute'
    ];
    final values = <String, double>{};
    for (final key in keys) {
      final value = asDouble(building['settlement_net_$key']);
      if (value == null) return null;
      values[key] = value;
    }
    return values;
  }

  Widget _buildNetResourceLine(
    BuildContext context, {
    required Map<String, dynamic> building,
    required double effectiveOutputAmount,
    required double effectiveOperatingCost,
    Map<String, double>? resourceChanges,
    bool settlementReadModelExpected = false,
  }) {
    if (settlementReadModelExpected && resourceChanges == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('NET PRODUCTION: UNAVAILABLE · A GAME-DAY SETTLEMENT IS REQUIRED',
            style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
      );
    }
    if (resourceChanges == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('NET PRODUCTION: SERVER SETTLEMENT REQUIRED',
            style: context.widgetFooterStyle.copyWith(color: context.mutedColor)),
      );
    }
    final values = resourceChanges!;
    final icons = <String, IconData>{
      'credits': Icons.account_balance_wallet_outlined,
      'energy': Icons.bolt_rounded,
      'food': Icons.eco_outlined,
      'materials': Icons.terrain_outlined,
      'components': Icons.precision_manufacturing_outlined,
      'compute': Icons.memory_rounded,
    };
    return Container(
      width: double.infinity,
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < values.length * 76;
          final items = values.entries.map((entry) {
            final value = entry.value;
            final color = value < 0
                ? context.dangerColor
                : value > 0
                    ? context.successColor
                    : context.mutedColor;
            final sign = value > 0 ? '+' : '';
            final amount = value.abs() >= 100
                ? formatWholeNumber(value.abs())
                : value.abs().toStringAsFixed(1);
            return SizedBox(
              width: compact
                  ? constraints.maxWidth / 3
                  : constraints.maxWidth / values.length,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icons[entry.key],
                      size: 16,
                      color: EarthResourceMeta.forCommodity(entry.key).color),
                  const SizedBox(height: 2),
                  Text('$sign${value < 0 ? '-' : ''}$amount',
                      style: context.topicTitleStyle.copyWith(color: color)),
                ],
              ),
            );
          }).toList();
          return compact
              ? Wrap(children: items)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: items,
                );
        },
      ),
    );
  }

  Widget _buildBuildingEconomicsSummary(
    BuildContext context, {
    required Map<String, dynamic> building,
    required double effectiveOutputAmount,
    required double effectiveOperatingCost,
    required bool isActive,
  }) {
    final outputType = building['resource_output_type']?.toString();
    final hasPhysicalOutput =
        outputType != null && outputType.isNotEmpty && outputType != 'credits';
    final status = !isActive
        ? 'Inactive'
        : hasPhysicalOutput
            ? 'Operational'
            : 'Operational · revenue requires customers';
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
            label: 'Production',
            value: 'UNAVAILABLE · SERVER SETTLEMENT REQUIRED',
            icon: hasPhysicalOutput
                ? Icons.factory_outlined
                : Icons.room_service_outlined,
            color: context.successColor,
          ),
          _buildingClarityMetric(
            context,
            label: 'Operating cost',
            value: 'UNAVAILABLE · SERVER SETTLEMENT REQUIRED',
            icon: Icons.payments_outlined,
            color: context.warningColor,
          ),
          _buildingClarityMetric(
            context,
            label: 'Status',
            value: status,
            icon: isActive
                ? Icons.check_circle_outline
                : Icons.pause_circle_outline,
            color: isActive ? context.successColor : context.mutedColor,
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

  Widget _buildCivicAndShareMarketSection(
    BuildContext context,
    List<Map<String, dynamic>> publicBuildings,
    List<Map<String, dynamic>> shares,
    List<Map<String, dynamic>> dividends,
  ) {
    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.primaryColor.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('PUBLIC PROJECTS & DIVIDENDS',
                  style: context.topicTitleStyle),
              const EarthBadge(
                  label: '70/30 UBI + PARTICIPATION',
                  variant: EarthBadgeVariant.secondary),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Civic and territorial facilities distribute operating surplus according to the active territorial dividend rules. Public megaprojects may offer fractional investment shares providing direct daily dividend yields.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),
          if (dividends.isNotEmpty) ...[
            Text('RECENT CIVIC CITIZEN DIVIDEND PAYOUTS',
                style: context.captionStyle),
            const SizedBox(height: 6),
            Column(
              children: dividends.map((d) {
                final day = asIntOr(d['day'], 0);
                final totalPool = asDoubleOr(d['total_surplus_crd'], 0);
                final ubiPerCitizen =
                    asDoubleOr(d['base_ubi_per_resident_crd'], 0);
                final partBonus =
                    asDoubleOr(d['participation_bonus_per_resident_crd'], 0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GAME DAY $day PAYOUT',
                          style: context.widgetTitleStyle),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          EarthBadge(
                              label:
                                  'TOTAL SURPLUS: +${formatWholeNumber(totalPool)} CRD',
                              variant: EarthBadgeVariant.primary),
                          EarthBadge(
                              label:
                                  'BASE UBI: +${formatWholeNumber(ubiPerCitizen)} CRD',
                              variant: EarthBadgeVariant.success),
                          if (partBonus > 0)
                            EarthBadge(
                                label:
                                    'BONUS: +${formatWholeNumber(partBonus)} CRD',
                                variant: EarthBadgeVariant.secondary),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
