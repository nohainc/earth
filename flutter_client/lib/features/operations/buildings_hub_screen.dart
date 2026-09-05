import 'dart:async';
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
import 'real_estate_dialogs.dart';

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
  final String _selectedCategory = 'all';
  String _catalogFilter = 'all';
  String _civicBuiltFilter = 'all'; // 'all' | 'civic' | 'invest'
  String _civicCatalogFilter = 'all'; // 'all' | 'civic' | 'invest'
  final String _sortMode = 'default';
  String _plannerSelectedBlueprint = 'restaurant';
  Set<String>? _expandedBuildingGroups;
  Timer? _constructionProgressTimer;
  int _localElapsedSeconds = 0;
  int? _serverClockTotalMinutes;
  final Set<String> _constructionCompletionRequests = <String>{};

  String _buildingImageAsset(String buildingType) {
    const assets = <String, String>{
      'restaurant': 'molecular-bistro',
      'retail-store': 'retail-tools-boutique',
      'commercial-mall': 'commercial-galleria',
      'fabrication-plant': 'cnc-fabrication-plant',
      'chemical-foundry': 'polymer-foundry',
      'solar-array-complex': 'solar-array',
      'geothermal-grid': 'geothermal-core',
      'vertical-farm': 'aeroponic-farm',
      'server-farm': 'neural-data-center',
      'medical-clinic': 'bionic-medical-center',
      'transit-hyperloop': 'hyperloop-terminal',
      'orbital-spaceport': 'orbital-spaceport',
      'transit-terminus': 'transit-hub',
      'urban-district-module': 'urban-district-module',
      'private-estate-plot': 'private-estate-plot',
    };
    return 'assets/buildings/${assets[buildingType] ?? 'urban-district-module'}.png';
  }

  Widget _buildingImage(BuildContext context, String buildingType) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.radiusControl),
      child: Image.asset(
        _buildingImageAsset(buildingType),
        width: 92,
        height: 92,
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

  @override
  void initState() {
    super.initState();
    _startConstructionTimer();
  }

  @override
  void didUpdateWidget(covariant BuildingsHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final serverTotalMinutes =
        asIntOr(widget.state.clock['totalGameMinutes'], 0);
    if (_serverClockTotalMinutes != null &&
        serverTotalMinutes != _serverClockTotalMinutes) {
      _localElapsedSeconds = 0;
    }
    _serverClockTotalMinutes = serverTotalMinutes;
    _startConstructionTimer();
  }

  @override
  void dispose() {
    _constructionProgressTimer?.cancel();
    super.dispose();
  }

  void _startConstructionTimer() {
    final hasUnderConstruction = widget.state.buildings.any((b) =>
        b is Map &&
        (b['status']?.toString() == 'under_construction' ||
            b['status']?.toString() == 'inactive'));
    if (hasUnderConstruction) {
      if (_constructionProgressTimer == null ||
          !_constructionProgressTimer!.isActive) {
        _constructionProgressTimer =
            Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _localElapsedSeconds++;
          });
          _completeFinishedBuildings();
        });
      }
    } else {
      _constructionProgressTimer?.cancel();
      _constructionProgressTimer = null;
    }
  }

  void _completeFinishedBuildings() {
    for (final raw in widget.state.buildings) {
      if (raw is! Map) continue;
      final building = Map<String, dynamic>.from(raw);
      final status = building['status']?.toString();
      if (status != 'under_construction' && status != 'inactive') continue;
      if (building['owner_id']?.toString() !=
          widget.state.human['id']?.toString()) {
        continue;
      }
      if (_calculateBuildingProgress(building) < 100.0) continue;
      final id = building['id']?.toString();
      if (id == null || !_constructionCompletionRequests.add(id)) continue;
      widget
          .action(() =>
              const EarthApi().completeBuildingConstruction(buildingId: id))
          .catchError((_) {
        _constructionCompletionRequests.remove(id);
      });
    }
  }

  bool _isBuildingActive(Map<String, dynamic> b) {
    return b['status']?.toString() == 'active';
  }

  String _getInactiveReason(Map<String, dynamic> b) {
    final status = b['status']?.toString();
    final progress = _calculateBuildingProgress(b);
    if (status == 'under_construction' ||
        (status == 'inactive' && progress < 100.0)) {
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

  double _calculateBuildingProgress(Map<String, dynamic> b) {
    final status = b['status']?.toString();
    if (status != 'under_construction' && status != 'inactive') {
      return 100.0;
    }

    final currentDay = asDoubleOr(widget.state.clock['day'], 1);
    final currentMinuteOfDay = asDoubleOr(widget.state.clock['minute'], 0);
    final baseAuthoritativeMinutes = asDoubleOr(
      widget.state.clock['totalGameMinutes'],
      ((currentDay - 1) * 1440.0) + currentMinuteOfDay,
    );
    // 1 real second = 1 game minute. Add local elapsed seconds so progress ticks every second
    final authoritativeMinutes =
        baseAuthoritativeMinutes + _localElapsedSeconds;

    final startMinute = b['construction_started_minute'] != null
        ? asDoubleOr(b['construction_started_minute'], 0)
        : ((asDoubleOr(
                    b['construction_started_game_day'] ?? b['created_game_day'],
                    currentDay) -
                1) *
            1440.0);
    final completeMinute = b['construction_complete_minute'] != null
        ? asDoubleOr(b['construction_complete_minute'], startMinute + 1440.0)
        : ((asDoubleOr(b['construction_complete_game_day'],
                    (startMinute / 1440.0) + 2.0) -
                1) *
            1440.0);

    final totalMinutes = math.max(1.0, completeMinute - startMinute);
    final elapsed = math.max(0.0, authoritativeMinutes - startMinute);

    final computed = (elapsed / totalMinutes) * 100.0;
    if (computed >= 100.0) {
      return 100.0;
    }
    return computed.clamp(0.0, 100.0);
  }

  double _creditResult(Map<String, dynamic> building) {
    final outputType = building['resource_output_type']?.toString();
    final creditOutput = outputType == 'credits' || outputType == null
        ? asDoubleOr(building['resource_output_amount'], 0)
        : 0;
    return creditOutput - asDoubleOr(building['daily_operating_credits'], 0);
  }

  void _showBuildingFeedback(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    required String cityId,
    required int creditCost,
    required int materialCost,
    required int footprint,
    bool publicInvestment = false,
  }) async {
    final title = TextEditingController(
        text: publicInvestment
            ? 'Open investment project: $buildingName'
            : 'Build $buildingName');
    final body = TextEditingController(
        text: publicInvestment
            ? 'City proposal to construct $buildingName as a public investment project. Construction cost: ${formatWholeNumber(creditCost)} Credits and $materialCost Materials; footprint: $footprint spaces. After construction is active, citizens can purchase shares.'
            : 'City proposal to procure $buildingName for municipal service. Construction cost: ${formatWholeNumber(creditCost)} Credits and $materialCost Materials; footprint: $footprint spaces.');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            publicInvestment
                ? 'PROPOSE INVESTMENT PROJECT'
                : 'PROPOSE CIVIC BUILDING',
            style:
                context.topicTitleStyle.copyWith(color: context.primaryColor)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                publicInvestment
                    ? 'The city will vote before construction begins. Shares become available only after the project is active.'
                    : 'The city will vote on this proposal before construction begins.',
                style: context.widgetFooterStyle),
            const SizedBox(height: 12),
            TextField(
                controller: title,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Proposal title')),
            const SizedBox(height: 8),
            TextField(
                controller: body,
                minLines: 4,
                maxLines: 7,
                maxLength: 4000,
                decoration:
                    const InputDecoration(labelText: 'Proposal details')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          EarthButton(
              label: 'SUBMIT PROPOSAL',
              onPressed: () async {
                if (title.text.trim().length < 8 ||
                    body.text.trim().length < 20) {
                  return;
                }
                try {
                  await widget.action(() => const EarthApi().createProposal(
                        title.text.trim(),
                        body.text.trim(),
                        institutionId: cityId,
                        targetCategory: 'megaproject_procurement',
                        targetValue: {
                          'buildingType': buildingType,
                          if (publicInvestment)
                            'ownershipClass': 'public_investment',
                        },
                      ));
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  _showBuildingFeedback(
                      error.toString().replaceFirst('Exception: ', ''));
                }
              }),
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
    final rawCityId = widget.state.membership?['city_id']?.toString();
    final isIndependent =
        rawCityId == null || rawCityId.isEmpty || rawCityId == 'Independent';
    final cityId = rawCityId ?? 'CITY-0084';
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
        'Private buildings belong to you and generate personal income. Civic buildings belong to the city and distribute surplus to all residents.',
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
              ownershipFilter: effectiveTab == 0 ? 'private' : 'civic');
          final civicBuildingsCount = civicBuildings.length;
          final mainTabs = isIndependent
              ? const SizedBox.shrink()
              : _buildMainOwnershipTabs(context);
          final ownershipDescription = isIndependent
              ? const SizedBox.shrink()
              : _buildOwnershipDescription(context, effectiveTab);

          final cockpit = EarthPageCockpit(
            status: isIndependent ? 'INDEPENDENT HOLDINGS' : 'REAL ESTATE & INFRASTRUCTURE',
            statusColor: isIndependent ? context.warningColor : context.primaryColor,
            infoTitle: 'REAL ESTATE & INFRASTRUCTURE ARCHITECTURE',
            infoDescription:
                '• Private Assets: Commercial, industrial, and residential buildings owned personally or assigned to your operating businesses.\n\n• Civic Assets: Municipal infrastructure and shared public investment projects that return dividends and UBI to residents.',
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

          // Wide and medium: one ownership context, two content columns.
          if (isWide || isMedium) {
            return Column(children: [
              cockpit,
              const SizedBox(height: 24),
              mainTabs,
              ownershipDescription,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: selectedBuilt),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${effectiveTab == 0 ? 'PRIVATE' : 'CIVIC'} CATALOG',
                          style: context.topicTitleStyle),
                      SizedBox(height: context.spacingControl),
                      selectedCatalog,
                    ])),
              ]),
            ]);
          }

          // Narrow: one ownership context with BUILT/ACTIVE and CATALOG subtabs.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cockpit,
              const SizedBox(height: 24),
              mainTabs,
              ownershipDescription,
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

  Widget _buildOwnershipDescription(BuildContext context, int tab) {
    final text = tab == 0
        ? 'Private buildings belong to you. Their output goes to your account, while upkeep and operating costs are paid by you.'
        : 'Civic buildings belong to the city or are co-funded by citizens through public shares. They expand municipal capacity and services, while surplus from public investment offerings is distributed to shareholding citizens as daily dividends.';
    return Padding(
      padding: EdgeInsets.only(bottom: context.spacingControl),
      child: Text(text, style: context.widgetFooterStyle),
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
        _buildBuildingsResourceLine(context, privateBuildings),
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
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['BUILT', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0) ...[
          _buildBuildingRecommendation(
            context,
            privateBuildings: privateBuildings,
            availablePrivateSlots: availablePrivateSlots,
          ),
          SizedBox(height: context.spacingControl),
          SizedBox(height: context.spacingTopic),
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
              catalog: catalog, ownershipFilter: 'private'),
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

    final filteredBuiltBuildings = allCivicBuildings.where((b) {
      if (_civicBuiltFilter == 'civic') {
        return b['ownership_class'] == 'civic';
      }
      if (_civicBuiltFilter == 'invest') {
        return b['ownership_class'] == 'public_investment';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('CIVIC BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, allCivicBuildings),
        if (publicBuildings.isNotEmpty) ...[
          SizedBox(height: context.spacingControl),
          _buildInvestmentPortfolioSummary(
              context, publicBuildings, shares, totalMyShares),
        ],
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
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['BUILT', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                context,
                label: 'ALL (${allCivicBuildings.length})',
                isSelected: _civicBuiltFilter == 'all',
                onTap: () => setState(() => _civicBuiltFilter = 'all'),
              ),
              _buildFilterChip(
                context,
                label: 'CIVIC (${civicBuildings.length})',
                isSelected: _civicBuiltFilter == 'civic',
                onTap: () => setState(() => _civicBuiltFilter = 'civic'),
              ),
              _buildFilterChip(
                context,
                label: 'INVEST (${publicBuildings.length})',
                isSelected: _civicBuiltFilter == 'invest',
                onTap: () => setState(() => _civicBuiltFilter = 'invest'),
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),
          filteredBuiltBuildings.isEmpty
              ? const EarthEmptyState(
                  message:
                      'No civic or public investment buildings match filter.',
                  icon: Icons.account_balance_outlined)
              : Column(
                  children: _buildGroupedBuildingCards(
                      context, filteredBuiltBuildings, viewerId, catalog,
                      investmentShares: shares)),
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
      return building['status']?.toString() == 'under_construction' ||
          asDoubleOr(building['condition'], 100) < 80;
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
          'Start with a building that matches your available Credits, Materials, and city capacity.';
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
          'Private capacity is full. Grow the city or improve infrastructure before expanding further.';
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
              return _creditResult(b) > 0;
            }
            if (_selectedCategory == 'attention') {
              return b['status']?.toString() == 'under_construction' ||
                  asDoubleOr(b['condition'], 100) < 80;
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
      filteredBuildings
          .sort((a, b) => _creditResult(b).compareTo(_creditResult(a)));
    } else if (_sortMode == 'upkeep') {
      filteredBuildings.sort((a, b) =>
          asDoubleOr(a['daily_operating_credits'], 0)
              .compareTo(asDoubleOr(b['daily_operating_credits'], 0)));
    } else if (_sortMode == 'attention') {
      filteredBuildings.sort((a, b) {
        final aScore = a['status']?.toString() == 'under_construction'
            ? 0
            : asDoubleOr(a['condition'], 100);
        final bScore = b['status']?.toString() == 'under_construction'
            ? 0
            : asDoubleOr(b['condition'], 100);
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
          Column(
              children: _buildGroupedBuildingCards(
                  context, filteredBuildings, viewerId, catalog)),

        SizedBox(height: context.spacingTopic),
        _buildRecentBuildingActivity(context),
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
      final totalSpace =
          items.fold<int>(0, (sum, b) => sum + asIntOr(b['slot_footprint'], 1));
      final tiers = items.map((b) => asIntOr(b['tier'], 1)).toList()..sort();
      final hasConstruction = items.any((b) =>
          b['status']?.toString() == 'under_construction' ||
          b['status']?.toString() == 'inactive');
      final hasIssue = items.any((b) {
        final status = b['status']?.toString();
        return status != 'active' &&
            status != 'under_construction' &&
            status != 'inactive';
      });
      final constructionItems = items.where((b) {
        final status = b['status']?.toString();
        return status == 'under_construction' || status == 'inactive';
      }).toList();
      final avgProgress = constructionItems.isEmpty
          ? 100.0
          : constructionItems.fold<double>(
                  0, (sum, b) => sum + _calculateBuildingProgress(b)) /
              constructionItems.length;
      final allConstructed = items.every((b) =>
          _calculateBuildingProgress(b) >= 100.0 &&
          b['status']?.toString() != 'under_construction' &&
          b['status']?.toString() != 'inactive');
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
      final name = first['name']?.toString() ?? 'Building';
      final groupKey = '${first['building_type'] ?? ''}|$name';
      final isExpanded = expandedGroups.contains(groupKey);
      final tierLabel = tiers.first == tiers.last
          ? 'TIER ${tiers.first}'
          : 'TIER ${tiers.first}-${tiers.last}';
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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$name × ${items.length}',
                                style: context.widgetTitleStyle.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (first['ownership_class'] ==
                                'public_investment') ...[
                              const SizedBox(width: 8),
                              const EarthBadge(
                                label: 'PUBLIC INVESTMENT',
                                variant: EarthBadgeVariant.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: toggleGroup,
                        child: Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: context.primaryColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasConstruction)
                          Text(
                            'Construction in progress ${avgProgress.toStringAsFixed(0)}% complete',
                            style: context.widgetFooterStyle.copyWith(
                                color: context.warningColor, fontSize: 12),
                          ),
                        if (hasConstruction) const SizedBox(height: 2),
                        Text(
                          '$totalSpace space${totalSpace == 1 ? '' : 's'}  ·  ${tierLabel.replaceFirst('TIER', 'Tier')}',
                          style: context.widgetFooterStyle.copyWith(
                              color: context.mutedColor, fontSize: 12),
                        ),
                        if (hasIssue)
                          Text(
                            'Building issue detected',
                            style: context.widgetFooterStyle.copyWith(
                                color: context.errorColor, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: toggleGroup,
                    child: _buildNetResourceLine(context,
                        building: const {},
                        effectiveOutputAmount: 0,
                        effectiveOperatingCost: 0,
                        resourceChanges: _resourceChangesForBuildings(items)),
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
                                    'Normal uses standard output and operating cost. Frugal reduces output and operating cost by 30%. High output increases output by 30% and operating cost by 40%.')),
                            Wrap(
                              spacing: 4,
                              children: [
                                for (final policyOption in const [
                                  {
                                    'id': 'balanced',
                                    'label': 'Normal',
                                    'help':
                                        'Standard output and operating cost.'
                                  },
                                  {
                                    'id': 'eco_reserve',
                                    'label': 'Frugal −30%',
                                    'help':
                                        '30% lower output and operating cost.'
                                  },
                                  {
                                    'id': 'high_output',
                                    'label': 'High output +30%',
                                    'help':
                                        '30% higher output and 40% higher operating cost.'
                                  },
                                ])
                                  Tooltip(
                                    message: policyOption['help']!,
                                    child: InkWell(
                                      onTap: widget.busy ||
                                              commonPolicy == policyOption['id']
                                          ? null
                                          : () async {
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
      if (bType == 'private-estate-plot') return false;
      final ownership = b['ownership_class'] ??
          b['defaultOwnershipClass'] ??
          b['ownershipClass'] ??
          'private';
      final tier = asIntOr(b['tier'], 1);
      final prevId = b['prev_catalog_id'];
      return ownership == 'private' &&
          tier == 1 &&
          (prevId == null || prevId.toString().isEmpty);
    }).toList();
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
    final creditCost = asIntOr(
        currentSpec['cost_credits'] ?? currentSpec['baseCreditCost'], 8500);
    final materialCost = asIntOr(
        currentSpec['cost_materials'] ?? currentSpec['baseMaterialCost'], 120);
    final dailyYield = asDoubleOr(
        currentSpec['output_credits'] ??
            currentSpec['dailyCreditRevenue'] ??
            currentSpec['dailyOutputCredits'],
        600);
    final opCost = asDoubleOr(
        currentSpec['operating_credits'] ??
            currentSpec['dailyOperatingCredits'] ??
            currentSpec['dailyStaffingCredits'],
        100);
    final netDailyProfit = dailyYield - opCost;
    final paybackDays = asIntOr(currentSpec['estimatedPaybackDays'],
        (creditCost / (netDailyProfit > 0 ? netDailyProfit : 1)).round());
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
    final hasEnoughCredits =
        creditsAvailable == null || creditsAvailable >= creditCost;
    final hasEnoughMaterials =
        materialsAvailable == null || materialsAvailable >= materialCost;
    final canConstruct = hasEnoughSlots &&
        hasEnoughPop &&
        hasEnoughCredits &&
        hasEnoughMaterials;

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
              final bCost =
                  asIntOr(b['cost_credits'] ?? b['baseCreditCost'], 8500);
              final bOutput = asDoubleOr(
                  b['output_credits'] ??
                      b['dailyCreditRevenue'] ??
                      b['dailyOutputCredits'],
                  0);
              final bUpkeep = asDoubleOr(
                  b['operating_credits'] ??
                      b['dailyOperatingCredits'] ??
                      b['dailyStaffingCredits'],
                  0);
              final bResourceType =
                  (b['resource_output_type'] ?? b['dailyOutputResourceType'])
                      ?.toString();
              final bResourceAmount = asDoubleOr(
                  b['output_energy'] ??
                      b['output_food'] ??
                      b['output_materials'] ??
                      b['output_components'] ??
                      b['output_compute'] ??
                      b['dailyOutputResourceAmount'],
                  0);
              final cardHasCapacity = availablePrivateSlots >= bSpace;
              final cardHasCredits =
                  creditsAvailable == null || creditsAvailable >= bCost;
              final cardHasMaterials = materialsAvailable == null ||
                  materialsAvailable >=
                      asIntOr(
                          b['cost_materials'] ?? b['baseMaterialCost'], 120);
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
                            '$bSpace capacity space${bSpace > 1 ? 's' : ''} · ${formatWholeNumber(bCost)} CRD',
                            style: context.widgetFooterStyle),
                        const SizedBox(height: 4),
                        Text(
                          bResourceAmount > 0 &&
                                  bResourceType != null &&
                                  bResourceType != 'credits'
                              ? 'Output: +${bResourceAmount.toStringAsFixed(1)} ${bResourceType.toUpperCase()}/day'
                              : 'Net: ${bOutput - bUpkeep >= 0 ? '+' : ''}${formatWholeNumber(bOutput - bUpkeep)} CRD/day',
                          style: context.bodyStyle.copyWith(
                            color: bResourceAmount > 0 &&
                                    bResourceType != null &&
                                    bResourceType != 'credits'
                                ? context.secondaryColor
                                : bOutput - bUpkeep >= 0
                                    ? context.successColor
                                    : context.dangerColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Operating cost: -${formatWholeNumber(bUpkeep)} CRD/day',
                          style: context.widgetFooterStyle.copyWith(
                            color: bUpkeep > 0
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
                      value: '~ $paybackDays DAYS',
                      icon: Icons.timer_outlined,
                      accentColor: paybackDays <= 15
                          ? context.successColor
                          : context.primaryColor,
                    ),
                    EarthMetricTile(
                      label: 'PROJECTED NET DAILY',
                      value: '+${formatWholeNumber(netDailyProfit)} CRD',
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
                                ? 'Credits: ${formatWholeNumber(creditCost)} required'
                                : 'Credits: ${formatWholeNumber(creditCost)} required · ${formatWholeNumber(creditsAvailable)} available',
                            hasEnoughCredits,
                          ),
                          _buildRequirementItem(
                            context,
                            materialsAvailable == null
                                ? 'Materials: $materialCost required'
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
                              await _confirmConstruction(
                                context,
                                buildingName: name,
                                buildingType: _plannerSelectedBlueprint,
                                cityId: cityId,
                                creditCost: creditCost,
                                materialCost: materialCost,
                                capacityCost: footprint,
                                remainingCapacity:
                                    availablePrivateSlots - footprint,
                                netDailyCredits: netDailyProfit,
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
    required double netDailyCredits,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Build $buildingName', style: context.topicTitleStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Review this investment before construction begins.',
                style: context.bodyStyle),
            const SizedBox(height: 12),
            Text('Cost', style: context.captionStyle),
            Text(
                '${formatWholeNumber(creditCost)} Credits + $materialCost Materials',
                style: context.bodyStyle),
            const SizedBox(height: 8),
            Text('Capacity', style: context.captionStyle),
            Text(
                '$capacityCost space${capacityCost > 1 ? 's' : ''} · $remainingCapacity private spaces remaining',
                style: context.bodyStyle),
            const SizedBox(height: 8),
            Text('Expected result', style: context.captionStyle),
            Text(
              '${netDailyCredits >= 0 ? '+' : ''}${formatWholeNumber(netDailyCredits)} Credits/day',
              style: context.bodyStyle.copyWith(
                color: netDailyCredits >= 0
                    ? context.successColor
                    : context.dangerColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
      await widget.action(() => const EarthApi().purchaseBuilding(
            buildingType: buildingType,
            name: buildingName,
            cityId: cityId,
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
    return Container(
      margin: EdgeInsets.only(bottom: context.spacingControl),
      decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.subtleBorderColor)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
              child: _buildTabButton(context,
                  title: labels[i],
                  icon:
                      i == 0 ? Icons.domain_outlined : Icons.menu_book_outlined,
                  isSelected: selected == i,
                  onTap: () => onChanged(i))),
      ]),
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

  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
    String? ownershipFilter,
  }) {
    final allCatalogMaps = catalog
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((item) =>
            (item['building_type'] ?? item['type']) != 'private-estate-plot')
        .toList();

    // Only display root blueprints (tier 1 or prev_catalog_id is null) in the catalog blueprints view
    final rootBlueprints = allCatalogMaps.where((item) {
      final prevId = item['prev_catalog_id'];
      final tier = asIntOr(item['tier'], 1);
      return (prevId == null || prevId.toString().isEmpty) && tier == 1;
    }).toList();

    final zoning = widget.state.districtZoning;
    final availablePrivateSlots = asIntOr(zoning['availablePrivateSlots'], 0);
    final cityId =
        widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final creditsAvailable = asDouble(widget.state.human['credits'] ??
        widget.state.finance['balance'] ??
        widget.state.personalFinance['balance']);
    final materialsAvailable = asDouble(widget.state.resources['materials'] ??
        widget.state.resources['material']);

    rootBlueprints.sort((a, b) {
      final categoryCompare = (a['category']?.toString() ?? 'commercial')
          .compareTo(b['category']?.toString() ?? 'commercial');
      if (categoryCompare != 0) return categoryCompare;
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

    final filteredList = rootBlueprints.where((item) {
      final ownership = item['ownership_class']?.toString() ??
          item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString() ??
          'private';

      if (ownershipFilter == 'private') {
        return ownership == 'private';
      }
      if (ownershipFilter == 'civic') {
        if (_civicCatalogFilter == 'civic') {
          return ownership == 'civic';
        }
        return ownership == 'civic';
      }

      if (_catalogFilter == 'private') {
        return ownership == 'private';
      }
      if (_catalogFilter == 'civic') {
        return ownership == 'civic';
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ownershipFilter == null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _catalogFilterChip(context,
                  label: 'ALL (${rootBlueprints.length})', filter: 'all'),
              _catalogFilterChip(context,
                  label: 'PRIVATE ($privateCount)', filter: 'private'),
              _catalogFilterChip(context,
                  label: 'CIVIC ($civicCount)', filter: 'civic'),
            ],
          )
        else if (ownershipFilter == 'civic')
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                context,
                label: 'ALL ($civicCount)',
                isSelected: _civicCatalogFilter == 'all',
                onTap: () => setState(() => _civicCatalogFilter = 'all'),
              ),
              _buildFilterChip(
                context,
                label: 'CIVIC ($civicCount)',
                isSelected: _civicCatalogFilter == 'civic',
                onTap: () => setState(() => _civicCatalogFilter = 'civic'),
              ),
            ],
          ),
        SizedBox(height: context.spacingControl),

        // Catalog List
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: filteredList.map<Widget>((item) {
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
            final footprint =
                asIntOr(item['slot_footprint'] ?? item['slotFootprint'], 1);

            // Group count: total upgrades/tiers available in the catalog for this building type
            final groupBuildings = allCatalogMaps
                .where((b) => (b['building_type'] ?? b['type']) == bType)
                .toList();
            final tierCount = math.max(1, groupBuildings.length);

            // Costs (24-resource vector)
            final creditCost =
                asIntOr(item['cost_credits'] ?? item['baseCreditCost'], 8500);
            final matCost = asIntOr(
                item['cost_materials'] ?? item['baseMaterialCost'], 120);
            final compCost = asIntOr(item['cost_components'], 0);
            final computeCost = asIntOr(item['cost_compute'], 0);

            final purpose = item['primaryEconomicPurpose']?.toString() ??
                (ownership == 'civic'
                    ? 'Municipal Public Utility'
                    : 'Economic Production');
            final desc = item['description']?.toString() ?? '';
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

            // Legacy fallback if output_* was 0
            if (outputs.isEmpty) {
              final legacyOutType = item['resourceOutputType']?.toString() ??
                  item['resource_output_type']?.toString();
              final legacyOutAmount = asDoubleOr(
                  item['resourceOutputAmount'] ??
                      item['resource_output_amount'],
                  0);
              final legacyCreditRevenue = asDoubleOr(
                  item['dailyCreditRevenue'] ?? item['daily_credit_revenue'],
                  0);
              if (legacyCreditRevenue > 0) {
                outputs.add((
                  Icons.account_balance_wallet_outlined,
                  EarthResourceColors.credits,
                  '${formatWholeNumber(legacyCreditRevenue)} CRD / DAY'
                ));
              }
              if (legacyOutType != null &&
                  legacyOutType != 'credits' &&
                  legacyOutAmount > 0) {
                outputs.add((
                  EarthResourceMeta.forCommodity(legacyOutType).icon,
                  EarthResourceMeta.forCommodity(legacyOutType).color,
                  '${legacyOutAmount.toStringAsFixed(1)} ${legacyOutType.toUpperCase()} / DAY',
                ));
              }
            }

            // Upkeep Inputs (24-resource vector)
            final inputs = <(IconData, Color, String)>[];
            void addInput(
                String key, String label, IconData icon, Color color) {
              final amount = asDoubleOr(item['upkeep_$key'], 0);
              if (amount > 0) {
                inputs
                    .add((icon, color, '${amount.toStringAsFixed(1)} $label'));
              }
            }

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

            // Operating Expenses (24-resource vector)
            final operatingCredits = asDoubleOr(
              item['operating_credits'] ??
                  item['dailyOperatingCredits'] ??
                  item['dailyStaffingCredits'] ??
                  item['daily_operating_credits'],
              0,
            );
            final operatingEnergy = asDoubleOr(item['operating_energy'], 0);
            final operatingFood = asDoubleOr(item['operating_food'], 0);
            final operatingMaterials =
                asDoubleOr(item['operating_materials'], 0);
            final operatingComponents =
                asDoubleOr(item['operating_components'], 0);
            final operatingCompute = asDoubleOr(item['operating_compute'], 0);

            final hasActiveProposal =
                ownership == 'civic' &&
                    _hasActiveProposalForBuilding(bType);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildingImage(context, bType),
                      ),
                      const SizedBox(height: 8),
                      Text(name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: context.widgetTitleStyle
                              .copyWith(color: context.primaryColor)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (ownership == 'civic')
                            const EarthBadge(
                                label: 'CIVIC MUNICIPAL',
                                variant: EarthBadgeVariant.secondary),
                          if (hasActiveProposal)
                            const EarthBadge(
                                label: 'PROPOSAL ACTIVE',
                                variant: EarthBadgeVariant.primary),
                          EarthBadge(
                              label:
                                  '$footprint SPACE${footprint > 1 ? 'S' : ''}',
                              variant: EarthBadgeVariant.primary),
                          EarthBadge(
                              label: '$tierCount TIERS',
                              variant: EarthBadgeVariant.neutral),
                          EarthBadge(
                              label: category,
                              variant: EarthBadgeVariant.neutral),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(desc,
                          style: context.bodyStyle
                              .copyWith(color: context.mutedColor)),
                      const SizedBox(height: 6),
                      Text('Economic Purpose: $purpose',
                          style: context.widgetFooterStyle),
                      if (civicBenefit != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.secondaryColor.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('🏛️ Civic Benefit: $civicBenefit',
                              style: TextStyle(
                                  color: context.secondaryColor, fontSize: 11)),
                        ),
                      ],
                      const SizedBox(height: 8),

                      // Cost line
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('COST', style: context.captionStyle),
                          const SizedBox(width: 2),
                          const Icon(Icons.account_balance_wallet_outlined,
                              size: 14, color: EarthResourceColors.credits),
                          Text(formatWholeNumber(creditCost),
                              style: context.widgetFooterStyle),
                          if (matCost > 0) ...[
                            const SizedBox(width: 4),
                            Icon(
                                EarthResourceMeta.forCommodity('materials')
                                    .icon,
                                size: 14,
                                color: EarthResourceColors.materials),
                            Text('$matCost', style: context.widgetFooterStyle),
                          ],
                          if (compCost > 0) ...[
                            const SizedBox(width: 4),
                            Icon(
                                EarthResourceMeta.forCommodity('components')
                                    .icon,
                                size: 14,
                                color: EarthResourceColors.components),
                            Text('$compCost', style: context.widgetFooterStyle),
                          ],
                          if (computeCost > 0) ...[
                            const SizedBox(width: 4),
                            Icon(EarthResourceMeta.forCommodity('compute').icon,
                                size: 14, color: EarthResourceColors.compute),
                            Text('$computeCost',
                                style: context.widgetFooterStyle),
                          ],
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
                            Text('DAILY UPKEEP', style: context.captionStyle),
                            const SizedBox(width: 2),
                            ...inputs.expand((input) => <Widget>[
                                  Icon(input.$1, size: 14, color: input.$2),
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
                            Text('OPERATING', style: context.captionStyle),
                            const SizedBox(width: 2),
                            if (operatingCredits > 0) ...[
                              const Icon(Icons.account_balance_wallet_outlined,
                                  size: 14, color: EarthResourceColors.credits),
                              Text(
                                  '-${formatWholeNumber(operatingCredits)} CRD / DAY',
                                  style: context.widgetFooterStyle),
                            ],
                            if (operatingEnergy > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                  EarthResourceMeta.forCommodity('energy').icon,
                                  size: 14,
                                  color: EarthResourceColors.energy),
                              Text(
                                  '-${operatingEnergy.toStringAsFixed(1)} / DAY',
                                  style: context.widgetFooterStyle),
                            ],
                            if (operatingComponents > 0) ...[
                              const SizedBox(width: 4),
                              Icon(
                                  EarthResourceMeta.forCommodity('components')
                                      .icon,
                                  size: 14,
                                  color: EarthResourceColors.components),
                              Text(
                                  '-${operatingComponents.toStringAsFixed(1)} / DAY',
                                  style: context.widgetFooterStyle),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Builder(
                      builder: (context) {
                        final outCreditsVal = asDoubleOr(item['output_credits'],
                            asDoubleOr(item['dailyCreditRevenue'], 0));
                        final canBuild = ownership == 'private' &&
                            !widget.busy &&
                            availablePrivateSlots >= footprint &&
                            (creditsAvailable == null ||
                                creditsAvailable >= creditCost) &&
                            (materialsAvailable == null ||
                                materialsAvailable >= matCost);
                        return IconButton(
                          tooltip: ownership == 'civic'
                              ? 'Create a civic procurement proposal'
                              : canBuild
                                  ? 'Build this building'
                                  : 'Insufficient resources or capacity',
                          icon: const Icon(Icons.domain_add_outlined),
                          color: context.primaryColor,
                          onPressed: ownership == 'civic'
                              ? () => _showCivicProposalDialog(context,
                                  buildingName: name.trim(),
                                  buildingType: bType,
                                  cityId: cityId,
                                  creditCost: creditCost,
                                  materialCost: matCost,
                                  footprint: footprint)
                              : canBuild
                                      ? () => _confirmConstruction(
                                            context,
                                            buildingName: name,
                                            buildingType: bType,
                                            cityId: cityId,
                                            creditCost: creditCost,
                                            materialCost: matCost,
                                            capacityCost: footprint,
                                            remainingCapacity:
                                                availablePrivateSlots -
                                                    footprint,
                                            netDailyCredits: outCreditsVal -
                                                operatingCredits,
                                          )
                                      : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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

    final resOutType = b['resource_output_type']?.toString();
    final resOutAmt = asDoubleOr(b['resource_output_amount'], 0);
    final opCost = asDoubleOr(b['daily_operating_credits'], 0);
    final isCreditOutput = resOutType == 'credits' || resOutType == null;
    final policyCostMultiplier = (policy == 'frugal' || policy == 'eco_reserve')
        ? 0.70
        : policy == 'high_output'
            ? 1.40
            : 1.0;
    final effectiveOpCost = opCost * policyCostMultiplier;
    final policyYieldMultiplier =
        (policy == 'frugal' || policy == 'eco_reserve')
            ? 0.75
            : policy == 'high_output'
                ? 1.30
                : 1.0;
    final effectiveOutputAmount = resOutAmt * policyYieldMultiplier;
    final effectiveOutput = isCreditOutput ? effectiveOutputAmount : 0.0;
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
    final progressVal = _calculateBuildingProgress(b);
    final isUnderConstruction = !bActive &&
        (b['status']?.toString() == 'under_construction' ||
            progressVal < 100.0);
    final hasIssue = !bActive && !isUnderConstruction;
    final inactiveReason = _getInactiveReason(b);

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
          Align(
            alignment: Alignment.centerLeft,
            child: _buildingImage(context, bType),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isUnderConstruction)
                      Text(
                        'Construction in progress ${progressVal.toStringAsFixed(0)}% complete',
                        style: context.widgetFooterStyle.copyWith(
                            color: context.warningColor, fontSize: 12),
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
              if (!bActive) ...[
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
          _buildNetResourceLine(
            context,
            building: b,
            effectiveOutputAmount: effectiveOutputAmount,
            effectiveOperatingCost: effectiveOpCost,
          ),
          if (isPublicInvestment) ...[
            const SizedBox(height: 8),
            Text('Available shares: $availableShares / $totalShares',
                style: context.widgetFooterStyle),
            Text('You hold: $sharesOwned',
                style: context.widgetFooterStyle),
            if (bActive && availableShares > 0) ...[
              const SizedBox(height: 8),
              EarthButton(
                label: 'INVEST IN SHARES',
                icon: Icons.show_chart_outlined,
                variant: EarthButtonVariant.secondary,
                onPressed: widget.busy
                    ? null
                    : () => _showBuildingFeedback(
                        'Share investment is available from the public investment market.'),
              ),
            ],
          ],
          if (!isCreditOutput)
            Text(
              'Net CRD shows only the credit operating margin; physical output is shown separately.',
              style: context.widgetFooterStyle,
            ),
          const SizedBox(height: 6),

          // Management actions
          if (isOwner)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showOperatingPolicy && bType != 'private-estate-plot') ...[
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
                            {'id': 'balanced', 'label': 'Balanced · normal'},
                            {
                              'id': 'high_output',
                              'label': 'High output · +30%'
                            },
                            {
                              'id': 'eco_reserve',
                              'label': 'Frugal · lower upkeep'
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
                      EarthButton(
                        label: isUnderConstruction
                            ? 'UNDER CONSTRUCTION'
                            : 'UPGRADE TREE (TIER ${tier + 1})',
                        icon: isUnderConstruction
                            ? Icons.hourglass_top_outlined
                            : Icons.account_tree_outlined,
                        variant: isUnderConstruction
                            ? EarthButtonVariant.secondary
                            : EarthButtonVariant.primary,
                        onPressed: widget.busy || isUnderConstruction
                            ? null
                            : () async {
                                EarthAudioEngine.instance.playClick();
                                await showBuildingDetailUpgradeDialog(
                                  context,
                                  widget.action,
                                  b,
                                  catalog,
                                );
                                _showBuildingFeedback(
                                    '$name upgrade completed.');
                              },
                      ),
                      if (bType != 'private-estate-plot' &&
                          bType != 'urban-district-module')
                        EarthButton(
                          label: 'DEMOLISH / RECYCLE',
                          icon: Icons.delete_outline,
                          variant: EarthButtonVariant.danger,
                          onPressed: widget.busy
                              ? null
                              : () async {
                                  EarthAudioEngine.instance.playClick();
                                  await showDemolishConfirmDialog(
                                      context, widget.action, b);
                                  _showBuildingFeedback(
                                      '$name was removed and its capacity was released.');
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

  Widget _buildBuildingsResourceLine(
      BuildContext context, List<Map<String, dynamic>> buildings) {
    return _buildNetResourceLine(context,
        building: const {},
        effectiveOutputAmount: 0,
        effectiveOperatingCost: 0,
        resourceChanges: _resourceChangesForBuildings(buildings));
  }

  Widget _buildInvestmentPortfolioSummary(
      BuildContext context,
      List<Map<String, dynamic>> buildings,
      List<Map<String, dynamic>> shares,
      int totalMyShares) {
    var estimate = 0.0;
    for (final building in buildings) {
      final status = building['status']?.toString();
      if (status == 'under_construction' ||
          status == 'inactive' ||
          status == 'closed' ||
          status == 'foreclosed') {
        continue;
      }
      final holding = shares
          .where((share) =>
              share['building_id']?.toString() == building['id']?.toString())
          .firstOrNull;
      if (holding == null) continue;
      final policy = building['operating_policy']?.toString() ?? 'balanced';
      final yieldMultiplier = policy == 'high_output'
          ? 1.30
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? 0.75
              : 1.0;
      final costMultiplier = policy == 'high_output'
          ? 1.40
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? 0.70
              : 1.0;
      final gross =
          asDoubleOr(building['resource_output_amount'], 0) * yieldMultiplier;
      final cost =
          asDoubleOr(building['daily_operating_credits'], 0) * costMultiplier;
      final sharesOwned = asDoubleOr(holding['shares_owned'], 0);
      final issued = asDoubleOr(holding['total_shares_issued'], 1000);
      estimate += math.max(0, gross - cost) * sharesOwned / math.max(1, issued);
    }
    final invested = shares.fold<double>(
        0, (sum, share) => sum + asDoubleOr(share['invested_credits'], 0));
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
        '+${formatWholeNumber(estimate)} C',
        Icons.trending_up_outlined,
        estimate > 0 ? context.successColor : context.mutedColor
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

  Map<String, double> _resourceChangesForBuildings(
      List<Map<String, dynamic>> buildings) {
    final changes = <String, double>{
      'credits': 0,
      'energy': 0,
      'food': 0,
      'materials': 0,
      'components': 0,
      'compute': 0,
    };
    for (final building in buildings) {
      // Inactive and under-construction buildings produce no income and incur no daily operating/upkeep costs
      if (!_isBuildingActive(building)) {
        continue;
      }

      final policy = building['operating_policy']?.toString() ?? 'balanced';
      final outputMultiplier = (policy == 'high_output')
          ? 1.30
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? 0.75
              : 1.0;
      final costMultiplier = (policy == 'high_output')
          ? 1.40
          : (policy == 'frugal' || policy == 'eco_reserve')
              ? 0.70
              : 1.0;
      double rounded(double value) => (value * 10).ceil() / 10;

      for (final key in [
        'credits',
        'energy',
        'food',
        'materials',
        'components',
        'compute'
      ]) {
        // Output calculation (support 24-field vector with legacy fallback)
        double outVal = asDoubleOr(building['output_$key'], 0);
        if (outVal == 0 &&
            building['resource_output_type']?.toString() == key) {
          outVal = asDoubleOr(building['resource_output_amount'], 0);
        } else if (outVal == 0 &&
            key == 'credits' &&
            (building['resource_output_type']?.toString() == 'credits' ||
                building['resource_output_type'] == null)) {
          outVal = asDoubleOr(building['resource_output_amount'], 0);
        }

        // Upkeep & Operating calculation (support 24-field vector with legacy fallback)
        double upkeepVal = asDoubleOr(building['upkeep_$key'], 0);
        double opVal = asDoubleOr(building['operating_$key'], 0);
        if (key == 'credits' && opVal == 0) {
          opVal = asDoubleOr(building['daily_operating_credits'], 0);
        }

        final netDelta = (outVal * outputMultiplier) -
            ((upkeepVal + opVal) * costMultiplier);
        if (key == 'credits') {
          changes['credits'] = changes['credits']! + netDelta;
        } else {
          changes[key] =
              changes[key]! + (key == 'credits' ? netDelta : rounded(netDelta));
        }
      }
    }
    return changes;
  }

  Widget _buildNetResourceLine(
    BuildContext context, {
    required Map<String, dynamic> building,
    required double effectiveOutputAmount,
    required double effectiveOperatingCost,
    Map<String, double>? resourceChanges,
  }) {
    final isBuildingActive = _isBuildingActive(building);

    final outputType =
        building['resource_output_type']?.toString() ?? 'credits';
    final isCreditOutput = outputType == 'credits';
    final values = resourceChanges ??
        (!isBuildingActive
            ? <String, double>{
                'credits': 0,
                'energy': 0,
                'food': 0,
                'materials': 0,
                'components': 0,
                'compute': 0,
              }
            : <String, double>{
                'credits': (asDoubleOr(building['output_credits'],
                        isCreditOutput ? effectiveOutputAmount : 0)) -
                    (asDoubleOr(building['operating_credits'],
                            effectiveOperatingCost) +
                        asDoubleOr(building['upkeep_credits'], 0)),
                'energy': asDoubleOr(building['output_energy'],
                        outputType == 'energy' ? effectiveOutputAmount : 0) -
                    (asDoubleOr(building['upkeep_energy'], 0) +
                        asDoubleOr(building['operating_energy'], 0)),
                'food': asDoubleOr(building['output_food'],
                        outputType == 'food' ? effectiveOutputAmount : 0) -
                    (asDoubleOr(building['upkeep_food'], 0) +
                        asDoubleOr(building['operating_food'], 0)),
                'materials': asDoubleOr(
                        building['output_materials'],
                        (outputType == 'material' || outputType == 'materials')
                            ? effectiveOutputAmount
                            : 0) -
                    (asDoubleOr(building['upkeep_materials'], 0) +
                        asDoubleOr(building['operating_materials'], 0)),
                'components': asDoubleOr(
                        building['output_components'],
                        outputType == 'components'
                            ? effectiveOutputAmount
                            : 0) -
                    (asDoubleOr(building['upkeep_components'], 0) +
                        asDoubleOr(building['operating_components'], 0)),
                'compute': asDoubleOr(building['output_compute'],
                        outputType == 'compute' ? effectiveOutputAmount : 0) -
                    (asDoubleOr(building['upkeep_compute'], 0) +
                        asDoubleOr(building['operating_compute'], 0)),
              });
    if (resourceChanges == null &&
        isBuildingActive &&
        !isCreditOutput &&
        asDoubleOr(building['output_$outputType'], 0) == 0) {
      values[outputType] = (values[outputType] ?? 0) + effectiveOutputAmount;
    }
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
            'Civic and municipal facilities distribute 100% of their net operating surplus to registered city residents (70% as equal Base UBI, and 30% weighted by citizen participation). Public megaprojects offer fractional investment shares providing direct daily dividend yields.',
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
