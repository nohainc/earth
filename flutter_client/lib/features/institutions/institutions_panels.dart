import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import 'institutions_dialogs.dart';

class CorporationDirectoryPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CorporationDirectoryPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<CorporationDirectoryPanel> createState() => _CorporationDirectoryPanelState();
}

class _CorporationDirectoryPanelState extends State<CorporationDirectoryPanel> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _corporations = const [];
  Map<String, dynamic>? _selected;
  bool _loading = true;
  int _searchGeneration = 0;

  bool get _isMember => widget.state.membership?['corporation_id'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CorporationDirectoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.membership?['corporation_id'] != widget.state.membership?['corporation_id']) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isMember) {
      setState(() => _loading = false);
      return;
    }
    final generation = ++_searchGeneration;
    setState(() => _loading = true);
    try {
      final rows = await const EarthApi().listCorporations(search: _search.text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _corporations = rows;
        _selected = rows.isEmpty
            ? null
            : (_selected == null
                ? rows.first
                : rows.firstWhere((row) => row['id'] == _selected!['id'], orElse: () => rows.first));
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _join() async {
    final id = _selected?['id']?.toString();
    if (id == null) return;
    await widget.action(() => const EarthApi().joinCorporation(corporationId: id));
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final id = widget.state.membership?['corporation_id']?.toString();
    if (id == null) return;
    final corporation = widget.state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(widget.state.institutions['corporation'] as Map)
        : const <String, dynamic>{};
    final name = corporation['name']?.toString() ?? 'your corporation';
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            'Leave Corporation?',
            style: context.topicTitleStyle.copyWith(color: context.warningColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This will remove you from $name and its current city. Your businesses and personal assets remain yours.',
                style: context.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                style: context.bodyStyle.copyWith(color: context.inkColor),
                onChanged: (value) => setState(() {
                  confirmed = value.trim() == name;
                }),
                decoration: InputDecoration(
                  labelText: 'Type "$name" to confirm',
                  labelStyle: context.widgetFooterStyle,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'LEAVE CORPORATION',
              variant: EarthButtonVariant.danger,
              onPressed: confirmed
                  ? () async {
                      Navigator.pop(dialogContext);
                      await widget.action(() => const EarthApi().leaveCorporation(corporationId: id));
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(widget.state.institutions['corporation'] as Map)
        : const <String, dynamic>{};

    return EarthSection(
      title: 'FIND YOUR CORPORATION',
      showSurface: false,
      infoBulletPoints: const [
        'Independent people can compare active corporations and choose a network.',
        'Every corporation has a capital city. Joining places you there automatically.',
        'Open corporations accept members immediately; approval corporations create a request for their administrators.',
        'Once affiliated, leave your current corporation before choosing another one.',
      ],
      child: _isMember ? _memberView(current) : _directoryView(),
    );
  }

  Widget _memberView(Map<String, dynamic> current) {
    final name = current['name']?.toString() ?? 'your corporation';
    final city = current['capital_city_name']?.toString() ??
        widget.state.membership?['city_id']?.toString() ??
        'capital city';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(context.cardPadding),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, size: context.iconSize + 2, color: context.primaryColor),
              SizedBox(width: context.spacingInline),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AFFILIATED', style: context.widgetValueStyle.copyWith(color: context.primaryColor)),
                    const SizedBox(height: 4),
                    Text(
                      'You are a member of $name. Your corporation membership places you in its capital city: $city.',
                      style: context.widgetFooterStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.spacingTitleOffset),
        EarthButton(
          label: 'LEAVE CORPORATION',
          icon: Icons.logout,
          variant: EarthButtonVariant.danger,
          onPressed: widget.busy ? null : () => _confirmLeave(context),
        ),
        const SizedBox(height: 7),
        Text(
          'Leaving ends the corporation-city affiliation and returns you to the independent ruleset.',
          style: context.widgetFooterStyle,
        ),
      ],
    );
  }

  Widget _directoryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EarthSearchInput(
          controller: _search,
          hintText: 'Search corporations...',
          onChanged: (_) => _load(),
          onClear: _load,
        ),
        SizedBox(height: context.spacingTitleOffset),
        if (_loading)
          Center(child: CircularProgressIndicator(color: context.primaryColor))
        else if (_corporations.isEmpty)
          const EarthEmptyState(
            message: 'No corporations found. You can found a new one from your capital city.',
            icon: Icons.domain_disabled_outlined,
          )
        else
          EarthDataList(
            children: _corporations.map((row) {
              final id = row['id']?.toString() ?? '';
              final name = row['name']?.toString() ?? id;
              final city = row['capital_city_name']?.toString() ?? 'capital city';
              final members = row['member_count'] ?? 0;
              final isSelected = _selected?['id'] == id;

              return EarthDataRow(
                title: name,
                subtitle: 'Capital: $city · $members members',
                leading: Icon(
                  Icons.domain,
                  size: context.iconSize,
                  color: isSelected ? context.primaryColor : context.mutedColor,
                ),
                isSelected: isSelected,
                onTap: () => setState(() => _selected = row),
                trailing: EarthButton(
                  label: 'JOIN',
                  variant: isSelected ? EarthButtonVariant.primary : EarthButtonVariant.secondary,
                  onPressed: widget.busy ? null : () => setState(() => _selected = row),
                ),
              );
            }).toList(),
          ),
        if (_selected != null) ...[
          SizedBox(height: context.spacingTitleOffset),
          EarthButton(
            label: 'JOIN ${_selected!['name']?.toString().toUpperCase()}',
            variant: EarthButtonVariant.primary,
            onPressed: widget.busy ? null : _join,
          ),
        ],
      ],
    );
  }
}

