import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import 'business_dialogs.dart';

class BusinessManagerOverviewPanel extends StatelessWidget {
  final EarthState state;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final Map<String, dynamic>? activeBusiness;
  final ValueChanged<String>? onNavigate;

  const BusinessManagerOverviewPanel({
    super.key,
    required this.state,
    this.businessFinancials = const {},
    this.businessProfile = const {},
    this.activeBusiness,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final business = activeBusiness ?? state.business;
    final businessId = business['id']?.toString();
    final businessName = (business['name'] ?? businessProfile['name'] ?? 'Business Operations').toString();
    final fin = businessFinancials['business'] is Map
        ? Map<String, dynamic>.from(businessFinancials['business'] as Map)
        : businessFinancials;
    final status = (business['status'] ?? 'active').toString().toUpperCase();
    final revenue = asDouble(fin['revenue']);
    final costs = asDouble(fin['operating_costs'] ?? fin['costs']);
    final profit = asDouble(fin['profit']) ??
        (revenue != null && costs != null ? revenue - costs : null);
    final cash = asDouble(fin['cash'] ?? fin['balance'] ?? business['cash']);
    final payroll = asDouble(fin['payroll']);
    final workforce = state.json['workforce'] is List
        ? (state.json['workforce'] as List)
            .whereType<Map>()
            .where((item) =>
                item['status']?.toString() == 'active' &&
                (businessId == null ||
                    item['business_id'] == null ||
                    item['business_id']?.toString() == businessId))
            .length
        : 0;
    final buildingCount = state.buildings
        .whereType<Map>()
        .where((item) => _belongsToBusiness(item, businessId))
        .length;
    final businessBuildings = state.buildings.whereType<Map>().where((item) {
      return _belongsToBusiness(item, businessId);
    }).toList();
    final buildingNeeds = <String, double>{
      'energy': 0,
      'food': 0,
      'material': 0,
      'components': 0,
      'compute': 0,
    };
    for (final building in businessBuildings) {
      for (final entry in {
        'energy': 'upkeep_energy',
        'food': 'upkeep_food',
        'material': 'upkeep_materials',
        'components': 'upkeep_components',
        'compute': 'upkeep_compute',
      }.entries) {
        buildingNeeds[entry.key] =
            buildingNeeds[entry.key]! + asDoubleOr(building[entry.value], 0);
      }
    }
    final resourceRisks = buildingNeeds.entries.where((entry) {
      final stock = asDoubleOr(state.resources[entry.key] ??
          (entry.key == 'material' ? state.resources['materials'] : null), 0);
      return entry.value > 0 && stock < entry.value;
    }).map((entry) => entry.key).toList();
    final businessContracts = state.contracts.whereType<Map>().where((contract) {
      final contractBusiness = contract['business_id'] ?? contract['businessId'];
      return businessId == null ||
          contractBusiness == null ||
          contractBusiness.toString() == businessId;
    }).toList();
    final contractRisks = businessContracts.where((contract) {
      final status = (contract['status']?.toString() ?? '').toLowerCase();
      return status.contains('risk') ||
          status.contains('default') ||
          status.contains('overdue') ||
          status.contains('pending');
    }).length;
    final policy = (business['policy'] ??
            businessProfile['policy'] ??
            'No operating direction chosen')
        .toString();
    final bottlenecks = <String>[];
    if (workforce == 0) bottlenecks.add('staffing');
    if (buildingCount == 0) bottlenecks.add('building capacity');
    if (profit != null && profit < 0) bottlenecks.add('cost control');
    if (resourceRisks.isNotEmpty) bottlenecks.add('resource coverage');
    final nextAction = profit != null && profit < 0
        ? 'Review policy and operating costs before expanding.'
        : resourceRisks.isNotEmpty
            ? 'Secure ${resourceRisks.join(' · ')} before the next operating cycle.'
            : buildingCount == 0
                ? 'Connect a productive building before hiring or expanding.'
                : 'Review capacity and consider expansion, contracts, or technology adoption.';
    final nextSection = profit != null && profit < 0
        ? 'finance'
        : resourceRisks.isNotEmpty
            ? 'market'
            : buildingCount == 0
                ? 'buildings'
                : null;

    return EarthSection(
      title: 'MANAGER\'S BRIEF / $businessName',
      showSurface: false,
      infoBulletPoints: const [
        'The decision view for running this business: strategy, people, capacity, cash, and risks.',
        'Buildings are the productive assets; operating policy, upkeep, and revenue are managed here.',
        'Values are shown only when current business data is available.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status == 'ACTIVE'
                ? 'The operation is active. Choose the next investment or protect the current margin.'
                : 'The operation needs attention before it can safely expand.',
            style: context.widgetTitleStyle.copyWith(
              color: status == 'ACTIVE' ? context.successColor : context.warningColor,
            ),
          ),
          SizedBox(height: context.spacingControl),
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'PROFIT / CYCLE',
                value: profit == null
                    ? 'UNAVAILABLE'
                    : '${formatWholeNumber(profit)} C',
                icon: Icons.trending_up_outlined,
                accentColor: profit == null || profit >= 0
                    ? context.successColor
                    : context.warningColor,
              ),
              EarthMetricTile(
                label: 'CASH RUNWAY',
                value: cash == null || payroll == null || payroll <= 0
                    ? 'UNAVAILABLE'
                    : '${(cash / payroll).floor()} cycles',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'ACTIVE STAFF',
                value: '$workforce',
                icon: Icons.groups_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'BUILDING CAPACITY',
                value: '$buildingCount',
                icon: Icons.business_outlined,
                accentColor: context.warningColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingControl),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.primaryColor.withValues(alpha: .28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OPERATING SIGNAL', style: context.captionStyle),
                const SizedBox(height: 5),
                Text(nextAction,
                    style: context.widgetTitleStyle.copyWith(
                        color: bottlenecks.isEmpty
                            ? context.inkColor
                            : context.warningColor)),
                const SizedBox(height: 4),
                Text(
                    bottlenecks.isEmpty
                        ? 'No immediate operating blocker is visible.'
                        : 'Watch: ${bottlenecks.join(' · ')}',
                    style: context.widgetFooterStyle),
                if (nextSection != null && onNavigate != null) ...[
                  const SizedBox(height: 8),
                  EarthButton(
                    label: nextSection == 'market'
                        ? 'OPEN MARKET'
                        : nextSection == 'buildings'
                            ? 'OPEN BUILDINGS'
                            : 'OPEN FINANCE',
                    icon: Icons.arrow_forward_rounded,
                    variant: EarthButtonVariant.secondary,
                    onPressed: () => onNavigate!(nextSection),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: context.spacingControl),
          _productiveAssetsCard(context, businessBuildings, buildingNeeds),
          SizedBox(height: context.spacingControl),
          _resourceRunwayCard(context, buildingNeeds),
          SizedBox(height: context.spacingControl),
          _contractExposureCard(context, businessContracts, contractRisks),
          Text(
            'STRATEGY: $policy',
            style: context.widgetTitleStyle.copyWith(color: context.inkColor),
          ),
          const SizedBox(height: 4),
          Text(
            'Policy trade-off: ${_policyExplanation(policy)}',
            style: context.widgetFooterStyle.copyWith(
              color: bottlenecks.isEmpty ? context.mutedColor : context.warningColor,
            ),
          ),
          const SizedBox(height: 10),
          _policyComparisonCard(context, policy),
          const SizedBox(height: 6),
          Text(
            'Next decisions: hire · train · secure supplies · adjust policy · adopt technology · expand · conserve cash.',
            style: context.widgetFooterStyle,
          ),
        ],
      ),
    );
  }

