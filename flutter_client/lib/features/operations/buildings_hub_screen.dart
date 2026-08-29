import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
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
  String _selectedCategory = 'all';
  String _catalogFilter = 'all';
  String _sortMode = 'default';
  String _plannerSelectedBlueprint = 'restaurant';
  Set<String>? _expandedBuildingGroups;

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
  }) async {
    final title = TextEditingController(text: 'Build $buildingName');
    final body = TextEditingController(
        text:
            'City proposal to procure $buildingName for municipal service. Construction cost: ${formatWholeNumber(creditCost)} Credits and $materialCost Materials; footprint: $footprint spaces.');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('PROPOSE CIVIC BUILDING',
            style:
                context.topicTitleStyle.copyWith(color: context.primaryColor)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'The city will vote on this proposal before construction begins.',
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
                    body.text.trim().length < 20) return;
                try {
                  await widget.action(() => const EarthApi().createProposal(
                        title.text.trim(),
                        body.text.trim(),
                        institutionId: cityId,
                        targetCategory: 'megaproject_procurement',
                        targetValue: {'buildingType': buildingType},
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

  Future<void> _showPublicOfferingDialog(BuildContext context,
      {required String buildingName,
      required String buildingType,
      required String cityId}) async {
    final title = TextEditingController(text: buildingName);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('OPEN PUBLIC INVESTMENT',
            style:
                context.topicTitleStyle.copyWith(color: context.primaryColor)),
        content: SizedBox(
          width: 440,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Open this blueprint as an active share-funded public project. Investors can buy shares after it is opened.',
                    style: context.bodyStyle),
                const SizedBox(height: 12),
                TextField(
                    controller: title,
                    maxLength: 140,
                    decoration:
                        const InputDecoration(labelText: 'Project name')),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          EarthButton(
              label: 'OPEN OFFERING',
              onPressed: () async {
                try {
                  await widget.action(() => const EarthApi()
                      .openPublicInvestmentOffering(
                          cityId: cityId,
                          buildingType: buildingType,
                          name: title.text.trim()));
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
    final cityId =
        widget.state.membership?['city_id']?.toString() ?? 'CITY-0084';
    final viewerId = widget.state.human['id']?.toString();

    final totalSlots = asIntOr(zoning['totalSlots'], 10);
    final civicReservedSlots = asIntOr(zoning['civicReservedSlots'], 3);
    final usedPrivateSlots = asIntOr(zoning['usedPrivateSlots'], 0);
    final usedCivicSlots = asIntOr(zoning['usedCivicSlots'], 0);
    final availablePrivateSlots = asIntOr(zoning['availablePrivateSlots'], 7);
    final population = asIntOr(zoning['population'], 12);
    final creditsAvailable = asDouble(
      widget.state.human['credits'] ??
          widget.state.finance['balance'] ??
          widget.state.personalFinance['balance'],
    );
    final materialsAvailable = asDouble(
      widget.state.resources['materials'] ?? widget.state.resources['material'],
    );

    final privateBuildings = buildings
        .where((b) => b['owner_id'] == viewerId && b['status'] != 'closed')
        .toList();
    final publicBuildings = buildings
        .where((b) =>
            b['ownership_class'] == 'public_investment' ||
            b['ownership_class'] == 'civic')
        .toList();
    final civicBuildings = buildings
        .where(
            (b) => b['ownership_class'] == 'civic' && b['status'] != 'closed')
        .toList();

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
            totalSlots: totalSlots,
            civicReservedSlots: civicReservedSlots,
            usedPrivateSlots: usedPrivateSlots,
            usedCivicSlots: usedCivicSlots,
            availablePrivateSlots: availablePrivateSlots,
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

          final investmentPanel = _buildInvestmentPanel(
            context,
            publicBuildings: publicBuildings
                .where((b) => b['ownership_class'] == 'public_investment')
                .toList(),
            shares: shares,
            dividends: dividends,
            totalMyShares: totalMyShares,
            lastUbi: lastUbi,
            catalog: catalog,
          );

          final selectedBuilt = _mainTab == 0
              ? privatePanel
              : _mainTab == 1
                  ? civicPanel
                  : investmentPanel;
          final selectedCatalog = _buildCatalogTab(context,
              catalog: catalog,
              ownershipFilter: _mainTab == 0
                  ? 'private'
                  : _mainTab == 1
                      ? 'civic'
                      : 'public_investment');
          final mainTabs = _buildMainOwnershipTabs(context,
              privateCount: privateBuildings.length,
              civicCount: civicBuildings.length,
              investmentCount: publicBuildings
                  .where((b) => b['ownership_class'] == 'public_investment')
                  .length);
          final ownershipDescription =
              _buildOwnershipDescription(context, _mainTab);

          // Wide and medium: one ownership context, two content columns.
          if (isWide || isMedium) {
            return Column(children: [
              mainTabs,
              ownershipDescription,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: selectedBuilt),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          _mainTab == 2
                              ? 'INVESTMENT CATALOG'
                              : '${_mainTab == 0 ? 'PRIVATE' : 'CIVIC'} CATALOG',
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
              mainTabs,
              ownershipDescription,
              _mainTab == 0
                  ? _buildPrivatePanel(context,
                      privateBuildings: privateBuildings,
                      catalog: catalog,
                      totalSlots: totalSlots,
                      civicReservedSlots: civicReservedSlots,
                      usedPrivateSlots: usedPrivateSlots,
                      usedCivicSlots: usedCivicSlots,
                      availablePrivateSlots: availablePrivateSlots,
                      population: population,
                      cityId: cityId,
                      creditsAvailable: creditsAvailable,
                      materialsAvailable: materialsAvailable,
                      viewerId: viewerId,
                      showSubTabs: true,
                      contentTab: _narrowSubTab,
                      showPanelTitle: false)
                  : _mainTab == 1
                      ? _buildCivicPanel(context,
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
                          showPanelTitle: false)
                      : _buildInvestmentPanel(context,
                          publicBuildings: publicBuildings
                              .where((b) =>
                                  b['ownership_class'] == 'public_investment')
                              .toList(),
                          shares: shares,
                          dividends: dividends,
                          totalMyShares: totalMyShares,
                          lastUbi: lastUbi,
                          catalog: catalog,
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
  Widget _buildMainOwnershipTabs(BuildContext context,
      {required int privateCount,
      required int civicCount,
      required int investmentCount}) {
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
                title: 'PRIVATE ($privateCount)',
                icon: Icons.storefront_outlined,
                isSelected: _mainTab == 0,
                onTap: () => setState(() => _mainTab = 0))),
        Expanded(
            child: _buildTabButton(context,
                title: 'CIVIC ($civicCount)',
                icon: Icons.account_balance_outlined,
                isSelected: _mainTab == 1,
                onTap: () => setState(() => _mainTab = 1))),
        Expanded(
            child: _buildTabButton(context,
                title: 'INVEST ($investmentCount)',
                icon: Icons.pie_chart_outline,
                isSelected: _mainTab == 2,
                onTap: () => setState(() => _mainTab = 2))),
      ]),
    );
  }

  Widget _buildOwnershipDescription(BuildContext context, int tab) {
    final text = tab == 0
        ? 'Private buildings belong to you. Their output goes to your account, while upkeep and operating costs are paid by you.'
        : tab == 1
            ? 'Civic buildings belong to the city. They expand city capacity and services, while their inputs and operating costs are paid from the city budget.'
            : 'Public-investment buildings are funded through shares. The city receives the investment capital and pays operating inputs; remaining credit surplus is distributed to investors as daily dividends.';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('CIVIC BUILDINGS', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, civicBuildings),
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
        if (!showSubTabs || contentTab == 0)
          civicBuildings.isEmpty
              ? const EarthEmptyState(
                  message: 'No city-owned civic buildings are active.',
                  icon: Icons.account_balance_outlined)
              : Column(
                  children: _buildGroupedBuildingCards(
                      context, civicBuildings, viewerId, catalog))
        else
          _buildCatalogTab(context, catalog: catalog, ownershipFilter: 'civic'),
        SizedBox(height: context.spacingTopic),
      ],
    );
  }

  Widget _buildInvestmentPanel(
    BuildContext context, {
    required List<Map<String, dynamic>> publicBuildings,
    required List<Map<String, dynamic>> shares,
    required List<Map<String, dynamic>> dividends,
    required int totalMyShares,
    required double lastUbi,
    required List<dynamic> catalog,
    bool showSubTabs = false,
    int contentTab = 0,
    bool showPanelTitle = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPanelTitle)
          Text('PUBLIC INVESTMENT', style: context.topicTitleStyle),
        SizedBox(height: context.spacingControl),
        _buildBuildingsResourceLine(context, publicBuildings),
        SizedBox(height: context.spacingControl),
        _buildInvestmentPortfolioSummary(
            context, publicBuildings, shares, totalMyShares),
        SizedBox(height: context.spacingControl),
        if (showSubTabs)
          _buildOwnershipSubTabs(context,
              labels: ['ACTIVE', 'CATALOG'],
              selected: contentTab,
              onChanged: (value) => setState(() => _narrowSubTab = value)),
        if (!showSubTabs || contentTab == 0)
          publicBuildings.isEmpty
              ? const EarthEmptyState(
                  message: 'No active public-investment offerings.',
                  icon: Icons.pie_chart_outline)
              : Column(
                  children: _buildGroupedBuildingCards(
                      context, publicBuildings, null, catalog,
                      investmentShares: shares))
        else
          _buildCatalogTab(context,
              catalog: catalog, ownershipFilter: 'public_investment'),
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
            if (_selectedCategory == 'manufacturing')
              return cat == 'manufacturing' || cat == 'industrial';
            if (_selectedCategory == 'compute')
              return cat == 'compute' || cat == 'high_tech';
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
      final avgProgress = items.fold<double>(0,
              (sum, b) => sum + asDoubleOr(b['construction_progress'], 100)) /
          items.length;
      final hasConstruction =
          items.any((b) => b['status']?.toString() == 'under_construction');
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
      final autoRepairStates = items
          .map((b) =>
              b['auto_repair_enabled'] == true ||
              b['auto_repair_enabled']?.toString() == 'true')
          .toSet();
      final commonAutoRepair =
          autoRepairStates.length == 1 && autoRepairStates.first;
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
              onTap: null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  children: [
                    InkWell(
                      onTap: toggleGroup,
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('$name × ${items.length}',
                                  style: context.widgetTitleStyle
                                      .copyWith(color: context.primaryColor))),
                          Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: context.primaryColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${totalSpace} space${totalSpace == 1 ? '' : 's'}  ·  ${tierLabel.replaceFirst('TIER', 'Tier')}  ·  ${hasConstruction ? 'Construction in progress' : 'Operational'} ${avgProgress.toStringAsFixed(0)}% complete',
                        style: context.widgetFooterStyle
                            .copyWith(color: context.mutedColor, fontSize: 12),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Text('AUTO-REPAIR',
                                  style: context.captionStyle.copyWith(
                                      fontSize: 9, color: context.mutedColor)),
                              const SizedBox(width: 4),
                              IconButton(
                                  tooltip: 'Auto-repair information',
                                  icon: Icon(Icons.info_outline,
                                      size: 15, color: context.mutedColor),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showInfoDialog(
                                      context,
                                      'Auto-repair',
                                      'When enabled, the next settlement uses one component for private buildings, or one material for civic buildings, to restore condition below 80% before production.')),
                            ]),
                            Transform.scale(
                                scale: 0.78,
                                child: Switch.adaptive(
                                    value: commonAutoRepair,
                                    activeThumbColor: context.primaryColor,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: widget.busy
                                        ? null
                                        : (enabled) async {
                                            await Future.wait(items.map(
                                                (item) => widget.action(() =>
                                                    const EarthApi()
                                                        .setBuildingAutoRepair(
                                                            buildingId:
                                                                item['id']
                                                                    .toString(),
                                                            enabled:
                                                                enabled))));
                                            _showBuildingFeedback(
                                                '$name group: auto-repair ${enabled ? 'enabled' : 'disabled'} for all ${items.length} buildings.');
                                          })),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                    showAutoRepair: false,
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
    final blueprints = catalog
        .whereType<Map>()
        .where((b) => b['defaultOwnershipClass'] == 'private')
        .toList();
    if (blueprints.isEmpty) {
      return const EarthEmptyState(
        message: 'No blueprints available for planning.',
        icon: Icons.architecture_outlined,
      );
    }

    final currentSpec = blueprints.firstWhere(
      (b) => b['type'] == _plannerSelectedBlueprint,
      orElse: () => blueprints.first,
    );

    final name = currentSpec['name']?.toString() ?? 'Blueprint';
    final type = currentSpec['type']?.toString() ?? '';
    final category = currentSpec['category']?.toString() ?? 'commercial';
    final footprint = asIntOr(currentSpec['slotFootprint'], 1);
    final creditCost = asIntOr(currentSpec['baseCreditCost'], 8500);
    final materialCost = asIntOr(currentSpec['baseMaterialCost'], 120);
    final dailyYield = asDoubleOr(
        currentSpec['dailyCreditRevenue'] ?? currentSpec['dailyOutputCredits'],
        600);
    final opCost = asDoubleOr(
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
              final bType = b['type']?.toString() ?? '';
              final bName = b['name']?.toString() ?? bType;
              final bSpace = asIntOr(b['slotFootprint'], 1);
              final bCost = asIntOr(b['baseCreditCost'], 8500);
              final bOutput = asDoubleOr(
                  b['dailyCreditRevenue'] ?? b['dailyOutputCredits'], 0);
              final bUpkeep = asDoubleOr(
                  b['dailyOperatingCredits'] ?? b['dailyStaffingCredits'], 0);
              final bResourceType = b['dailyOutputResourceType']?.toString();
              final bResourceAmount =
                  asDoubleOr(b['dailyOutputResourceAmount'], 0);
              final cardHasCapacity = availablePrivateSlots >= bSpace;
              final cardHasCredits =
                  creditsAvailable == null || creditsAvailable >= bCost;
              final cardHasMaterials = materialsAvailable == null ||
                  materialsAvailable >= asIntOr(b['baseMaterialCost'], 120);
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
                          bResourceAmount > 0 && bResourceType != null
                              ? 'Output: +${bResourceAmount.toStringAsFixed(1)} ${bResourceType.toUpperCase()}/day'
                              : 'Net: ${bOutput - bUpkeep >= 0 ? '+' : ''}${formatWholeNumber(bOutput - bUpkeep)} CRD/day',
                          style: context.bodyStyle.copyWith(
                            color: bResourceAmount > 0 && bResourceType != null
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

  // ==================== TAB 4: BUILDING CATALOG ====================
  Widget _catalogFilterChip(
    BuildContext context, {
    required String label,
    required String filter,
  }) {
    final isSelected = _catalogFilter == filter;
    return InkWell(
      onTap: () => setState(() => _catalogFilter = filter),
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

  Widget _buildCatalogTab(
    BuildContext context, {
    required List<dynamic> catalog,
    String? ownershipFilter,
  }) {
    final list = catalog
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((item) {
      if (ownershipFilter == null) return true;
      final ownership = item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString();
      return ownershipFilter == 'private'
          ? ownership != 'civic' && ownership != 'public_investment'
          : ownership == ownershipFilter;
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
    list.sort((a, b) {
      final categoryCompare = (a['category']?.toString() ?? 'commercial')
          .compareTo(b['category']?.toString() ?? 'commercial');
      if (categoryCompare != 0) return categoryCompare;
      return (a['name']?.toString() ?? 'Blueprint')
          .compareTo(b['name']?.toString() ?? 'Blueprint');
    });
    final privateCount = list.where((item) {
      final ownership = item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString();
      return ownership != 'civic' && ownership != 'public_investment';
    }).length;
    final civicCount = list
        .where((item) =>
            (item['defaultOwnershipClass']?.toString() ??
                item['ownershipClass']?.toString()) ==
            'civic')
        .length;
    final publicInvestmentCount = list
        .where((item) =>
            (item['defaultOwnershipClass']?.toString() ??
                item['ownershipClass']?.toString()) ==
            'public_investment')
        .length;
    final filteredList = list.where((item) {
      final ownership = item['defaultOwnershipClass']?.toString() ??
          item['ownershipClass']?.toString();
      if (_catalogFilter == 'private') {
        return ownership != 'civic' && ownership != 'public_investment';
      }
      if (_catalogFilter == 'civic') {
        return ownership == 'civic';
      }
      if (_catalogFilter == 'public_investment') {
        return ownership == 'public_investment';
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
                  label: 'ALL (${list.length})', filter: 'all'),
              _catalogFilterChip(context,
                  label: 'PRIVATE ($privateCount)', filter: 'private'),
              _catalogFilterChip(context,
                  label: 'CIVIC ($civicCount)', filter: 'civic'),
              _catalogFilterChip(context,
                  label: 'PUBLIC INVESTMENT ($publicInvestmentCount)',
                  filter: 'public_investment'),
            ],
          ),
        SizedBox(height: context.spacingControl),

        // Catalog List
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: filteredList.map<Widget>((item) {
            final name = item['name']?.toString() ?? 'Blueprint';
            final category =
                (item['category']?.toString() ?? 'commercial').toUpperCase();
            final footprint = asIntOr(item['slotFootprint'], 1);
            final creditCost = asIntOr(item['baseCreditCost'], 8500);
            final matCost = asIntOr(item['baseMaterialCost'], 120);
            final purpose = item['primaryEconomicPurpose']?.toString() ??
                'Economic Production';
            final desc = item['description']?.toString() ?? '';
            final civicBenefit = item['civicBenefit']?.toString();
            final rawTiers = item['tiers'] as List?;
            final tierCount = rawTiers != null ? rawTiers.length : 3;
            final outputType = item['resourceOutputType']?.toString();
            final outputAmount = asDoubleOr(item['resourceOutputAmount'], 0);
            final outputCredits = asDoubleOr(item['dailyCreditRevenue'], 0);
            final constructionDays = footprint;
            final inputs = <(IconData, String)>[];
            void addInput(String key, String label, IconData icon) {
              final amount = asDoubleOr(item[key], 0);
              if (amount > 0)
                inputs.add((icon, '${amount.toStringAsFixed(1)} $label'));
            }

            addInput('dailyEnergyUpkeep', 'ENERGY', Icons.bolt_rounded);
            addInput('dailyFoodUpkeep', 'FOOD', Icons.eco_outlined);
            addInput(
                'dailyMaterialsUpkeep', 'MATERIAL', Icons.terrain_outlined);
            addInput('dailyComponentsUpkeep', 'COMPONENTS',
                Icons.precision_manufacturing_outlined);
            addInput('dailyComputeUpkeep', 'COMPUTE', Icons.memory_rounded);
            final operatingCredits = asDoubleOr(
              item['dailyOperatingCredits'] ?? item['dailyStaffingCredits'],
              0,
            );

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
                          EarthBadge(
                              label:
                                  '$footprint SPACE${footprint > 1 ? 'S' : ''}',
                              variant: EarthBadgeVariant.primary),
                          EarthBadge(
                              label: 'UPGRADES $tierCount',
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
                      Wrap(
                        spacing: 3,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('COST', style: context.captionStyle),
                          const SizedBox(width: 5),
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 14, color: EarthResourceColors.credits),
                          Text(formatWholeNumber(creditCost),
                              style: context.widgetFooterStyle),
                          const SizedBox(width: 4),
                          Icon(EarthResourceMeta.forCommodity('material').icon,
                              size: 14, color: EarthResourceColors.materials),
                          Text('$matCost', style: context.widgetFooterStyle),
                        ],
                      ),
                      if (inputs.isNotEmpty ||
                          outputType != null ||
                          outputCredits > 0) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 3,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (inputs.isNotEmpty) ...[
                              Text('INPUT', style: context.captionStyle),
                              const SizedBox(width: 5),
                              ...inputs.expand((input) => <Widget>[
                                    Icon(input.$1,
                                        size: 14,
                                        color:
                                            _resourceColor(context, input.$2)),
                                    Text(input.$2.split(' ').first,
                                        style: context.widgetFooterStyle),
                                  ]),
                            ],
                          ],
                        ),
                        if (outputType != null || outputCredits > 0) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('OUTPUT', style: context.captionStyle),
                              const SizedBox(width: 5),
                              Icon(
                                outputType == null || outputType == 'credits'
                                    ? Icons.account_balance_wallet_outlined
                                    : EarthResourceMeta.forCommodity(outputType)
                                        .icon,
                                size: 14,
                                color: EarthResourceMeta.forCommodity(
                                        outputType ?? 'credits')
                                    .color,
                              ),
                              Text(
                                outputType == null || outputType == 'credits'
                                    ? formatWholeNumber(outputCredits)
                                    : '${outputAmount.toStringAsFixed(1)} ${outputType.toUpperCase()}',
                                style: context.widgetFooterStyle,
                              ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 4),
                      if (operatingCredits > 0)
                        Wrap(
                          spacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('OPERATING COST', style: context.captionStyle),
                            const SizedBox(width: 5),
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 14, color: EarthResourceColors.credits),
                            Text(
                                '-${formatWholeNumber(operatingCredits)} CRD / DAY',
                                style: context.widgetFooterStyle),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('CONSTRUCTION', style: context.captionStyle),
                          const SizedBox(width: 5),
                          Icon(Icons.schedule_outlined,
                              size: 14, color: context.primaryColor),
                          Text(
                              '$constructionDays ${constructionDays == 1 ? 'DAY' : 'DAYS'}',
                              style: context.widgetFooterStyle),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Builder(
                      builder: (context) {
                        final ownership =
                            item['defaultOwnershipClass']?.toString() ??
                                item['ownershipClass']?.toString();
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
                              : ownership == 'public_investment'
                                  ? 'Public investments are purchased through active share offerings'
                                  : canBuild
                                      ? 'Build this building'
                                      : 'Insufficient resources or capacity',
                          icon: const Icon(Icons.domain_add_outlined),
                          color: context.primaryColor,
                          onPressed: ownership == 'civic'
                              ? () => _showCivicProposalDialog(context,
                                  buildingName: name.trim(),
                                  buildingType: item['type']?.toString() ?? '',
                                  cityId: cityId,
                                  creditCost: creditCost,
                                  materialCost: matCost,
                                  footprint: footprint)
                              : ownership == 'public_investment'
                                  ? () => _showPublicOfferingDialog(context,
                                      buildingName: name.trim(),
                                      buildingType:
                                          item['type']?.toString() ?? '',
                                      cityId: cityId)
                                  : canBuild
                                      ? () => _confirmConstruction(
                                            context,
                                            buildingName: name,
                                            buildingType:
                                                item['type']?.toString() ?? '',
                                            cityId: cityId,
                                            creditCost: creditCost,
                                            materialCost: matCost,
                                            capacityCost: footprint,
                                            remainingCapacity:
                                                availablePrivateSlots -
                                                    footprint,
                                            netDailyCredits: outputCredits -
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

  // ==================== BUILDING CAPACITY ====================
  Widget _buildDistrictZoningVisualizer(
    BuildContext context, {
    required int totalSlots,
    required int civicReserved,
    required int usedPrivate,
    required int usedCivic,
    required int population,
  }) {
    final privateCapacity =
        (totalSlots - civicReserved).clamp(0, totalSlots).toInt();
    final privateUsed = usedPrivate.clamp(0, privateCapacity).toInt();
    final privateFree =
        (privateCapacity - privateUsed).clamp(0, privateCapacity).toInt();
    final privateProgress =
        privateCapacity == 0 ? 1.0 : privateUsed / privateCapacity;
    final civicUsed = usedCivic.clamp(0, civicReserved).toInt();
    final civicProgress = civicReserved == 0 ? 0.0 : civicUsed / civicReserved;

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
            children: [
              Icon(Icons.domain_outlined,
                  color: context.primaryColor, size: 20),
              const SizedBox(width: 8),
              Text('BUILDING CAPACITY', style: context.widgetTitleStyle),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Population supports $privateCapacity private building spaces. $privateFree are available for expansion.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('PRIVATE BUILDINGS', style: context.captionStyle),
              Text('$privateUsed / $privateCapacity used',
                  style: context.widgetFooterStyle),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: privateProgress,
              minHeight: 10,
              backgroundColor: context.primaryColor.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(
                privateFree > 0 ? context.primaryColor : context.dangerColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CIVIC SPACE', style: context.captionStyle),
              Text('$civicUsed / $civicReserved reserved',
                  style: context.widgetFooterStyle),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: civicProgress,
              minHeight: 8,
              backgroundColor: context.secondaryColor.withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(context.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== BUILDING CARD ====================
  Widget _buildBuildingCard(BuildContext context, Map<String, dynamic> b,
      String? viewerId, List<dynamic> catalog,
      {int? itemNumber,
      bool showOperatingPolicy = true,
      bool showAutoRepair = true,
      List<Map<String, dynamic>>? investmentShares}) {
    final id = b['id']?.toString() ?? '';
    final name = b['name']?.toString() ?? 'Facility';
    final tier = asIntOr(b['tier'], 1);
    final condition = asDoubleOr(b['condition'], 100);
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
    final conditionCostMultiplier = condition >= 80
        ? 1.0
        : condition >= 50
            ? 1.15
            : condition >= 20
                ? 1.40
                : 2.0;
    final effectiveOpCost =
        opCost * policyCostMultiplier * conditionCostMultiplier;
    final policyYieldMultiplier =
        (policy == 'frugal' || policy == 'eco_reserve')
            ? 0.75
            : policy == 'high_output'
                ? 1.30
                : 1.0;
    final conditionYieldMultiplier = condition >= 80
        ? 1.0
        : condition >= 50
            ? 0.75
            : condition >= 20
                ? 0.40
                : 0.10;
    final effectiveYield = policyYieldMultiplier * conditionYieldMultiplier;
    final effectiveOutputAmount = resOutAmt * effectiveYield;
    final effectiveOutput = isCreditOutput ? effectiveOutputAmount : 0.0;
    final autoRepairEnabled = b['auto_repair_enabled'] == true ||
        b['auto_repair_enabled']?.toString() == 'true';
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
          Text(
            '${itemNumber == null ? '' : '#$itemNumber  ·  '}${asIntOr(b['slot_footprint'], 1)} space${asIntOr(b['slot_footprint'], 1) == 1 ? '' : 's'}  ·  Tier ${asIntOr(b['tier'], 1)}  ·  ${b['status']?.toString() == 'under_construction' ? 'Construction in progress' : 'Operational'} ${asDoubleOr(b['construction_progress'], 100).toStringAsFixed(0)}% complete',
            style: context.widgetFooterStyle
                .copyWith(color: context.mutedColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _buildNetResourceLine(
            context,
            building: b,
            effectiveOutputAmount: effectiveOutputAmount,
            effectiveOperatingCost: effectiveOpCost,
          ),
          if (isPublicInvestment && investmentShares != null) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Available shares: $availableShares / $totalShares  ·  You hold: $sharesOwned',
                  style: context.widgetFooterStyle
                      .copyWith(color: context.mutedColor),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: EarthButton(
                    label: 'INVEST IN SHARES',
                    icon: Icons.add_chart_outlined,
                    variant: EarthButtonVariant.secondary,
                    onPressed: widget.busy
                        ? null
                        : () {
                            EarthAudioEngine.instance.playClick();
                            showPublicShareInvestDialog(
                                context, widget.action, b);
                          },
                  ),
                ),
              ],
            ),
          ],
          if (autoRepairEnabled && condition < 80)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Auto-repair is ready: the next settlement uses 1 ${isCivic ? 'material' : 'component'} to restore condition before production.',
                style: context.widgetFooterStyle
                    .copyWith(color: context.primaryColor),
              ),
            ),
          if (!isCreditOutput)
            Text(
              'Net CRD shows only the credit operating margin; physical output is shown separately.',
              style: context.widgetFooterStyle,
            ),
          const SizedBox(height: 6),

          // Secondary management actions stay collapsed until needed.
          if (isOwner)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showOperatingPolicy) ...[
                  Text(
                    'Policy changes the daily trade-off: Balanced is standard, Frugal lowers output and upkeep, and High output raises both. Condition also affects yield and cost.',
                    style: context.widgetFooterStyle,
                  ),
                  const SizedBox(height: 10),
                ],
                if (showOperatingPolicy)
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
                const SizedBox(height: 10),
                if (showAutoRepair)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('AUTO-REPAIR (<80%):',
                              style:
                                  context.captionStyle.copyWith(fontSize: 10)),
                          const SizedBox(width: 6),
                          Text(
                            'Cost: ${isCivic ? '1 Material' : '1 Component'} / cycle',
                            style: context.captionStyle.copyWith(
                                fontSize: 10, color: context.primaryColor),
                          ),
                        ],
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch.adaptive(
                          value: b['auto_repair_enabled'] == true ||
                              b['auto_repair_enabled']?.toString() == 'true',
                          activeThumbColor: context.primaryColor,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onChanged: widget.busy
                              ? null
                              : (val) async {
                                  EarthAudioEngine.instance.playClick();
                                  await widget.action(() =>
                                      const EarthApi().setBuildingAutoRepair(
                                        buildingId: id,
                                        enabled: val,
                                      ));
                                  _showBuildingFeedback(
                                    '$name: automatic repair ${val ? 'enabled' : 'disabled'}.',
                                  );
                                },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (condition < 100)
                        EarthButton(
                          label: 'REPAIR TO 100%',
                          icon: Icons.build_outlined,
                          variant: EarthButtonVariant.primary,
                          onPressed: widget.busy
                              ? null
                              : () async {
                                  EarthAudioEngine.instance.playClick();
                                  await widget.action(() => const EarthApi()
                                      .repairBuilding(buildingId: id));
                                  _showBuildingFeedback(
                                      '$name repaired to full condition.');
                                },
                        ),
                      EarthButton(
                        label: 'UPGRADE TREE (TIER ${tier + 1})',
                        icon: Icons.account_tree_outlined,
                        variant: EarthButtonVariant.primary,
                        onPressed: widget.busy
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
      final condition = asDoubleOr(building['condition'], 100);
      final conditionMultiplier = condition >= 80
          ? 1.0
          : condition >= 50
              ? 1.15
              : condition >= 20
                  ? 1.40
                  : 2.0;
      final gross =
          asDoubleOr(building['resource_output_amount'], 0) * yieldMultiplier;
      final cost = asDoubleOr(building['daily_operating_credits'], 0) *
          costMultiplier *
          conditionMultiplier;
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
      final outputType =
          building['resource_output_type']?.toString() ?? 'credits';
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
      final condition = asDoubleOr(building['condition'], 100);
      final conditionCostMultiplier = condition >= 80
          ? 1.0
          : condition >= 50
              ? 1.15
              : condition >= 20
                  ? 1.40
                  : 2.0;
      final upkeepMultiplier = costMultiplier * conditionCostMultiplier;
      final output =
          asDoubleOr(building['resource_output_amount'], 0) * outputMultiplier;
      final operatingCost =
          asDoubleOr(building['daily_operating_credits'], 0) * upkeepMultiplier;
      final autoRepair = building['auto_repair_enabled'] == true ||
          building['auto_repair_enabled']?.toString() == 'true';
      final repairResource = building['ownership_class']?.toString() == 'civic'
          ? 'materials'
          : 'components';
      double rounded(double value) => (value * 10).ceil() / 10;
      if (outputType == 'credits') {
        changes['credits'] = changes['credits']! + output - operatingCost;
      } else {
        changes[outputType] = (changes[outputType] ?? 0) + output;
        changes['credits'] = changes['credits']! - operatingCost;
      }
      changes['energy'] = changes['energy']! -
          rounded(asDoubleOr(building['upkeep_energy'], 0) * upkeepMultiplier);
      changes['food'] = changes['food']! -
          rounded(asDoubleOr(building['upkeep_food'], 0) * upkeepMultiplier);
      changes['materials'] = changes['materials']! -
          rounded(
              asDoubleOr(building['upkeep_materials'], 0) * upkeepMultiplier +
                  (autoRepair && repairResource == 'materials' ? 1 : 0));
      changes['components'] = changes['components']! -
          rounded(
              asDoubleOr(building['upkeep_components'], 0) * upkeepMultiplier +
                  (autoRepair && repairResource == 'components' ? 1 : 0));
      changes['compute'] = changes['compute']! -
          rounded(asDoubleOr(building['upkeep_compute'], 0) * upkeepMultiplier);
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
    final outputType =
        building['resource_output_type']?.toString() ?? 'credits';
    final isCreditOutput = outputType == 'credits';
    final autoRepair = building['auto_repair_enabled'] == true ||
        building['auto_repair_enabled']?.toString() == 'true';
    final repairResource = building['ownership_class']?.toString() == 'civic'
        ? 'materials'
        : 'components';
    final values = resourceChanges ??
        <String, double>{
          'credits': (isCreditOutput ? effectiveOutputAmount : 0) -
              effectiveOperatingCost,
          'energy': -asDoubleOr(building['upkeep_energy'], 0),
          'food': -asDoubleOr(building['upkeep_food'], 0),
          'materials': -asDoubleOr(building['upkeep_materials'], 0) -
              (autoRepair && repairResource == 'materials' ? 1 : 0),
          'components': -asDoubleOr(building['upkeep_components'], 0) -
              (autoRepair && repairResource == 'components' ? 1 : 0),
          'compute': -asDoubleOr(building['upkeep_compute'], 0),
        };
    if (resourceChanges == null && !isCreditOutput)
      values[outputType] = (values[outputType] ?? 0) + effectiveOutputAmount;
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
          if (publicBuildings.isNotEmpty) ...[
            Text('ACTIVE PUBLIC MEGAPROJECTS (CROWDFUNDED)',
                style: context.captionStyle),
            const SizedBox(height: 6),
            Column(
              children: publicBuildings.map((pb) {
                final bId = pb['id']?.toString() ?? '';
                final bName = pb['name']?.toString() ?? 'Megaproject';
                final isPublicProject =
                    pb['ownership_class']?.toString() == 'public_investment';
                final totalShares = asIntOr(pb['total_shares'], 100);
                final pricePerShare =
                    asDoubleOr(pb['price_per_share_crd'], 500);
                final myHolding = shares.firstWhere(
                  (s) => s['building_id'] == bId,
                  orElse: () => <String, dynamic>{'shares_owned': 0},
                );
                final myCount = asIntOr(myHolding['shares_owned'], 0);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusControl),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bName, style: context.widgetTitleStyle),
                      const SizedBox(height: 2),
                      if (isPublicProject) ...[
                        Text(
                          'Price: ${formatWholeNumber(pricePerShare)} CRD / Share · Your Holdings: $myCount / $totalShares Shares (${((myCount / totalShares) * 100).toStringAsFixed(1)}%)',
                          style: context.widgetFooterStyle,
                        ),
                        const SizedBox(height: 8),
                        EarthButton(
                          label: 'INVEST IN SHARES',
                          icon: Icons.add_chart_outlined,
                          variant: EarthButtonVariant.secondary,
                          onPressed: widget.busy
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  showPublicShareInvestDialog(
                                      context, widget.action, pb);
                                },
                        ),
                      ] else
                        Text('Civic utility · City-owned · No shares available',
                            style: context.widgetFooterStyle
                                .copyWith(color: context.mutedColor)),
                    ],
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: context.spacingControl),
          ] else ...[
            EarthSection(
              title: 'PUBLIC INVESTMENT OFFERINGS',
              showSurface: false,
              infoBulletPoints: const [
                'Public-investment blueprints become investable only after an active offering is opened.',
                'When an offering is active, its share price, available shares, and INVEST IN SHARES action appear here.',
              ],
              child: const EarthEmptyState(
                message:
                    'No public-investment offerings are active right now. Check the Public Investment catalog for available project blueprints.',
                icon: Icons.pie_chart_outline,
              ),
            ),
            SizedBox(height: context.spacingControl),
          ],
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