class CivicRankingsPanel extends StatelessWidget {
  final EarthState state;
  const CivicRankingsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthSection(
      title: 'CIVIC / CORPORATION & CITY RANKINGS',
      showSurface: false,
      infoBulletPoints: const [
        'Compare institutions by the measures that shape civic life: productive membership, city services, and resilience—not treasury alone.',
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final corp = _rows(state.rankings['corporations']);
          final cities = _rows(state.rankings['cities']);
          final wide = constraints.maxWidth > 700;

          final col1 = _rankingColumn(context, 'CORPORATIONS', corp, Icons.account_balance_outlined, 'members');
          final col2 = _rankingColumn(context, 'CITIES', cities, Icons.location_city_outlined, 'residents');

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: col1),
                SizedBox(width: context.spacingTopic),
                Expanded(child: col2),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              col1,
              SizedBox(height: context.spacingTopic),
              col2,
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).take(10).toList()
      : const [];

  Widget _rankingColumn(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> rows,
    IconData icon,
    String secondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.widgetTitleStyle),
        SizedBox(height: context.spacingControl),
        if (rows.isEmpty)
          const EarthEmptyState(
            message: 'No ranking data available.',
            icon: Icons.leaderboard_outlined,
          )
        else
          EarthDataList(
            children: rows.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final row = entry.value;
              final name = row['name']?.toString() ?? row['id']?.toString() ?? 'Institution';
              final count = row[secondary] ?? row['member_count'] ?? 0;

              return EarthDataRow(
                title: name,
                subtitle: '$count $secondary',
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '#$idx',
                        style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
                      ),
                    ),
                    Icon(icon, size: context.iconSize, color: context.mutedColor),
                  ],
                ),
                trailing: EarthBadge(
                  label: '$count $secondary',
                  variant: idx <= 3 ? EarthBadgeVariant.primary : EarthBadgeVariant.neutral,
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class CorporationOverviewPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function())? action;

  const CorporationOverviewPanel({
    super.key,
    required this.state,
    this.busy = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final corporation = state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(state.institutions['corporation'] as Map)
        : const <String, dynamic>{};
    final membership = state.membership ?? const <String, dynamic>{};
    final name = (corporation['name'] ?? 'Independent').toString();
    final id = corporation['id']?.toString() ?? '—';
    final memberCount = asIntOr(corporation['member_count'], 0);
    final treasury = asDouble(corporation['treasury']);
    final cityId = membership['city_id']?.toString();
    final sharedPatents = state.technology['corporationSharedPatents'] is List
        ? state.technology['corporationSharedPatents'] as List
        : const <dynamic>[];
    final isMember = membership['corporation_id'] != null;

    final canAdoptCity = state.roles.any((raw) {
      if (raw is! Map) return false;
      final role = raw['role_name'] ?? raw['name'] ?? raw['role'];
      return raw['status']?.toString() == 'active' &&
          role?.toString().toLowerCase() == 'corporation executive';
    });

    if (!isMember) {
      return EarthSection(
        title: 'MEMBERSHIP',
        showSurface: false,
        infoBulletPoints: const [
          'Corporation membership is optional. Independent people use Earth default rules until they choose a corporation.',
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are currently independent.',
                style: context.widgetValueStyle.copyWith(color: context.warningColor)),
            const SizedBox(height: 5),
            Text(
              'Join a corporation to access shared cities, technologies, contracts, and civic influence.',
              style: context.widgetFooterStyle,
            ),
          ],
        ),
      );
    }

    return EarthSection(
      title: 'CORPORATION',
      showSurface: false,
      infoBulletPoints: const [
        'Corporation membership determines which shared rules, cities, technologies, contracts, and services are available to you.',
        'A city belongs to a corporation: moving between cities changes your local services and opportunities while preserving corporation membership.',
        'Independent people use Earth default rules and do not participate in corporation decisions.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              name.toUpperCase(),
              textAlign: TextAlign.center,
              style: context.pageTitleStyle,
            ),
          ),
          SizedBox(height: context.spacingTitleOffset),
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'AFFILIATION',
                value: name,
                subtitle: 'ID: $id',
                icon: Icons.account_balance_outlined,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'MEMBERS',
                value: '$memberCount',
                subtitle: 'Active citizens',
                icon: Icons.groups_outlined,
                accentColor: context.secondaryColor,
              ),
              EarthMetricTile(
                label: 'TREASURY',
                value: treasury == null ? 'UNAVAILABLE' : '${formatWholeNumber(treasury)} C',
                subtitle: 'Sovereign reserves',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: context.warningColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingTopic),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.primaryColor.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.primaryColor.withValues(alpha: .22)),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_outlined, size: context.iconSize + 2, color: context.primaryColor),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CORPORATION RESEARCH COMMONS',
                        style: context.captionStyle.copyWith(color: context.primaryColor),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sharedPatents.isEmpty
                            ? 'No shared patents are visible yet.'
                            : '${sharedPatents.length} shared capabilities available to this corporation network.',
                        style: context.widgetFooterStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.spacingTopic),
          Text('CORPORATE CHARTER & BYLAWS', style: context.widgetTitleStyle),
          const SizedBox(height: 4),
          Text(
            'Operational policies governed by this corporation. Overrides Earth baseline within constitutional boundaries.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),
          EarthDataList(
            children: [
              EarthDataRow(
                title: 'Internal Corporate Tax Levy',
                subtitle:
                    '2.0% on affiliated business revenues\nAllocated directly to the sovereign corporate treasury to fund public goods and research. Parent Earth ceiling: Max 15.0%.',
                leading: Icon(Icons.receipt_long_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(label: 'CUSTOM OVERRIDE', variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Corporate Dividend Distribution',
                subtitle:
                    '50% treasury retained · 50% distributed to equity holders per game-cycle based on registered shareholding.',
                leading: Icon(Icons.payments_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(label: 'CUSTOM OVERRIDE', variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Shareholder Supermajority Protection',
                subtitle:
                    '67.0% voting supermajority required for charter amendments, corporate restructuring, or asset liquidations.',
                leading: Icon(Icons.lock_outline_rounded, size: context.iconSize, color: context.primaryColor),
                badges: const [
                  EarthBadge(label: 'IMMUTABLE INVARIANT', variant: EarthBadgeVariant.neutral),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Membership Admission Standards',
                subtitle:
                    'Current policy: ${(corporation['admission_policy'] ?? 'open').toString().toUpperCase()}. Open admission welcomes all universal citizens; approval requires executive review.',
                leading: Icon(Icons.how_to_reg_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: [
                  EarthBadge(
                    label: (corporation['admission_policy'] ?? 'open').toString().toLowerCase() == 'open'
                        ? 'EARTH DEFAULT'
                        : 'CUSTOM OVERRIDE',
                    variant: (corporation['admission_policy'] ?? 'open').toString().toLowerCase() == 'open'
                        ? EarthBadgeVariant.neutral
                        : EarthBadgeVariant.primary,
                  ),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Executive Role & Adoption Powers',
                subtitle:
                    'Active Corporation Executives hold statutory authority to adopt unclaimed cities and introduce governance proposals.',
                leading: Icon(Icons.manage_accounts_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(label: 'EARTH DEFAULT', variant: EarthBadgeVariant.neutral),
                ],
                showDivider: false,
              ),
            ],
          ),
          SizedBox(height: context.spacingTopic),
          Text('CORPORATION DECISIONS', style: context.widgetTitleStyle),
          const SizedBox(height: 5),
          Text(
            'Choose belonging · compare cities · support or challenge corporation rules · use shared technology · build a business network · move when another city offers a better future.',
            style: context.widgetFooterStyle,
          ),
          if (isMember && id != '—') ...[
            SizedBox(height: context.spacingTitleOffset),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                EarthButton(
                  label: 'CORPORATION RULES',
                  icon: Icons.gavel_outlined,
                  variant: EarthButtonVariant.secondary,
                  onPressed: busy
                      ? null
                      : () => showTaxCharterDialog(context, action ?? ((_) async {}), id, corporation: true),
                ),
                if (canAdoptCity)
                  EarthButton(
                    label: corporation['admission_policy']?.toString() == 'approval'
                        ? 'ADMISSION: APPROVAL'
                        : 'ADMISSION: OPEN',
                    icon: Icons.how_to_reg_outlined,
                    variant: EarthButtonVariant.secondary,
                    onPressed: busy
                        ? null
                        : () => showAdmissionPolicyDialog(
                              context,
                              action ?? ((_) async {}),
                              id,
                              currentPolicy: corporation['admission_policy']?.toString() ?? 'open',
                            ),
                  ),
                EarthButton(
                  label: 'LEAVE CORPORATION',
                  icon: Icons.logout,
                  variant: EarthButtonVariant.danger,
                  onPressed: busy ? null : () => _confirmLeave(context, name, id),
                ),
              ],
            ),
          ],
          if (isMember && state.rankings['cities'] is List && (state.rankings['cities'] as List).isNotEmpty) ...[
            SizedBox(height: context.spacingTopic),
            Text('CORPORATION CITY NETWORK', style: context.widgetTitleStyle),
            const SizedBox(height: 4),
            Text('Rules apply across the corporation network.', style: context.widgetFooterStyle),
            SizedBox(height: context.spacingControl),
            EarthDataList(
              children: (state.rankings['cities'] as List).take(8).map((raw) {
                final row = Map<String, dynamic>.from(raw as Map);
                final city = row['id']?.toString() ?? 'City';
                final owner = row['corporation_id']?.toString();
                final belongsToUs = owner == id;
                final unclaimed = owner == null || owner.isEmpty;

                return EarthDataRow(
                  title: '${row['name'] ?? city}',
                  subtitle: '${row['residents'] ?? 0} residents',
                  leading: Icon(
                    belongsToUs ? Icons.domain : Icons.location_city_outlined,
                    size: context.iconSize,
                    color: belongsToUs ? context.primaryColor : context.mutedColor,
                  ),
                  trailing: isMember && belongsToUs && city != cityId
                      ? EarthButton(
                          label: 'MOVE',
                          variant: EarthButtonVariant.primary,
                          onPressed: busy
                              ? null
                              : () => action?.call(() => const EarthApi().joinCity(cityId: city)),
                        )
                      : (isMember && unclaimed && canAdoptCity
                          ? EarthButton(
                              label: 'ADOPT',
                              variant: EarthButtonVariant.secondary,
                              onPressed: busy
                                  ? null
                                  : () => action?.call(() => const EarthApi()
                                      .adoptCityForCorporation(corporationId: id, cityId: city)),
                            )
                          : EarthBadge(
                              label: owner ?? 'UNCLAIMED',
                              variant: belongsToUs ? EarthBadgeVariant.primary : EarthBadgeVariant.neutral,
                            )),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, String corporationName, String corporationId) async {
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            'Leave Corporation?',
            style: context.topicTitleStyle.copyWith(color: context.warningColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Leaving $corporationName removes your corporation and city affiliation. Your personal assets remain yours.',
                style: context.widgetFooterStyle,
              ),
              const SizedBox(height: 12),
              TextField(
                style: context.bodyStyle.copyWith(color: context.inkColor),
                onChanged: (value) => setState(() => confirmed = value.trim() == corporationName),
                decoration: InputDecoration(
                  labelText: 'Type "$corporationName" to confirm',
                  labelStyle: context.widgetFooterStyle,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('CANCEL', style: context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'LEAVE CORPORATION',
              variant: EarthButtonVariant.danger,
              onPressed: confirmed
                  ? () async {
                      Navigator.pop(dialogContext);
                      await (action ?? ((_) async {}))(
                          () => const EarthApi().leaveCorporation(corporationId: corporationId));
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class InstitutionsCapacityPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const InstitutionsCapacityPanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['city'] is Map<String, dynamic>
        ? (state.institutions['city'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final cityId = city['id']?.toString() ?? 'CITY-0084';
    final cityName = (city['name']?.toString() ?? 'NEW CARTHAGE').toUpperCase();
    final residents = asIntOr(city['residents'], 100);
    final housingCap = asIntOr(city['housing_capacity'], 120);
    final energyCap = asIntOr(city['energy_capacity'], 200);

    final isCityResident = state.membership?['city_id'] != null;

    final housingRatio = formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio = formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);
    final cityMembers = state.json['cityMembers'] is List
        ? List<dynamic>.from(state.json['cityMembers'] as List)
        : const <dynamic>[];
    final playerId = state.human['id']?.toString();
    final playerRank = cityMembers.indexWhere((raw) => raw is Map && raw['id']?.toString() == playerId) + 1;

    return EarthSection(
      key: panelKey,
      title: 'INSTITUTIONS / CITY & SERVICES',
      showSurface: false,
      infoBulletPoints: const [
        'Municipal Administration & Service Capacity: Oversight of public housing, energy grid, connectivity, and healthcare.',
        'City Standing: Civic prestige and influence among resident citizens.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              cityName,
              textAlign: TextAlign.center,
              style: context.pageTitleStyle,
            ),
          ),
          SizedBox(height: context.spacingTitleOffset),

          // City Administration Card
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(context.radiusControl),
                      ),
                      child: Icon(Icons.location_city_outlined, size: context.iconSize + 4, color: context.primaryColor),
                    ),
                    SizedBox(width: context.spacingTitleOffset),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(cityId, style: context.widgetValueStyle),
                              ),
                              EarthBadge(
                                label: isCityResident ? 'RESIDENT' : 'NON-RESIDENT',
                                variant: isCityResident ? EarthBadgeVariant.primary : EarthBadgeVariant.neutral,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$residents residents · Housing cap: $housingCap · Energy cap: $energyCap',
                            style: context.widgetFooterStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: context.spacingTitleOffset),

                // Service Pressure Gauges Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .03),
                    borderRadius: BorderRadius.circular(context.radiusControl),
                  ),
                  child: Text(
                    'Service pressure: Housing $housingRatio · Energy $energyRatio · Connect $connectRatio · Health $healthRatio',
                    style: context.widgetFooterStyle.copyWith(color: context.inkColor),
                  ),
                ),

                if (isCityResident && cityMembers.isNotEmpty) ...[
                  SizedBox(height: context.spacingTitleOffset),
                  Text('CITY STANDING', style: context.widgetTitleStyle),
                  const SizedBox(height: 4),
                  Text(
                    playerRank > 0
                        ? 'You rank #$playerRank among active residents by civic standing.'
                        : 'Resident standings are being established for this city.',
                    style: context.widgetFooterStyle,
                  ),
                  SizedBox(height: context.spacingControl),
                  EarthDataList(
                    children: cityMembers.take(5).toList().asMap().entries.map((entry) {
                      final member = Map<String, dynamic>.from(entry.value as Map);
                      final isPlayer = member['id']?.toString() == playerId;
                      final name = member['display_name']?.toString() ?? member['id']?.toString() ?? 'Resident';

                      return EarthDataRow(
                        title: name,
                        subtitle: 'Standing: ${member['standing'] ?? 0}',
                        leading: Text('#${entry.key + 1}',
                            style: context.widgetTitleStyle.copyWith(color: context.primaryColor)),
                        badges: [
                          if (isPlayer) const EarthBadge(label: 'YOU', variant: EarthBadgeVariant.primary),
                        ],
                      );
                    }).toList(),
                  ),
                ],

                SizedBox(height: context.spacingTitleOffset),

                // City Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    EarthButton(
                      label: 'CHANGE CITY',
                      variant: isCityResident ? EarthButtonVariant.secondary : EarthButtonVariant.primary,
                      onPressed: busy ? null : () => showCityChangeDialog(context, state, cityId, action),
                    ),
                    EarthButton(
                      label: 'PROPOSE BUDGET',
                      icon: Icons.account_balance_wallet_outlined,
                      variant: EarthButtonVariant.secondary,
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi().setCityBudget('maintenance', cityId: cityId)),
                    ),
                    EarthButton(
                      label: 'TAX CHARTER',
                      icon: Icons.receipt_long_outlined,
                      variant: EarthButtonVariant.secondary,
                      onPressed: busy ? null : () => showTaxCharterDialog(context, action, cityId),
                    ),
                    if (state.communities.isNotEmpty)
                      EarthButton(
                        label: 'FORM CITY',
                        icon: Icons.add_business_outlined,
                        variant: EarthButtonVariant.primary,
                        onPressed: busy
                            ? null
                            : () => showFormationComposer(
                                  context,
                                  action,
                                  city: true,
                                  communityId: (state.communities.first as Map<String, dynamic>)['id'] as String,
                                ),
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
}

class CityImpactPanel extends StatelessWidget {
  final EarthState state;

  const CityImpactPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['city'] is Map
        ? Map<String, dynamic>.from(state.institutions['city'] as Map)
        : const <String, dynamic>{};
    final ratios = state.world['serviceRatios'] is Map
        ? Map<String, dynamic>.from(state.world['serviceRatios'] as Map)
        : const <String, dynamic>{};
    final pressure = asDouble(city['service_pressure'] ?? city['servicePressure']);
    final taxRate = asDouble(city['tax_rate'] ?? city['taxRate']);
    final business = state.business;
    final operatingEffect = asDouble(business['city_operating_modifier'] ?? business['cityOperatingModifier']);

    final services = [
      ('HOUSING', ratios['housing']),
      ('ENERGY', ratios['energy']),
      ('CONNECTIVITY', ratios['connectivity']),
      ('HEALTH', ratios['health']),
    ];

    return EarthSection(
      title: 'CITY EFFECTS / LIFE & BUSINESS',
      showSurface: false,
      infoBulletPoints: const [
        'City conditions affect your life and businesses through services, taxes, workforce quality, and operating costs.',
        'Pressure above the city baseline can increase friction and reduce service reliability.',
        'Values marked unavailable require current city or business data; they are not estimates.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            city['name'] == null
                ? 'No city effect is currently reported.'
                : 'Living in ${city['name']} changes your services, costs, and opportunities.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingTitleOffset),
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'CITY PRESSURE',
                value: pressure == null ? 'UNAVAILABLE' : '${pressure.toStringAsFixed(0)}%',
                subtitle: pressure == null
                    ? 'Pressure data unavailable'
                    : (pressure > 70 ? 'Costs under strain' : 'Normal service load'),
                icon: Icons.speed_outlined,
                accentColor: pressure != null && pressure > 70 ? context.warningColor : context.primaryColor,
              ),
              EarthMetricTile(
                label: 'BUSINESS EFFECT',
                value: operatingEffect == null
                    ? 'UNAVAILABLE'
                    : '${operatingEffect >= 0 ? '+' : ''}${operatingEffect.toStringAsFixed(1)}%',
                subtitle: operatingEffect == null ? 'No modifier reported' : 'Operating cost modifier',
                icon: Icons.storefront_outlined,
                accentColor: operatingEffect != null && operatingEffect > 0 ? context.warningColor : context.successColor,
              ),
              EarthMetricTile(
                label: 'CITY TAX',
                value: taxRate == null ? 'UNAVAILABLE' : '${taxRate.toStringAsFixed(1)}%',
                subtitle: 'Current resident rate',
                icon: Icons.receipt_long_outlined,
                accentColor: context.secondaryColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingTopic),
          Text('SERVICE CONDITIONS', style: context.widgetTitleStyle),
          SizedBox(height: context.spacingControl),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: services.map((service) {
              final value = asDouble(service.$2);
              return EarthBadge(
                label: '${service.$1} · ${value == null ? 'UNAVAILABLE' : '${(value * 100).round()}%'}',
                variant: value == null
                    ? EarthBadgeVariant.neutral
                    : (value < .5
                        ? EarthBadgeVariant.error
                        : (value < .75 ? EarthBadgeVariant.warning : EarthBadgeVariant.success)),
              );
            }).toList(),
          ),
          SizedBox(height: context.spacingTopic),
          Text('MUNICIPAL ORDINANCES & TARIFFS', style: context.widgetTitleStyle),
          const SizedBox(height: 4),
          Text(
            'Local ordinances and service tariffs set by this municipality. Restricted by Corporate Charters and Earth Law.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),
          EarthDataList(
            children: [
              EarthDataRow(
                title: 'Municipal Energy & Grid Tariff',
                subtitle:
                    '${taxRate == null ? '3.0' : (taxRate * 100).toStringAsFixed(1)}% consumption tariff\nApplied to municipal energy grid load and infrastructure utility draws.',
                leading: Icon(Icons.bolt_outlined, size: context.iconSize, color: context.warningColor),
                badges: const [
                  EarthBadge(label: 'CUSTOM OVERRIDE', variant: EarthBadgeVariant.warning),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Public Housing & Residency Criteria',
                subtitle:
                    'Priority allocation granted to active municipal residents and registered corporate affiliate citizens.',
                leading: Icon(Icons.home_work_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(label: 'DELEGATED', variant: EarthBadgeVariant.neutral),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Infrastructure Maintenance Assessment',
                subtitle:
                    'Municipal surcharge funding local transport connectivity, water filtration, and community health centers.',
                leading: Icon(Icons.construction_outlined, size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(label: 'CUSTOM OVERRIDE', variant: EarthBadgeVariant.warning),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Essential Services Minimum Standard',
                subtitle:
                    'Municipal service ratios must maintain minimum survival index (>0.50) as guaranteed by Planetary Law.',
                leading: Icon(Icons.shield_outlined, size: context.iconSize, color: context.primaryColor),
                badges: const [
                  EarthBadge(label: 'IMMUTABLE INVARIANT', variant: EarthBadgeVariant.neutral),
                ],
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CommunitiesPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CommunitiesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final communities = state.communities;
    final totalMembers = communities.fold<int>(
      0,
      (sum, raw) => sum + asIntOr((raw as Map)['member_count'], 12),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EarthSection(
            title: 'CITIZEN COMMUNITIES & GUILDS',
            showSurface: false,
            infoBulletPoints: const [
              'Civic Communities & Cooperatives: Grassroots voluntary associations formed by citizens for collective mutual aid, cultural affinity, industry cooperation, and shared projects.',
              'Membership & Contributions: Join or leave freely; voluntary treasury contributions fund shared communal initiatives and social crowdfunding campaigns.',
              'Cross-World Belonging: Communities are independent citizen associations spanning across all corporations and cities on Earth.',
            ],
            trailing: EarthButton(
              label: 'FOUND COMMUNITY',
              icon: Icons.add_rounded,
              variant: EarthButtonVariant.primary,
              onPressed: busy ? null : () => showCommunityComposer(context, action),
            ),
            child: EarthMetricGrid(
              metrics: [
                EarthMetricTile(
                  label: 'ACTIVE GUILDS',
                  value: '${communities.length}',
                  subtitle: 'Registered cooperatives',
                  icon: Icons.groups_outlined,
                  accentColor: context.primaryColor,
                ),
                EarthMetricTile(
                  label: 'COMMUNITY MEMBERS',
                  value: '$totalMembers',
                  subtitle: 'Participating citizens',
                  icon: Icons.person_search_outlined,
                  accentColor: context.secondaryColor,
                ),
                EarthMetricTile(
                  label: 'COMMUNAL INITIATIVES',
                  value: 'ACTIVE',
                  subtitle: 'Social crowdfunding',
                  icon: Icons.handshake_outlined,
                  accentColor: context.warningColor,
                ),
              ],
            ),
          ),
          SizedBox(height: context.spacingSection),
          EarthSection(
            title: 'PLANETARY COMMUNITY REGISTRY',
            showSurface: false,
            child: communities.isEmpty
                ? const EarthEmptyState(
                    message: 'No communities registered yet. You can found the first one.',
                    icon: Icons.groups_outlined,
                  )
                : EarthDataList(
                    children: communities.map((raw) {
                      final community = raw as Map<String, dynamic>;
                      final id = community['id']?.toString() ?? 'COM-001';
                      final name = community['name']?.toString() ?? 'Community';
                      final status = (community['status']?.toString() ?? 'active').toUpperCase();
                      final members = asIntOr(community['member_count'], 12);
                      final sharedCredits = asDouble(community['shared_credits']) ?? 0.0;

                      return EarthDataRow(
                        title: '$name ($id)',
                        subtitle: '$members members · ${sharedCredits.toStringAsFixed(0)} C in communal treasury',
                        leading: Icon(
                          Icons.groups_outlined,
                          size: context.iconSize,
                          color: context.primaryColor,
                        ),
                        badges: [
                          EarthBadge(
                            label: status,
                            variant: status == 'ACTIVE' ? EarthBadgeVariant.primary : EarthBadgeVariant.neutral,
                          ),
                        ],
                        trailing: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            EarthButton(
                              label: 'JOIN',
                              variant: EarthButtonVariant.primary,
                              onPressed: busy ? null : () => action(() => const EarthApi().joinCommunity(id)),
                            ),
                            EarthButton(
                              label: 'LEAVE',
                              variant: EarthButtonVariant.danger,
                              onPressed: busy ? null : () => action(() => const EarthApi().leaveCommunity(id)),
                            ),
                            EarthButton(
                              label: 'CONTRIBUTE',
                              variant: EarthButtonVariant.secondary,
                              onPressed: busy ? null : () => showCommunityContributionDialog(context, action, id),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