  String _policyExplanation(String policy) {
    final normalized = policy.toLowerCase();
    if (normalized.contains('margin')) {
      return 'protects profit by favoring cost control over maximum output.';
    }
    if (normalized.contains('capacity')) {
      return 'pushes output and capacity, with greater operating pressure.';
    }
    return 'favors stable operation and predictable upkeep.';
  }

  bool _belongsToBusiness(Map item, String? businessId) {
    if (businessId == null) return true;
    final allBuildings = state.buildings.whereType<Map>();
    final hasAssignments = allBuildings.any((building) =>
        building['business_id'] != null || building['businessId'] != null);
    if (!hasAssignments) return true;
    return (item['business_id'] ?? item['businessId'])?.toString() == businessId;
  }

  Widget _policyComparisonCard(BuildContext context, String activePolicy) {
    const options = [
      ('reliability', 'Stable output', 'Predictable upkeep and lower operating volatility.'),
      ('margin', 'Protect margin', 'Lower operating pressure with less emphasis on maximum output.'),
      ('capacity', 'Push capacity', 'Higher output potential with greater resource demand.'),
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('POLICY COMPARISON', style: context.captionStyle),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final selected = activePolicy == option.$1;
            return Container(
              width: 190,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: selected
                    ? context.primaryColor.withValues(alpha: .12)
                    : context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusControl),
                border: Border.all(
                    color: selected
                        ? context.primaryColor
                        : context.subtleBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.$2,
                      style: context.widgetTitleStyle.copyWith(
                          color: selected
                              ? context.primaryColor
                              : context.inkColor)),
                  const SizedBox(height: 3),
                  Text(option.$3, style: context.widgetFooterStyle),
                  if (selected) ...[
                    const SizedBox(height: 4),
                    Text('CURRENT', style: context.captionStyle.copyWith(
                        color: context.primaryColor)),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _productiveAssetsCard(BuildContext context, List<dynamic> buildings,
      Map<String, double> needs) {
    final rankedBuildings = List<dynamic>.from(buildings)
      ..sort((a, b) => _buildingNet(b).compareTo(_buildingNet(a)));
    final totalCapacity = buildings.fold<double>(
        0, (sum, building) => sum + asDoubleOr(building['capacity'], 0));
    final usedCapacity = buildings.fold<double>(
        0, (sum, building) => sum + asDoubleOr(building['capacity_used'], 0));
    final capacityText = totalCapacity > 0
        ? '${formatWholeNumber(usedCapacity)} / ${formatWholeNumber(totalCapacity)} used'
        : '${buildings.length} connected building${buildings.length == 1 ? '' : 's'}';
    final activeNeeds = needs.entries
        .where((entry) => entry.value > 0)
        .map((entry) => '${formatWholeNumber(entry.value)} ${entry.key.toUpperCase()}')
        .take(3)
        .join(' · ');
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.domain_outlined, size: 16, color: context.primaryColor),
          const SizedBox(width: 7),
          Text('PRODUCTIVE ASSETS', style: context.widgetTitleStyle),
        ]),
        const SizedBox(height: 5),
        Text(capacityText, style: context.widgetValueStyle),
        const SizedBox(height: 3),
        Text(
            buildings.isEmpty
                ? 'No building is connected to this business.'
                : '${rankedBuildings.take(3).map((b) => b['name']?.toString() ?? 'Building').join(' · ')}${buildings.length > 3 ? ' · +${buildings.length - 3} more' : ''}',
            style: context.widgetFooterStyle),
        if (activeNeeds.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text('INPUTS / CYCLE: $activeNeeds', style: context.widgetFooterStyle),
        ],
        if (buildings.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...rankedBuildings.take(4).map((building) {
            final outputType = building['resource_output_type']?.toString();
            final output = asDoubleOr(building['resource_output_amount'], 0);
            final operatingCost = asDoubleOr(
                building['daily_operating_credits'] ??
                    building['operating_cost'],
                0);
            final outputLabel = outputType == null || outputType == 'credits'
                ? '${formatWholeNumber(output)} C output'
                : '${formatWholeNumber(output)} ${outputType.toUpperCase()}';
            final name = building['name']?.toString() ?? 'Building';
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: context.widgetFooterStyle),
                  ),
                  Text(outputLabel, style: context.widgetFooterStyle),
                  const SizedBox(width: 8),
                  Text('-${formatWholeNumber(operatingCost)} C',
                      style: context.widgetFooterStyle),
                ],
              ),
            );
          }),
          if (buildings.length > 4)
            Text('+${buildings.length - 4} more connected buildings',
                style: context.widgetFooterStyle),
        ],
      ]),
    );
  }

  double _buildingNet(dynamic raw) {
    if (raw is! Map) return 0;
    final outputType = raw['resource_output_type']?.toString();
    final output = outputType == null || outputType == 'credits'
        ? asDoubleOr(raw['resource_output_amount'], 0)
        : 0;
    return output -
        asDoubleOr(raw['daily_operating_credits'] ?? raw['operating_cost'], 0);
  }

  Widget _resourceRunwayCard(
      BuildContext context, Map<String, double> buildingNeeds) {
    final relevant = buildingNeeds.entries.where((entry) => entry.value > 0).toList();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: context.secondaryColor),
          const SizedBox(width: 7),
          Text('RESOURCE RUNWAY', style: context.widgetTitleStyle),
        ]),
        const SizedBox(height: 5),
        Text(
            relevant.isEmpty
                ? 'No building input requirements are recorded.'
                : 'Estimated coverage before connected buildings need replenishment.',
            style: context.widgetFooterStyle),
        if (relevant.isNotEmpty) ...[
          const SizedBox(height: 9),
          ...relevant.map((entry) {
            final stock = asDoubleOr(state.resources[entry.key] ??
                (entry.key == 'material' ? state.resources['materials'] : null), 0);
            final cycles = (stock / entry.value).floor();
            final atRisk = cycles <= 1;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Expanded(
                    child: Text(entry.key.toUpperCase(),
                        style: context.captionStyle)),
                Text('$cycles cycle${cycles == 1 ? '' : 's'} covered',
                    style: context.widgetFooterStyle.copyWith(
                        color: atRisk
                            ? context.warningColor
                            : context.mutedColor)),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _contractExposureCard(
      BuildContext context, List<dynamic> contracts, int risks) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: risks > 0
            ? context.warningColor.withValues(alpha: .4)
            : context.subtleBorderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.handshake_outlined,
              size: 16,
              color: risks > 0 ? context.warningColor : context.primaryColor),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CONTRACT EXPOSURE', style: context.widgetTitleStyle),
                const SizedBox(height: 4),
                Text(
                    contracts.isEmpty
                        ? 'No linked contracts are visible for this business.'
                        : '${contracts.length} linked contract${contracts.length == 1 ? '' : 's'} · ${risks == 0 ? 'No immediate delivery risk' : '$risks need attention'}',
                    style: context.widgetFooterStyle.copyWith(
                        color: risks > 0
                            ? context.warningColor
                            : context.mutedColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BusinessPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> businessOwnership;
  final Map<String, dynamic> businessFinancials;
  final Map<String, dynamic> businessProfile;
  final Map<String, dynamic>? activeBusiness;
  final ValueChanged<String>? onSelectBusiness;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const BusinessPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.businessOwnership,
    required this.businessFinancials,
    required this.businessProfile,
    this.activeBusiness,
    this.onSelectBusiness,
    this.onNavigate,
    required this.action,
  });

  Future<void> _rename(BuildContext context, String businessId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dialogContext.radiusPanel),
          side: BorderSide(color: dialogContext.subtleBorderColor),
        ),
        title: Text('Rename business', style: dialogContext.pageTitleStyle),
        content: TextField(
          controller: controller,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Business name'),
        ),
        actions: [
          EarthButton(
            label: 'CANCEL',
            variant: EarthButtonVariant.neutral,
            onPressed: () => Navigator.pop(dialogContext),
          ),
          EarthButton(
            label: 'SAVE',
            variant: EarthButtonVariant.primary,
            onPressed: () async {
              final name = controller.text.trim();
              if (name.length < 2) return;
              Navigator.pop(dialogContext);
              await action(() => const EarthApi().renameBusiness(businessId, name));
            },
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final business = activeBusiness ?? state.business;
    final businessId = business['id']?.toString() ?? '';
    final businessName =
        (business['name'] as String?)?.toUpperCase() ?? 'BUSINESS OPERATIONS';
    final status = (business['status']?.toString() ?? 'active').toLowerCase();
    final condition = asIntOr(business['condition'], 96);
    final activePolicy =
        (business['policy']?.toString() ?? 'reliability').toLowerCase();
    final portfolio = state.businesses;

    final finMap = businessFinancials['business'] is Map<String, dynamic>
        ? (businessFinancials['business'] as Map<String, dynamic>)
        : business;

    final revenue = asDouble(finMap['revenue']);
    final operatingCosts = asDouble(finMap['operating_costs'] ?? finMap['costs']);
    final profit = asDouble(finMap['profit']) ??
        (revenue != null && operatingCosts != null
            ? revenue - operatingCosts
            : null);
    final taxedRevenue = asDouble(finMap['taxed_revenue']);
    final lastGameDay = finMap['last_game_day'] ?? state.clock['day'];
    final workforceData = (state.json['workforce'] is List
            ? state.json['workforce'] as List
            : const [])
        .whereType<Map>()
        .toList();
    final hasWorkforceAssignments = workforceData.any((employee) =>
        employee['business_id'] != null || employee['businessId'] != null);
    final workforce = (state.json['workforce'] is List
            ? state.json['workforce'] as List
            : const [])
        .whereType<Map>()
        .where((employee) =>
            employee['status']?.toString() == 'active' &&
            (!hasWorkforceAssignments ||
                (employee['business_id'] ?? employee['businessId'])
                        ?.toString() ==
                    businessId))
        .toList();
    final payroll = workforce.fold<double>(
        0, (sum, employee) => sum + asDoubleOr(employee['wage'], 0));

    final profitMargin = revenue != null && revenue > 0 && profit != null
        ? (profit / revenue) * 100
        : null;
    final costRatio = revenue != null && revenue > 0 && operatingCosts != null
        ? (operatingCosts / revenue).clamp(0.0, 1.0)
        : null;
    final profitRatio = costRatio == null ? null : (1.0 - costRatio).clamp(0.0, 1.0);

    final isDistressed = status == 'distressed';
    final isInsolvent = status == 'insolvent';
    final isDissolved = status == 'dissolved';

    EarthBadgeVariant statusBadgeVariant = EarthBadgeVariant.primary;
    if (isDistressed) statusBadgeVariant = EarthBadgeVariant.warning;
    if (isInsolvent || isDissolved) statusBadgeVariant = EarthBadgeVariant.danger;

    final holders = (businessOwnership['holders'] is List
        ? businessOwnership['holders'] as List
        : []);
    final totalShares = asIntOr(
        businessOwnership['totalIssuedShares'] ??
            business['total_issued_shares'],
        1000);
    final controllingId = businessOwnership['controllingHumanId']?.toString() ??
        business['controlling_human_id']?.toString() ??
        'UNAVAILABLE';

    final shareholderThreshold =
        asDoubleOr(business['shareholder_vote_threshold'], 0.5);
    final boardThreshold =
        asDoubleOr(business['board_approval_threshold'], 0.5);
    final dilutionNoticeDays = asIntOr(business['dilution_notice_days'], 3);

    return EarthSection(
      key: panelKey,
      title: 'BUSINESS',
      showSurface: false,
      infoBulletPoints: const [
        'Decide what this business should improve: growth, stability, unit economics, or market share.',
        'Buildings, staff, policy, technology adoption, and share distributions all coordinate here.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. EXECUTIVE BUSINESS HEADER CARD
        Container(
          width: double.infinity,
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
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: context.primaryColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(context.radiusControl),
                      border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.domain_rounded, size: 22, color: context.primaryColor),
                  ),
                  SizedBox(width: context.spacingInline),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                businessName,
                                style: context.pageTitleStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.edit_outlined, size: 15, color: context.mutedColor),
                              tooltip: 'Rename business',
                              onPressed: busy || businessId.isEmpty
                                  ? null
                                  : () => _rename(context, businessId, businessName),
                            ),
                            const SizedBox(width: 8),
                            EarthBadge(
                              label: status.toUpperCase(),
                              variant: statusBadgeVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ENTITY ID: ${businessId.isEmpty ? 'UNAVAILABLE' : businessId}  ·  SECTOR: ${(business['sector']?.toString() ?? 'UNSPECIFIED').toUpperCase()}  ·  ASSESSED DAY ${lastGameDay ?? 'UNAVAILABLE'}',
                          style: context.widgetFooterStyle,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'BUSINESS OPERATIONS · LEGAL / OPERATOR VIEW',
                          style: context.captionStyle.copyWith(
                              color: context.primaryColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.spacingTitleOffset),

              // Fleet condition & Policy Selector Row
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  // Fleet Health Meter
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OPERATING HEALTH:',
                        style: context.captionStyle,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (condition / 100.0).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: context.subtleBorderColor,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              condition > 75
                                  ? context.successColor
                                  : condition > 40
                                      ? context.warningColor
                                      : context.errorColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$condition%',
                        style: context.widgetValueStyle.copyWith(
                          color: condition > 75
                              ? context.successColor
                              : condition > 40
                                  ? context.warningColor
                                  : context.errorColor,
                        ),
                      ),
                    ],
                  ),

                  // Operating Policy Selector
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('OPERATING POLICY:', style: context.captionStyle),
                      const SizedBox(width: 8),
                      for (final policy in ['reliability', 'margin', 'capacity']) ...[
                        InkWell(
                          onTap: busy || isDissolved || businessId.isEmpty
                              ? null
                              : () {
                                  EarthAudioEngine.instance.playClick();
                                  action(() => const EarthApi().setPolicy(policy, businessId: businessId));
                                },
                          borderRadius: BorderRadius.circular(context.radiusControl),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: activePolicy == policy
                                  ? context.primaryColor.withValues(alpha: .2)
                                  : context.surfaceColor,
                              borderRadius: BorderRadius.circular(context.radiusControl),
                              border: Border.all(
                                color: activePolicy == policy
                                    ? context.primaryColor
                                    : context.subtleBorderColor,
                              ),
                            ),
                            child: Text(
                              policy.toUpperCase(),
                              style: context.captionStyle.copyWith(
                                color: activePolicy == policy ? context.primaryColor : context.mutedColor,
                                fontWeight: activePolicy == policy ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'CURRENT POLICY EFFECT: ${_policyPreview(activePolicy)}',
                style: context.widgetFooterStyle,
              ),
            ],
          ),
        ),

        // Distress / Insolvency Warning Banner
        if (isDistressed || isInsolvent) ...[
          SizedBox(height: context.spacingControl),
          Container(
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.errorColor.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.errorColor.withValues(alpha: .4)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: context.errorColor, size: 22),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isInsolvent
                            ? 'CRITICAL: BUSINESS INSOLVENCY'
                            : 'WARNING: FINANCIAL DISTRESS',
                        style: context.widgetTitleStyle.copyWith(color: context.errorColor),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Operating expenditures exceed reserves. You are eligible for sovereign restructuring or authorized liquidation.',
                        style: context.widgetFooterStyle,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: context.spacingInline),
                EarthButton(
                  label: 'RESTRUCTURE',
                  variant: EarthButtonVariant.warning,
                  onPressed: busy ? null : () => showReceivershipRestructuringDialog(context, action, businessId),
                ),
              ],
            ),
          ),
        ],

        SizedBox(height: context.spacingTopic),
        BusinessManagerOverviewPanel(
          state: state,
          businessFinancials: businessFinancials,
          businessProfile: businessProfile,
          activeBusiness: activeBusiness,
          onNavigate: onNavigate,
        ),

        if (portfolio.length > 1) ...[
          SizedBox(height: context.spacingTopic),
          _businessPortfolio(context, portfolio),
        ],

        SizedBox(height: context.spacingTopic),

        // WORKFORCE / OPERATING CAPACITY
        EarthSection(
          title: 'WORKFORCE / OPERATING CAPACITY',
          showSurface: false,
          infoBulletPoints: const [
            'Staff are part of the business, not abstract analytics. Their skills and morale affect the organization\'s ability to deliver work.',
            'Payroll is a recurring operating cost.',
            'Hire for a role, train valuable staff, or dismiss underperformers as the business changes.',
          ],
          trailing: EarthButton(
            label: 'HIRE',
            icon: Icons.person_add_alt_1,
            variant: EarthButtonVariant.primary,
            onPressed: busy ? null : () => showHireEmployeeDialog(context, action, businessId),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${workforce.length} active staff · ${formatWholeNumber(payroll)} C / cycle payroll',
                style: context.widgetFooterStyle,
              ),
              SizedBox(height: context.spacingControl),
              if (workforce.isEmpty)
                  const EarthEmptyState(
                  message: 'No staff are assigned yet. Connect productive buildings and hire the people needed to operate them.',
                  icon: Icons.groups_outlined,
                )
              else
                EarthDataList(
                  children: workforce.map((employee) {
                    final role = employee['role']?.toString() ?? 'Staff';
                    final name = employee['name']?.toString() ?? 'Employee';
                    final employeeId = employee['id']?.toString() ?? '';
                    final skill = (asDouble(employee['skill']) ?? 0) * 100;
                    final morale = (asDouble(employee['morale']) ?? 0) * 100;

                    return EarthDataRow(
                      title: name,
                      subtitle: '$role · Skill ${skill.toStringAsFixed(0)}% · Morale ${morale.toStringAsFixed(0)}%',
                      leading: Icon(Icons.person_outline, size: context.iconSize, color: context.primaryColor),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EarthButton(
                            label: 'UPDATE',
                            onPressed: busy || employeeId.isEmpty
                                ? null
                                : () async {
                                    final roleController = TextEditingController(text: role);
                                    final wageController = TextEditingController(
                                        text: (asDouble(employee['wage']) ?? 0).toStringAsFixed(0));
                                    final result = await showDialog<List<String>>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        backgroundColor: dialogContext.panelColor,
                                        title: Text('Update $name', style: dialogContext.pageTitleStyle),
                                        content: Column(mainAxisSize: MainAxisSize.min, children: [
                                          TextField(controller: roleController, decoration: const InputDecoration(labelText: 'Role')),
                                          TextField(
                                            controller: wageController,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Daily wage (C)'),
                                          ),
                                        ]),
                                        actions: [
                                          EarthButton(
                                            label: 'CANCEL',
                                            variant: EarthButtonVariant.neutral,
                                            onPressed: () => Navigator.pop(dialogContext),
                                          ),
                                          EarthButton(
                                            label: 'SAVE',
                                            variant: EarthButtonVariant.primary,
                                            onPressed: () => Navigator.pop(dialogContext, [roleController.text, wageController.text]),
                                          ),
                                        ],
                                      ),
                                    );
                                    final newWage = double.tryParse(result?[1] ?? '');
                                    if (result != null && result[0].trim().length >= 2 && newWage != null && newWage > 0) {
                                      await action(() => const EarthApi().reassignEmployee(businessId, employeeId, result[0], newWage));
                                    }
                                  },
                          ),
                          const SizedBox(width: 4),
                          EarthButton(
                            label: 'TRAIN',
                            onPressed: busy || employeeId.isEmpty
                                ? null
                                : () => action(() => const EarthApi().trainEmployee(businessId, employeeId)),
                          ),
                          const SizedBox(width: 4),
                          EarthButton(
                            label: 'DISMISS',
                            variant: EarthButtonVariant.danger,
                            onPressed: busy || employeeId.isEmpty
                                ? null
                                : () => action(() => const EarthApi().dismissEmployee(businessId, employeeId)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ),

        SizedBox(height: context.spacingTopic),

        // FINANCIAL STATEMENT & UNIT ECONOMICS
        EarthSection(
          title: 'PERIOD FINANCIAL STATEMENT & UNIT ECONOMICS',
          showSurface: false,
          infoBulletPoints: const [
            'OPERATING REVENUE: Gross product sales from market batches and executed contracts.',
            'OPERATING COSTS: Combined raw inputs, power, maintenance reserves, and civic taxes.',
            'NET PROFIT / CYCLE: Net operating income with margin % and cost structure ratio breakdown.',
            'TAX ASSESSMENT BASE: Audited canonical taxable turnover.',
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EarthMetricGrid(
                metrics: [
                  EarthMetricTile(
                    label: 'OPERATING REVENUE',
                value: revenue == null ? 'UNAVAILABLE' : '${formatWholeNumber(revenue)} C',
                    subtitle: 'Market sales & contracts',
                    accentColor: context.successColor,
                    icon: Icons.trending_up_rounded,
                  ),
                  EarthMetricTile(
                    label: 'OPERATING COSTS',
                    value: operatingCosts == null
                        ? 'UNAVAILABLE'
                        : '${formatWholeNumber(operatingCosts)} C',
                    subtitle: 'Inputs, maint & taxes',
                    accentColor: context.warningColor,
                    icon: Icons.trending_down_rounded,
                  ),
                  EarthMetricTile(
                    label: 'NET PROFIT / CYCLE',
                    value: profit == null
                        ? 'UNAVAILABLE'
                        : '${profit >= 0 ? '+' : ''}${formatWholeNumber(profit)} C',
                    subtitle: profitMargin == null
                        ? 'Margin unavailable'
                        : 'Margin: ${profitMargin.toStringAsFixed(1)}%',
                    accentColor: profit == null
                        ? context.mutedColor
                        : profit >= 0
                            ? context.successColor
                            : context.errorColor,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  EarthMetricTile(
                    label: 'TAX ASSESSMENT BASE',
                    value: taxedRevenue == null
                        ? 'UNAVAILABLE'
                        : '${formatWholeNumber(taxedRevenue)} C',
                    subtitle: 'Audited canonical base',
                    accentColor: context.secondaryColor,
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              ),
              SizedBox(height: context.spacingControl),

              // Visual Profit vs Cost Ratio Bar
              if (profitMargin != null &&
                  costRatio != null &&
                  profitRatio != null &&
                  profit != null)
                Container(
                padding: EdgeInsets.all(context.tokens.number('pageTopics.cardPadding', 12)),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('MARGIN VS COST STRUCTURE', style: context.captionStyle),
                        Text(
                          'OPERATING MARGIN: ${profitMargin.toStringAsFixed(1)}%',
                          style: context.widgetValueStyle.copyWith(
                            color: profit >= 0 ? context.successColor : context.errorColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: 8,
                        child: Row(
                          children: [
                            Expanded(
                              flex: (costRatio * 100).toInt().clamp(1, 100),
                              child: Container(color: context.warningColor),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              flex: (profitRatio * 100).toInt().clamp(1, 100),
                              child: Container(
                                color: profit >= 0 ? context.successColor : context.errorColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                )
              else
                Container(
                  padding: EdgeInsets.all(
                      context.tokens.number('pageTopics.cardPadding', 12)),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    border: Border.all(color: context.subtleBorderColor),
                  ),
                  child: Text(
                    'Margin structure is unavailable until the business financial statement is refreshed.',
                    style: context.widgetFooterStyle,
                  ),
                ),
            ],
          ),
        ),

        SizedBox(height: context.spacingTopic),

        // CAP TABLE & GOVERNANCE
        EarthSection(
          title: 'CAP TABLE & CORPORATE GOVERNANCE',
          showSurface: false,
          infoBulletPoints: const [
            'Share distribution across equity holders, controller designation, and constitutional thresholds (Shareholder vote %, Board approval %, Dilution notice days).',
          ],
          child: Container(
            width: double.infinity,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pie_chart_outline, size: 16, color: context.secondaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'EQUITY DISTRIBUTION ($totalShares TOTAL SHARES)',
                          style: context.widgetTitleStyle,
                        ),
                      ],
                    ),
                    EarthBadge(
                      label: 'CONTROLLER: $controllingId',
                      variant: EarthBadgeVariant.primary,
                    ),
                  ],
                ),
                SizedBox(height: context.spacingControl),

                if (holders.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 10,
                      child: Row(
                        children: holders.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final holder = entry.value as Map<String, dynamic>;
                          final pct = asDoubleOr(holder['percentage'], 50.0);
                          final color = idx == 0
                              ? context.secondaryColor
                              : idx == 1
                                  ? context.primaryColor
                                  : context.warningColor;
                          return Expanded(
                            flex: pct.toInt().clamp(1, 100),
                            child: Container(
                              margin: EdgeInsets.only(right: idx < holders.length - 1 ? 2 : 0),
                              color: color,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  SizedBox(height: context.spacingControl),
                ],

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 700;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _buildShareholderItems(context, holders, controllingId),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Container(width: 1, height: 100, color: context.subtleBorderColor),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: _buildGovernanceRulesCard(
                              context,
                              shareholderThreshold,
                              boardThreshold,
                              dilutionNoticeDays,
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._buildShareholderItems(context, holders, controllingId),
                        SizedBox(height: context.spacingControl),
                        _buildGovernanceRulesCard(
                          context,
                          shareholderThreshold,
                          boardThreshold,
                          dilutionNoticeDays,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: context.spacingTopic),

        // ACTION TOOLBAR HUB
        EarthSection(
          title: 'EXECUTIVE CORPORATE ACTIONS',
          showSurface: false,
          infoBulletPoints: const [
            'Execute dividend distributions, equity transfers, share issuance, mergers, managerial appointments, and enterprise liquidation.',
          ],
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionGroupTitle(context, 'CAPITAL & EQUITY'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    EarthButton(
                      label: 'DISTRIBUTE DIVIDENDS',
                      icon: Icons.paid_outlined,
                      variant: EarthButtonVariant.secondary,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showDividendDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'TRANSFER SHARES',
                      icon: Icons.swap_horiz_rounded,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showShareTransferDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'ISSUE SHARES',
                      icon: Icons.add_circle_outline_rounded,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showShareIssueDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'PROPOSE MERGER',
                      icon: Icons.handshake_outlined,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showMergerDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'SHAREHOLDER RESOLUTION (>66.7%)',
                      icon: Icons.how_to_vote_outlined,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showShareholderResolutionDialog(context, action, businessId),
                    ),
                  ],
                ),

                SizedBox(height: context.spacingControl),

                _actionGroupTitle(context, 'GOVERNANCE & MANAGEMENT'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    EarthButton(
                      label: 'CONSTITUTION & THRESHOLDS',
                      icon: Icons.gavel_outlined,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showBusinessConstitutionDialog(context, action, business),
                    ),
                    EarthButton(
                      label: 'APPOINT MANAGER',
                      icon: Icons.badge_outlined,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showBusinessManagerDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'AI OPERATIONAL ASSISTANT',
                      icon: Icons.smart_toy_outlined,
                      variant: EarthButtonVariant.primary,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showAiAssistantConfigDialog(context, action, businessId),
                    ),
                  ],
                ),

                SizedBox(height: context.spacingControl),

                _actionGroupTitle(context, 'BUSINESS LIFECYCLE'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    EarthButton(
                      label: 'NEW BUSINESS · 250 CR',
                      icon: Icons.add_business_outlined,
                      variant: EarthButtonVariant.primary,
                      onPressed: busy
                          ? null
                          : () => showBusinessComposerDialog(
                                context,
                                action,
                                hasCity: state.membership?['city_id'] != null,
                                hasCorporation: state.membership?['corporation_id'] != null,
                              ),
                    ),
                    EarthButton(
                      label: 'RECEIVERSHIP & WORKOUT',
                      icon: Icons.account_balance_outlined,
                      variant: EarthButtonVariant.warning,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showReceivershipRestructuringDialog(context, action, businessId),
                    ),
                    EarthButton(
                      label: 'LIQUIDATE BUSINESS',
                      icon: Icons.delete_forever_outlined,
                      variant: EarthButtonVariant.danger,
                      onPressed: busy || isDissolved
                          ? null
                          : () => showBusinessLiquidationDialog(context, action, businessId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    );
  }

  List<Widget> _buildShareholderItems(
      BuildContext context, List<dynamic> holders, String controllingId) {
    if (holders.isEmpty) {
      return [
        Text('Single-member sole proprietorship.', style: context.widgetFooterStyle)
      ];
    }

    return holders.map((raw) {
      final holder = raw as Map<String, dynamic>;
      final humanId = holder['human_id']?.toString() ?? '';
      final name = holder['display_name']?.toString() ??
          (humanId.isNotEmpty ? humanId : 'Shareholder');
      final label =
          humanId.isNotEmpty && name != humanId ? '$name ($humanId)' : name;
      final shares = asIntOr(holder['shares'], 0);
      final percentage = asDoubleOr(holder['percentage'], 0.0);
      final isController = humanId.isNotEmpty && humanId == controllingId;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isController ? context.secondaryColor : context.primaryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: context.widgetTitleStyle.copyWith(
                  fontWeight: isController ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isController) ...[
              const EarthBadge(
                label: 'CONTROLLER',
                variant: EarthBadgeVariant.primary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              '$shares shares  ·  ${percentage.toStringAsFixed(1)}%',
              style: context.widgetFooterStyle,
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildGovernanceRulesCard(
      BuildContext context, double shareholderThreshold, double boardThreshold, int dilutionDays) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONSTITUTIONAL THRESHOLDS', style: context.captionStyle),
        const SizedBox(height: 6),
        _govRuleRow(context, 'Shareholder Vote:', '${(shareholderThreshold * 100).toInt()}%'),
        const SizedBox(height: 3),
        _govRuleRow(context, 'Board Approval:', '${(boardThreshold * 100).toInt()}%'),
        const SizedBox(height: 3),
        _govRuleRow(context, 'Dilution Notice:', '$dilutionDays days'),
      ],
    );
  }

  Widget _govRuleRow(BuildContext context, String label, String val) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.widgetFooterStyle),
          Text(val, style: context.widgetTitleStyle),
        ],
      );

  Widget _businessPortfolio(BuildContext context, List<dynamic> businesses) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'BUSINESS PORTFOLIO · ${businesses.length} OPERATIONS',
          style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
        ),
        const SizedBox(height: 7),
        ...businesses.whereType<Map>().map((item) {
          final name = item['name']?.toString() ?? 'Unnamed operation';
          final status = (item['status']?.toString() ?? 'active').toUpperCase();
          final profit = item['profit'];
          final businessId = item['id']?.toString();
          final isSelected = item['id']?.toString() == activeBusiness?['id']?.toString();

          return InkWell(
            onTap: businessId == null || onSelectBusiness == null
                ? null
                : () {
                    EarthAudioEngine.instance.playClick();
                    onSelectBusiness!(businessId);
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 14,
                    color: context.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: context.widgetTitleStyle.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  EarthBadge(
                    label: status,
                    variant: status == 'ACTIVE' ? EarthBadgeVariant.success : EarthBadgeVariant.neutral,
                  ),
                  if (profit != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${formatWholeNumber(asDoubleOr(profit, 0))} C',
                      style: context.widgetValueStyle.copyWith(color: context.successColor),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ]),
    );
  }

  Widget _actionGroupTitle(BuildContext context, String title) => Text(
        title,
        style: context.captionStyle,
      );

  String _policyPreview(String policy) {
    switch (policy) {
      case 'margin':
        return 'lower operating pressure, with less emphasis on maximum output.';
      case 'capacity':
        return 'higher output potential, with greater resource and upkeep demand.';
      default:
        return 'more stable output and predictable operating costs.';
    }
  }
}
