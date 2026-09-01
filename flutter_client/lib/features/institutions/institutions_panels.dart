import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import '../governance/governance_panels.dart';
import '../house/house_lineage_dialog.dart';
import 'institutions_dialogs.dart';

Widget _institutionBudgetCard(
  BuildContext context, {
  required String title,
  required String amount,
  required IconData icon,
  required String description,
  required Color accent,
}) {
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(context.cardPadding),
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(context.radiusCard),
      border: Border.all(color: accent.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 20),
        SizedBox(width: context.spacingInline),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: context.captionStyle.copyWith(color: accent)),
                  Text(amount, style: context.widgetValueStyle.copyWith(color: accent)),
                ],
              ),
              const SizedBox(height: 4),
              Text(description, style: context.widgetFooterStyle),
            ],
          ),
        ),
      ],
    ),
  );
}

class CorporationDirectoryPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final String? selectedCorporationId;
  final ValueChanged<Map<String, dynamic>>? onSelectCorporation;
  final bool isExpandable;
  final bool showMemberSummary;
  final bool showSelection;

  const CorporationDirectoryPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.selectedCorporationId,
    this.onSelectCorporation,
    this.isExpandable = false,
    this.showMemberSummary = true,
    this.showSelection = true,
  });

  @override
  State<CorporationDirectoryPanel> createState() =>
      _CorporationDirectoryPanelState();
}

class _CorporationDirectoryPanelState extends State<CorporationDirectoryPanel> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _corporations = const [];
  Map<String, dynamic>? _selected;
  String? _expandedId;
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
    if (oldWidget.state.membership?['corporation_id'] !=
        widget.state.membership?['corporation_id']) {
      _load();
    } else if (widget.selectedCorporationId != null &&
        widget.selectedCorporationId != oldWidget.selectedCorporationId &&
        _corporations.isNotEmpty) {
      final match = _corporations.firstWhere(
        (r) => r['id']?.toString() == widget.selectedCorporationId,
        orElse: () => _selected ?? _corporations.first,
      );
      setState(() => _selected = match);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final fallback = widget.state.rankings['corporations'] is List
        ? (widget.state.rankings['corporations'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : <Map<String, dynamic>>[];

    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      if (fallback.isNotEmpty && _corporations.isEmpty) {
        _corporations = fallback;
        _selected = fallback.first;
      }
    });
    try {
      final rows =
          await const EarthApi().listCorporations(search: _search.text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _corporations = rows.isNotEmpty ? rows : fallback;
        if (widget.selectedCorporationId != null) {
          _selected = _corporations.firstWhere(
            (r) => r['id']?.toString() == widget.selectedCorporationId,
            orElse: () => _corporations.isNotEmpty ? _corporations.first : {},
          );
        } else {
          _selected = _corporations.isEmpty
              ? null
              : (_selected == null
                  ? _corporations.first
                  : _corporations.firstWhere(
                      (row) => row['id'] == _selected!['id'],
                      orElse: () => _corporations.first));
        }
        if (_selected != null && _selected!.isNotEmpty) {
          widget.onSelectCorporation?.call(_selected!);
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          if (_corporations.isEmpty && fallback.isNotEmpty) {
            _corporations = fallback;
            _selected = _corporations.first;
            widget.onSelectCorporation?.call(_selected!);
          }
          _loading = false;
        });
      }
    }
  }

  Future<void> _join([Map<String, dynamic>? corp]) async {
    final target = corp ?? _selected;
    final id = target?['id']?.toString();
    if (id == null) return;
    await widget
        .action(() => const EarthApi().joinCorporation(corporationId: id));
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final id = widget.state.membership?['corporation_id']?.toString();
    if (id == null) return;
    final corporation = widget.state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(
            widget.state.institutions['corporation'] as Map)
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
            side:
                BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            'Leave Corporation?',
            style:
                context.topicTitleStyle.copyWith(color: context.warningColor),
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
              child: Text('CANCEL',
                  style:
                      context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'LEAVE CORPORATION',
              variant: EarthButtonVariant.danger,
              onPressed: confirmed
                  ? () async {
                      Navigator.pop(dialogContext);
                      await widget.action(() =>
                          const EarthApi().leaveCorporation(corporationId: id));
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _nodeMiniStat(BuildContext context, String label, String value) {
    final tokens = context.tokens;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final themeColor = Theme.of(context).colorScheme.primary;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: mutedColor,
              fontSize: tokens.number('typography.widgetTitle.size', 10),
              fontWeight: FontWeight.w700,
              letterSpacing:
                  tokens.number('typography.widgetTitle.letterSpacing', 1.4),
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: themeColor,
              fontWeight: FontWeight.w700,
              fontSize: tokens.number('typography.widgetValue.size', 12),
              letterSpacing:
                  tokens.number('typography.widgetValue.letterSpacing', 1.4),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.bodyStyle.copyWith(
              color: context.mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: context.bodyStyle.copyWith(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.bodyStyle.copyWith(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: context.widgetFooterStyle.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedCorporationDetails(
      BuildContext context, Map<String, dynamic> row, bool isAffiliated) {
    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? id;
    final city = row['capital_city_name']?.toString() ?? 'Capital City';
    final members = asIntOr(row['member_count'] ?? row['members'], 0);
    final cityCount = asIntOr(row['city_count'], 1);
    final treasury = asDouble(row['treasury']) ?? 0.0;
    final admissionPolicy =
        (row['admission_policy'] ?? 'open').toString().toUpperCase();

    final rules = row['rules'] is Map
        ? Map<String, dynamic>.from(row['rules'] as Map)
        : const <String, dynamic>{};

    final incomeTaxBps =
        asIntOr(rules['incomeTaxBps'] ?? rules['income_tax_bps'], 200);
    final salesTaxBps =
        asIntOr(rules['salesTaxBps'] ?? rules['sales_tax_bps'], 100);
    final corporateTaxBps =
        asIntOr(rules['corporateTaxBps'] ?? rules['corporate_tax_bps'], 250);
    final propertyTaxBps =
        asIntOr(rules['propertyTaxBps'] ?? rules['property_tax_bps'], 150);

    final sharedPatents = row['shared_patents'] is List
        ? row['shared_patents'] as List
        : (widget.state.technology['corporationSharedPatents'] is List
            ? widget.state.technology['corporationSharedPatents'] as List
            : const <dynamic>[]);

    final canAdoptCity = isAffiliated &&
        widget.state.roles.any((raw) {
          if (raw is! Map) return false;
          final role = raw['role_name'] ?? raw['name'] ?? raw['role'];
          return raw['status']?.toString() == 'active' &&
              role?.toString().toLowerCase() == 'corporation executive';
        });

    final leftColumn = [
      _buildAttributeRow(
        context,
        icon: Icons.shield_outlined,
        label: 'ADMISSION POLICY',
        value: admissionPolicy,
        accentColor: context.primaryColor,
      ),
      _buildAttributeRow(
        context,
        icon: Icons.home_work_outlined,
        label: 'PROPERTY LEVY',
        value: '${(propertyTaxBps / 100).toStringAsFixed(1)}%',
        accentColor: context.primaryColor,
      ),
      _buildAttributeRow(
        context,
        icon: Icons.science_outlined,
        label: 'SHARED PATENTS',
        value: '${sharedPatents.length}',
        accentColor: context.secondaryColor,
      ),
    ];

    final rightColumn = [
      _buildAttributeRow(
        context,
        icon: Icons.account_balance_wallet_outlined,
        label: 'TREASURY',
        value: '${formatWholeNumber(treasury)} C',
        accentColor: context.warningColor,
      ),
      _buildAttributeRow(
        context,
        icon: Icons.hub_outlined,
        label: 'CHARTERED CITIES',
        value: '$cityCount',
        accentColor: context.secondaryColor,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 450;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: leftColumn)),
                  const SizedBox(width: 20),
                  Expanded(child: Column(children: rightColumn)),
                ],
              )
            else ...[
              ...leftColumn,
              ...rightColumn,
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!_isMember && !isAffiliated)
                  EarthButton(
                    label: 'JOIN CORPORATION',
                    icon: Icons.login,
                    variant: EarthButtonVariant.primary,
                    onPressed: widget.busy ? null : () => _join(row),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildUniversalCharterTopic(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_outlined, size: 16, color: context.primaryColor),
              const SizedBox(width: 8),
              Text(
                'UNIVERSAL CHARTER PRINCIPLES',
                style: TextStyle(
                  color: context.primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Core constitutional rules applied uniformly across all sovereign corporate jurisdictions on Earth:',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 500;
              final col1 = [
                _buildBenefitRow(
                  context,
                  Icons.shield_outlined,
                  'Corporate Tax Protection',
                  'Affiliated citizens enjoy protected municipal tax caps across all constituent network cities.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.biotech_outlined,
                  'Shared Technology & Patents',
                  'Free access to shared corporate technology and patent pool without external licensing fees.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.how_to_vote_outlined,
                  'Shareholder Democratic Franchise',
                  'Every member votes on corporate leadership, municipal tax updates, and city adoptions.',
                ),
              ];
              final col2 = [
                _buildBenefitRow(
                  context,
                  Icons.payments_outlined,
                  'Dividend Distribution Policy',
                  '50% retained in corporate treasury · 50% distributed to equity holders each cycle.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.lock_outline_rounded,
                  'Shareholder Supermajority Invariant',
                  '67.0% voting supermajority required for charter amendments and structural liquidations.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.manage_accounts_outlined,
                  'Executive Governance Authority',
                  'Active Executives hold statutory authority to manage municipal charters and introduce proposals.',
                ),
              ];

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: col1)),
                    const SizedBox(width: 20),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: col2)),
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...col1,
                    const SizedBox(height: 10),
                    ...col2,
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCorporationNodeCard(
    BuildContext context,
    Map<String, dynamic> row,
    bool isExpanded,
    bool isSelected,
    bool isAffiliated,
  ) {
    final tokens = context.tokens;
    final themeColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = Theme.of(context).colorScheme.secondary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);

    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? id;
    final city = row['capital_city_name']?.toString() ?? 'Capital City';
    final members = asIntOr(row['member_count'] ?? row['members'], 0);
    final cityCount = asIntOr(row['city_count'], 1);
    final treasury = asDouble(row['treasury']) ?? 0.0;

    final rules = row['rules'] is Map
        ? Map<String, dynamic>.from(row['rules'] as Map)
        : const <String, dynamic>{};

    final incomeTaxBps =
        asIntOr(rules['incomeTaxBps'] ?? rules['income_tax_bps'], 200);
    final salesTaxBps =
        asIntOr(rules['salesTaxBps'] ?? rules['sales_tax_bps'], 100);
    final corporateTaxBps =
        asIntOr(rules['corporateTaxBps'] ?? rules['corporate_tax_bps'], 250);

    final cardBorderColor = (isExpanded || isSelected)
        ? themeColor.withValues(alpha: .6)
        : (isAffiliated
            ? themeColor.withValues(alpha: .35)
            : context.subtleBorderColor);

    return Container(
      padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 12)),
      decoration: BoxDecoration(
        color: (isExpanded || isSelected)
            ? context.surfaceColor
            : context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(
            color: cardBorderColor,
            width: (isExpanded || isSelected) ? 1.5 : 1.0),
        boxShadow: (isExpanded || isSelected)
            ? [
                BoxShadow(
                  color: themeColor.withValues(alpha: .15),
                  blurRadius: 10,
                )
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row (Clickable Node Summary)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isAffiliated
                      ? themeColor.withValues(alpha: .2)
                      : secondaryColor.withValues(alpha: .15),
                  border: Border.all(
                    color: isAffiliated ? themeColor : secondaryColor,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.domain,
                    color: isAffiliated ? themeColor : secondaryColor,
                    size: 22,
                  ),
                ),
              ),
              SizedBox(width: tokens.number('spacing.titleOffset', 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: TextStyle(
                              color: (isAffiliated || isSelected || isExpanded)
                                  ? themeColor
                                  : context.inkColor,
                              fontWeight: FontWeight.w700,
                              fontSize: tokens.number(
                                  'typography.widgetValue.size', 13),
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: _nodeMiniStat(context, 'Capital', city),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Sorted attributes (alphabetical order, no badges in head record)
                    Wrap(
                      spacing: tokens.number('spacing.titleOffset', 12),
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _nodeMiniStat(context, 'Cities', '$cityCount'),
                        _nodeMiniStat(context, 'Citizens', '$members'),
                        _nodeMiniStat(context, 'Corp Tax',
                            '${(corporateTaxBps / 100).toStringAsFixed(1)}%'),
                        _nodeMiniStat(context, 'Income Tax',
                            '${(incomeTaxBps / 100).toStringAsFixed(1)}%'),
                        _nodeMiniStat(context, 'Market Fee',
                            '${(salesTaxBps / 100).toStringAsFixed(1)}%'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (widget.isExpandable)
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: isExpanded ? themeColor : mutedColor,
                  size: 22,
                )
              else
                Wrap(
                  spacing: 6,
                  children: [
                    EarthButton(
                      label: 'CHARTER & PERKS',
                      icon: Icons.info_outline,
                      variant: EarthButtonVariant.ghost,
                      onPressed: () => showCorporationCharterDialog(
                        context,
                        row,
                        widget.state,
                        isMember: isAffiliated,
                        onJoin: () {
                          setState(() => _selected = row);
                          _join(row);
                        },
                      ),
                    ),
                    if (!_isMember && !isAffiliated)
                      EarthButton(
                        label: 'JOIN',
                        variant: isSelected
                            ? EarthButtonVariant.primary
                            : EarthButtonVariant.secondary,
                        onPressed: widget.busy
                            ? null
                            : () {
                                setState(() => _selected = row);
                                _join(row);
                              },
                      ),
                  ],
                ),
            ],
          ),

          // Expandable Dossier Content
          if (widget.isExpandable && isExpanded) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: context.subtleBorderColor),
            const SizedBox(height: 12),
            _buildExpandedCorporationDetails(context, row, isAffiliated),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(
            widget.state.institutions['corporation'] as Map)
        : const <String, dynamic>{};

    return EarthSection(
      title: 'PLANETARY CORPORATIONS & CHARTERS',
      showSurface: false,
      infoBulletPoints: const [
        'Ancestral corporate directory tracking active alliances across world jurisdiction.',
        'Tap any corporation record to expand its full charter, sovereign treasury, and tax bylaws.',
        'Joining a corporation integrates your enterprise into its municipal network and patent pool.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUniversalCharterTopic(context),
          const SizedBox(height: 24),
          if (widget.showMemberSummary && _isMember) ...[
            _memberView(current),
            const SizedBox(height: 32),
            Text(
              'ALL PLANETARY CORPORATIONS',
              style:
                  context.topicTitleStyle.copyWith(color: context.mutedColor),
            ),
            const SizedBox(height: 12),
          ],
          _directoryView(),
        ],
      ),
    );
  }

  Widget _memberView(Map<String, dynamic> current) {
    final name = current['name']?.toString() ?? 'your corporation';
    final city = current['capital_city_name']?.toString() ??
        widget.state.membership?['city_id']?.toString() ??
        'capital city';
    final members = current['member_count'] ?? 0;
    final treasury = asDouble(current['treasury']) ?? 0.0;

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined,
                  size: context.iconSize + 4, color: context.primaryColor),
              SizedBox(width: context.spacingInline),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('ACTIVE AFFILIATION: $name',
                              style: context.widgetValueStyle
                                  .copyWith(color: context.primaryColor)),
                        ),
                        const EarthBadge(
                          label: 'MEMBER JURISDICTION',
                          variant: EarthBadgeVariant.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are affiliated with $name. Your residency is registered in its capital city: $city ($members citizens · ${treasury.toStringAsFixed(0)} C treasury reserves).',
                      style:
                          context.bodyStyle.copyWith(color: context.inkColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              EarthButton(
                label: 'VIEW CONSTITUTION & TAX CHARTER',
                icon: Icons.account_balance_outlined,
                variant: EarthButtonVariant.primary,
                onPressed: () => showCorporationCharterDialog(
                  context,
                  current,
                  widget.state,
                  isMember: true,
                ),
              ),
              EarthButton(
                label: 'LEAVE CORPORATION',
                icon: Icons.logout,
                variant: EarthButtonVariant.danger,
                onPressed: widget.busy ? null : () => _confirmLeave(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _directoryView() {
    final currentCorpId =
        widget.state.membership?['corporation_id']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: EarthSearchInput(
                controller: _search,
                hintText:
                    'Search corporations by name or chartered jurisdiction...',
                onChanged: (_) => _load(),
                onClear: _load,
              ),
            ),
            const SizedBox(width: 10),
            EarthButton(
              label: '+ FOUND CORPORATION',
              icon: Icons.add_business_outlined,
              onPressed: _isMember || widget.busy
                  ? null
                  : () =>
                      showCorporationWithCapitalDialog(context, widget.action),
            ),
          ],
        ),
        SizedBox(height: context.spacingTitleOffset),
        if (_loading)
          Center(child: CircularProgressIndicator(color: context.primaryColor))
        else if (_corporations.isEmpty)
          const EarthEmptyState(
            message:
                'No corporations found matching your search. You can found a new one from your capital city.',
            icon: Icons.domain_disabled_outlined,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _corporations.map((row) {
              final id = row['id']?.toString() ?? '';
              final corporationName = row['name']?.toString() ?? id;
              final isAffiliated = id == currentCorpId;
              final isSelected = widget.showSelection && _selected?['id'] == id;
              final isExpanded = _expandedId == id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  button: true,
                  expanded: isExpanded,
                  label: 'Show corporation $corporationName details',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    onTap: () {
                    setState(() {
                      _selected = row;
                      if (widget.isExpandable) {
                        _expandedId = _expandedId == id ? null : id;
                      }
                    });
                    widget.onSelectCorporation?.call(row);
                  },
                    child: _buildCorporationNodeCard(
                      context,
                      row,
                      isExpanded,
                      isSelected,
                      isAffiliated,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class CivicRankingsPanel extends StatefulWidget {
  final EarthState state;
  const CivicRankingsPanel({super.key, required this.state});

  @override
  State<CivicRankingsPanel> createState() => _CivicRankingsPanelState();
}

class _CivicRankingsPanelState extends State<CivicRankingsPanel> {
  int _singleTab = 0; // 0: Citizens, 1: Houses, 2: Corps, 3: Cities
  int _leftTab = 0; // 0: Citizens, 1: Houses
  int _rightTab = 0; // 0: Corps, 1: Cities
  int _citizenPage = 0;
  int _housePage = 0;
  int _corpPage = 0;
  int _cityPage = 0;
  bool _initializedPages = false;

  void _initPagesOnce({
    required List<Map<String, dynamic>> corp,
    required List<Map<String, dynamic>> cities,
    required List<Map<String, dynamic>> citizens,
    required List<Map<String, dynamic>> houses,
    required String? myCorpId,
    required String? myCityId,
    required String? myHumanId,
    required String? myHouseName,
  }) {
    if (_initializedPages) return;
    _initializedPages = true;

    if (myHumanId != null && myHumanId.isNotEmpty) {
      final idx = citizens.indexWhere((r) =>
          (r['id']?.toString() ?? r['human_id']?.toString()) == myHumanId);
      if (idx != -1) _citizenPage = idx ~/ 10;
    }
    if (myHouseName != null && myHouseName.isNotEmpty) {
      final idx = houses.indexWhere((r) =>
          (r['house_name']?.toString() ??
              r['dynasty_name']?.toString() ??
              r['name']?.toString()) ==
          myHouseName);
      if (idx != -1) _housePage = idx ~/ 10;
    }
    if (myCorpId != null && myCorpId.isNotEmpty) {
      final idx = corp.indexWhere((r) =>
          (r['id']?.toString() ?? r['corporation_id']?.toString()) == myCorpId);
      if (idx != -1) _corpPage = idx ~/ 10;
    }
    if (myCityId != null && myCityId.isNotEmpty) {
      final idx = cities.indexWhere(
          (r) => (r['id']?.toString() ?? r['city_id']?.toString()) == myCityId);
      if (idx != -1) _cityPage = idx ~/ 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final citizens = _citizenRows(
          widget.state.rankings['citizens'],
          widget.state.rankings['humans'],
          widget.state.rankings['wealth'],
          widget.state.json['cityMembers'] ?? widget.state.json['workforce'],
          widget.state.human,
        );
        final houses = _houseRows(
          widget.state.rankings['houses'] ??
              widget.state.rankings['dynasties'] ??
              widget.state.rankings['dynasticHouses'] ??
              widget.state.json['houses'] ??
              widget.state.json['dynasties'] ??
              widget.state.life['house'] ??
              widget.state.life['dynasty'] ??
              widget.state.life['dynasties'],
          citizens,
          widget.state.human,
          (widget.state.life['house'] is Map
              ? Map<String, dynamic>.from(widget.state.life['house'] as Map)
              : (widget.state.life['dynasty'] is Map
                  ? Map<String, dynamic>.from(
                      widget.state.life['dynasty'] as Map)
                  : null)),
        );
        final corp = _rows(widget.state.rankings['corporations']);
        final cities = _rows(widget.state.rankings['cities']);
        final wide = constraints.maxWidth >= 840;

        final myHumanId = widget.state.human['id']?.toString() ??
            widget.state.membership?['human_id']?.toString();
        final myCityId = widget.state.membership?['city_id']?.toString() ??
            widget.state.institutions['city']?['id']?.toString() ??
            widget.state.human['city_id']?.toString();
        final myCorpId =
            widget.state.membership?['corporation_id']?.toString() ??
                widget.state.institutions['corporation']?['id']?.toString() ??
                widget.state.human['corporation_id']?.toString();
        final myHouseName = widget.state.human['house_name']?.toString() ??
            widget.state.human['houseName']?.toString() ??
            widget.state.human['dynasty_name']?.toString() ??
            widget.state.human['dynastyName']?.toString();

        _initPagesOnce(
          corp: corp,
          cities: cities,
          citizens: citizens,
          houses: houses,
          myCorpId: myCorpId,
          myCityId: myCityId,
          myHumanId: myHumanId,
          myHouseName: myHouseName,
        );

        final corpNames = <String, String>{};
        for (final c in corp) {
          final id = c['id']?.toString();
          final name = c['name']?.toString();
          if (id != null && name != null && name.isNotEmpty) {
            corpNames[id] = name;
          }
        }

        final cityNames = <String, String>{};
        final cityToCorpMap = <String, String>{};
        for (final c in cities) {
          final id = c['id']?.toString();
          final name = c['name']?.toString();
          if (id != null && name != null && name.isNotEmpty) {
            cityNames[id] = name;
          }
          final corpId =
              c['corporation_id']?.toString() ?? c['corporationId']?.toString();
          final rawCorpName = c['corporation_name']?.toString() ??
              c['corporationName']?.toString() ??
              c['affiliation']?.toString();
          if (id != null) {
            if (rawCorpName != null &&
                rawCorpName.isNotEmpty &&
                rawCorpName != 'Independent') {
              cityToCorpMap[id] = corpNames.containsKey(rawCorpName)
                  ? corpNames[rawCorpName]!
                  : rawCorpName;
            } else if (corpId != null && corpNames.containsKey(corpId)) {
              cityToCorpMap[id] = corpNames[corpId]!;
            }
          }
        }

        final colCitizens = _rankingColumn(
          context,
          'CITIZENS',
          citizens,
          Icons.person_outline,
          'credits',
          page: _citizenPage,
          onPageChanged: (p) => setState(() => _citizenPage = p),
          corpNames: corpNames,
          cityNames: cityNames,
          cityToCorpMap: cityToCorpMap,
          myAffiliationId: myHumanId,
          formulaInfo:
              'Citizen Ranking Index (0–100):\n\n• 1. Personal Legacy: 45%\n  Lifetime achievements & personal milestones.\n\n• 2. Civic Standing: 35%\n  Governance reputation & civic participation.\n\n• 3. Personal Capitalization: 20%\n  Liquid credit holdings & physical asset net worth.\n\nNote: Each metric is scaled dynamically (0.0 to 1.0) against the highest live value in the world economy.\n\nPrestige Tiers:\n👑 Sovereign: 90–100 (Apex Leaders)\n🏛️ Patrician: 75–89 (Elite Citizens)\n🚀 Pioneer: 50–74 (Established Citizens)\n👤 Citizen: 0–49 (General Population)\n\n2nd Line: Leg · Std · Cap (Personal Legacy · Standing · Capitalization).\n\n3rd Line: Corporation · City (or Independent).',
        );

        final colHouses = _rankingColumn(
          context,
          'HOUSES',
          houses,
          Icons.shield_outlined,
          'generation',
          page: _housePage,
          onPageChanged: (p) => setState(() => _housePage = p),
          corpNames: corpNames,
          cityNames: cityNames,
          cityToCorpMap: cityToCorpMap,
          myAffiliationId: myHouseName,
          formulaInfo:
              'The House Prestige Score records the generational prominence and active survival of a noble house across Earth\'s history based on a 1 : 5 : 25 weighting ratio:\n\n• House Legacy (25x relative weight / 50 pts per LP):\n  Cumulative milestones and achievements earned across all generations.\n\n• House Standing (5x relative weight / 10 pts per pt):\n  Accumulated civic reputation and governance trust.\n\n• Ancestral Inscriptions (10x bonus / 20 pts per Ancestor):\n  Total passed ancestors permanently recorded.\n\n• House Lifespan (1x base weight / 2 pts per Year):\n  Total full years the house has existed on Earth.\n\nRelative Ratio: 1 Legacy Pt = 5 House Standing Pts = 25 Lifespan Years.\n\n2nd Line: Leg · Std · Gen (House Legacy · Standing · Generation).\n\n3rd Line: Founder · Heir.',
        );

        final colCorps = _rankingColumn(
          context,
          'CORPORATIONS',
          corp,
          Icons.account_balance_outlined,
          'members',
          page: _corpPage,
          onPageChanged: (p) => setState(() => _corpPage = p),
          allCities: cities,
          corpNames: corpNames,
          cityNames: cityNames,
          cityToCorpMap: cityToCorpMap,
          myAffiliationId: myCorpId,
          formulaInfo:
              'Corporation Ranking Index (0–100):\n\n• 1. Total Enterprise Capitalization: 45%\n  Corporate treasury + sum of constituent city valuations.\n\n• 2. Productive Ecosystem: 30%\n  Active businesses operating across constituent cities.\n\n• 3. Municipal Excellence: 15%\n  Average ranking score across constituent cities.\n\n• 4. Total Population: 10%\n  Aggregated workforce and residents.\n\nNote: Each metric is scaled dynamically (0.0 to 1.0) against the highest live value in the world economy.\n\n2nd Line: Cap · Biz · Res (Capitalization · Businesses · Population).',
        );

        final colCities = _rankingColumn(
          context,
          'CITIES',
          cities,
          Icons.location_city_outlined,
          'residents',
          page: _cityPage,
          onPageChanged: (p) => setState(() => _cityPage = p),
          corpNames: corpNames,
          cityNames: cityNames,
          cityToCorpMap: cityToCorpMap,
          myAffiliationId: myCityId,
          formulaInfo:
              'City Ranking Index (0–100):\n\n• 1. City Capitalization: 35%\n  Municipal treasury + real estate & infrastructure equity.\n\n• 2. Infrastructure Coverage: 35%\n  Housing, energy, connectivity & health vs population.\n\n• 3. Commercial Vitality: 20%\n  Active local operating businesses.\n\n• 4. Demographic Population: 10%\n  Settled active residents.\n\nNote: Each metric is scaled dynamically (0.0 to 1.0) against the highest live value in the world economy.\n\n2nd Line: Cap · Biz · Res (Capitalization · Businesses · Residents).\n\n3rd Line: Affiliated Corporation.',
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Column 1: Sovereign & Lineage Sphere (Citizens / Dynasties)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      margin: EdgeInsets.only(bottom: context.spacingControl),
                      decoration: BoxDecoration(
                        color: surfaceColor.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildNarrowTabButton(
                              context,
                              title: 'CITIZENS',
                              icon: Icons.person_outline,
                              count: citizens.length,
                              isSelected: _leftTab == 0,
                              onTap: () => setState(() => _leftTab = 0),
                            ),
                          ),
                          Expanded(
                            child: _buildNarrowTabButton(
                              context,
                              title: 'HOUSES',
                              icon: Icons.shield_outlined,
                              count: houses.length,
                              isSelected: _leftTab == 1,
                              onTap: () => setState(() => _leftTab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _leftTab == 0 ? colCitizens : colHouses,
                  ],
                ),
              ),
              const SizedBox(width: 40),
              // Column 2: Institutional & Municipal Sphere (Corps / Cities)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      margin: EdgeInsets.only(bottom: context.spacingControl),
                      decoration: BoxDecoration(
                        color: surfaceColor.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildNarrowTabButton(
                              context,
                              title: 'CORPS',
                              icon: Icons.account_balance_outlined,
                              count: corp.length,
                              isSelected: _rightTab == 0,
                              onTap: () => setState(() => _rightTab = 0),
                            ),
                          ),
                          Expanded(
                            child: _buildNarrowTabButton(
                              context,
                              title: 'CITIES',
                              icon: Icons.location_city_outlined,
                              count: cities.length,
                              isSelected: _rightTab == 1,
                              onTap: () => setState(() => _rightTab = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _rightTab == 0 ? colCorps : colCities,
                  ],
                ),
              ),
            ],
          );
        }

        // 1 Column Mode: 4 Tabs (Citizens -> Houses -> Corps -> Cities)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: EdgeInsets.only(bottom: context.spacingControl),
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'CITIZENS',
                      icon: Icons.person_outline,
                      count: citizens.length,
                      isSelected: _singleTab == 0,
                      onTap: () => setState(() => _singleTab = 0),
                    ),
                  ),
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'HOUSES',
                      icon: Icons.shield_outlined,
                      count: houses.length,
                      isSelected: _singleTab == 1,
                      onTap: () => setState(() => _singleTab = 1),
                    ),
                  ),
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'CORPS',
                      icon: Icons.account_balance_outlined,
                      count: corp.length,
                      isSelected: _singleTab == 2,
                      onTap: () => setState(() => _singleTab = 2),
                    ),
                  ),
                  Expanded(
                    child: _buildNarrowTabButton(
                      context,
                      title: 'CITIES',
                      icon: Icons.location_city_outlined,
                      count: cities.length,
                      isSelected: _singleTab == 3,
                      onTap: () => setState(() => _singleTab = 3),
                    ),
                  ),
                ],
              ),
            ),
            _singleTab == 0
                ? colCitizens
                : (_singleTab == 1
                    ? colHouses
                    : (_singleTab == 2 ? colCorps : colCities)),
          ],
        );
      },
    );
  }

  Widget _buildNarrowTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Show $title rankings',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: .15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: context.primaryColor.withValues(alpha: .4))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? context.primaryColor : context.mutedColor,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$title ($count)',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.white : context.mutedColor,
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : const [];

  List<Map<String, dynamic>> _citizenRows(
    dynamic citizensVal,
    dynamic humansVal,
    dynamic wealthVal,
    dynamic cityMembersVal,
    dynamic myHumanVal,
  ) {
    if (citizensVal is List && citizensVal.isNotEmpty) {
      return citizensVal
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (humansVal is List && humansVal.isNotEmpty) {
      return humansVal
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (cityMembersVal is List && cityMembersVal.isNotEmpty) {
      return cityMembersVal
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (wealthVal is List && wealthVal.isNotEmpty) {
      return wealthVal.whereType<Map>().map((row) {
        final r = Map<String, dynamic>.from(row);
        final id =
            r['human_id']?.toString() ?? r['id']?.toString() ?? 'Citizen';
        final credits = asIntOr(r['balance'], 0);
        return {
          'id': id,
          'displayName': r['displayName'] ?? id,
          'credits': credits,
          'standing': 100,
          'legacy': 0,
          'compositeScore': credits,
        };
      }).toList();
    }
    if (myHumanVal is Map && myHumanVal.isNotEmpty) {
      final r = Map<String, dynamic>.from(myHumanVal);
      final id = r['id']?.toString() ?? 'H-0001';
      final name = r['displayName'] ?? r['name'] ?? 'Citizen';
      final creds = asIntOr(r['credits'], 0);
      final standing = asIntOr(r['standing'], 100);
      final legacy = asIntOr(r['legacy'], 0);
      return [
        {
          'id': id,
          'displayName': name,
          'credits': creds,
          'standing': standing,
          'legacy': legacy,
          'compositeScore': (standing * 2) + (legacy * 3) + (creds ~/ 100),
        }
      ];
    }
    return const [];
  }

  List<Map<String, dynamic>> _houseRows(
    dynamic rawHouses, [
    List<Map<String, dynamic>>? citizens,
    Map<String, dynamic>? myHuman,
    Map<String, dynamic>? myHouse,
  ]) {
    final list = _rows(rawHouses);
    var active = list.where((d) {
      final isExtinct = d['is_extinct'] == true ||
          d['status'] == 'extinct' ||
          d['status'] == 'deceased' ||
          d['status'] == 'historical';
      return !isExtinct;
    }).toList();

    if (active.isEmpty && citizens != null && citizens.isNotEmpty) {
      final map = <String, Map<String, dynamic>>{};
      for (final c in citizens) {
        final dName = c['houseName']?.toString() ??
            c['house_name']?.toString() ??
            c['dynastyName']?.toString() ??
            c['dynasty_name']?.toString();
        if (dName != null &&
            dName.isNotEmpty &&
            dName != '—' &&
            dName != 'None') {
          final citizenName =
              c['displayName']?.toString() ?? c['name']?.toString() ?? 'Heir';
          final leg = asIntOr(c['legacy'], 0);
          final std = asIntOr(c['standing'], 0);
          if (!map.containsKey(dName)) {
            map[dName] = {
              'house_name': dName,
              'dynasty_name': dName,
              'founder_name': citizenName,
              'active_heir': citizenName,
              'generation': 1,
              'deceased_count': 0,
              'total_legacy': leg,
              'peak_standing': std,
              'house_score': leg * 50 + std * 10,
              'dynasty_score': leg * 50 + std * 10,
            };
          } else {
            final entry = map[dName]!;
            entry['total_legacy'] = (entry['total_legacy'] as int) + leg;
            entry['peak_standing'] =
                math.max(entry['peak_standing'] as int, std);
            entry['house_score'] = (entry['total_legacy'] as int) * 50 +
                (entry['peak_standing'] as int) * 10;
            entry['dynasty_score'] = entry['house_score'];
          }
        }
      }
      if (map.isNotEmpty) {
        active = map.values.toList();
      }
    }

    if (active.isEmpty) {
      active = [
        {
          'house_name': 'House of Vance',
          'dynasty_name': 'House of Vance',
          'founder_name': 'Marcus Vance',
          'active_heir': 'Amara Vance',
          'generation': 3,
          'deceased_count': 3,
          'total_legacy': 5400,
          'peak_standing': 980,
          'house_score': 28450,
          'dynasty_score': 28450,
        },
        {
          'house_name': 'House of Noha',
          'dynasty_name': 'House of Noha',
          'founder_name': 'Vitalii Noha',
          'active_heir': 'Vitalii Noha',
          'generation': 3,
          'deceased_count': 2,
          'total_legacy': 4600,
          'peak_standing': 920,
          'house_score': 24200,
          'dynasty_score': 24200,
        },
        {
          'house_name': 'House of Rostov',
          'dynasty_name': 'House of Rostov',
          'founder_name': 'Viktor Rostov',
          'active_heir': 'Dmitri Rostov',
          'generation': 2,
          'deceased_count': 2,
          'total_legacy': 3800,
          'peak_standing': 860,
          'house_score': 19800,
          'dynasty_score': 19800,
        },
        {
          'house_name': 'House of Thorne',
          'dynasty_name': 'House of Thorne',
          'founder_name': 'Silas Thorne',
          'active_heir': 'Kaelen Thorne',
          'generation': 2,
          'deceased_count': 1,
          'total_legacy': 2900,
          'peak_standing': 720,
          'house_score': 15400,
          'dynasty_score': 15400,
        },
        {
          'house_name': 'House of Chen',
          'dynasty_name': 'House of Chen',
          'founder_name': 'Wei Chen',
          'active_heir': 'Sariyah Chen',
          'generation': 1,
          'deceased_count': 0,
          'total_legacy': 1600,
          'peak_standing': 540,
          'house_score': 8600,
          'dynasty_score': 8600,
        },
        {
          'house_name': 'House of Mansoor',
          'dynasty_name': 'House of Mansoor',
          'founder_name': 'Rashid Al-Mansoor',
          'active_heir': 'Tarek Al-Mansoor',
          'generation': 1,
          'deceased_count': 0,
          'total_legacy': 1200,
          'peak_standing': 480,
          'house_score': 6500,
          'dynasty_score': 6500,
        },
      ];
    }

    // Inject player's own active house if defined and not already in the leaderboard
    final playerHouseName = myHuman?['house_name']?.toString() ??
        myHuman?['houseName']?.toString() ??
        myHuman?['dynasty_name']?.toString() ??
        myHuman?['dynastyName']?.toString() ??
        myHouse?['house_name']?.toString() ??
        myHouse?['dynasty_name']?.toString();
    if (playerHouseName != null &&
        playerHouseName.isNotEmpty &&
        playerHouseName != '—' &&
        playerHouseName != 'None') {
      final exists = active.any((d) =>
          (d['house_name']?.toString() ??
                  d['dynasty_name']?.toString() ??
                  d['name']?.toString())
              ?.toLowerCase() ==
          playerHouseName.toLowerCase());
      if (!exists) {
        final playerName = myHuman?['displayName']?.toString() ??
            myHuman?['display_name']?.toString() ??
            myHuman?['name']?.toString() ??
            'Vitalii Noha';
        final leg = asIntOr(myHuman?['legacy'], 0) +
            asIntOr(myHouse?['legacy_points'], 0);
        final std = asIntOr(myHuman?['standing'], 100);
        active.add({
          'house_name': playerHouseName,
          'dynasty_name': playerHouseName,
          'founder_name': myHouse?['founder_name']?.toString() ?? playerName,
          'active_heir': playerName,
          'generation': asIntOr(myHouse?['generation'], 1),
          'deceased_count': asIntOr(myHouse?['deceased_count'], 0),
          'total_legacy': leg,
          'peak_standing': std,
          'house_score': leg * 50 + std * 10,
          'dynasty_score': leg * 50 + std * 10,
        });
      }
    }

    return active;
  }

  Widget _rankingColumn(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> rows,
    IconData icon,
    String secondary, {
    int page = 0,
    required ValueChanged<int> onPageChanged,
    int pageSize = 10,
    List<Map<String, dynamic>>? allCities,
    Map<String, String>? corpNames,
    Map<String, String>? cityNames,
    Map<String, String>? cityToCorpMap,
    String? myAffiliationId,
    String? formulaInfo,
  }) {
    final isCitizen = title == 'CITIZENS';
    final isCity = title == 'CITIES';
    final isHouse = title == 'HOUSES' || title == 'DYNASTIES';

    int computeCityCap(Map<String, dynamic> c) {
      final treasury = asIntOr(c['treasury'], 0);
      final housing = asIntOr(c['housing_capacity'], 0);
      final energy = asIntOr(c['energy_capacity'], 0);
      final connectivity = asIntOr(c['connectivity_capacity'], 0);
      final health = asIntOr(c['health_capacity'], 0);
      return asIntOr(c['capitalization'],
          treasury + (housing + energy + connectivity + health) * 25);
    }

    Map<String, dynamic> resolveCorpMetrics(Map<String, dynamic> corp) {
      final directTreasury = asIntOr(corp['treasury'], 0);
      final directMembers = asIntOr(corp['member_count'] ?? corp[secondary], 0);

      final corpId =
          corp['id']?.toString() ?? corp['corporation_id']?.toString();
      final corpName = corp['name']?.toString();

      final constituentCities = (allCities ?? []).where((c) {
        final cCorpId =
            c['corporation_id']?.toString() ?? c['corporationId']?.toString();
        final cCorpName = c['corporation_name']?.toString() ??
            c['corporationName']?.toString();
        final mappedCorp = cityToCorpMap?[c['id']?.toString()];
        return (corpId != null &&
                (cCorpId == corpId ||
                    mappedCorp == corpName ||
                    mappedCorp == corpId)) ||
            (corpName != null &&
                (cCorpName == corpName || mappedCorp == corpName));
      }).toList();

      final rolledUpCityCap =
          constituentCities.fold<int>(0, (sum, c) => sum + computeCityCap(c));
      final rolledUpCityBiz = constituentCities.fold<int>(
        0,
        (sum, c) =>
            sum +
            asIntOr(
                c['businesses_count'] ??
                    c['active_businesses'] ??
                    c['businesses'],
                0),
      );
      final rolledUpCityRes = constituentCities.fold<int>(
          0, (sum, c) => sum + asIntOr(c['residents'], 0));

      final totalCap = asIntOr(
          corp['capitalization'] ?? corp['totalCapitalization'],
          directTreasury + rolledUpCityCap);
      final totalBiz = asIntOr(
        corp['active_businesses'] ?? corp['businesses_count'],
        rolledUpCityBiz > 0 ? rolledUpCityBiz : asIntOr(corp['city_count'], 0),
      );
      final totalRes =
          asIntOr(corp['residents'], math.max(directMembers, rolledUpCityRes));

      return {
        'capitalization': totalCap,
        'businesses': totalBiz,
        'residents': totalRes,
      };
    }

    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: context.widgetTitleStyle),
              if (formulaInfo != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: formulaInfo,
                  child: Semantics(
                    button: true,
                    label: 'Show $title ranking formula',
                    child: InkWell(
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: EarthColors.panelSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.white12),
                          ),
                          title: Row(
                            children: [
                              Icon(icon, color: cyanAccentColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$title RANKING FORMULA',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xffeab308),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          content: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: SingleChildScrollView(
                              child: Text(
                                formulaInfo,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('GOT IT',
                                  style: TextStyle(color: cyanAccentColor)),
                            ),
                          ],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.info_outline,
                        size: context.iconSize,
                        color: context.mutedColor,
                      ),
                    ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: context.spacingControl),
          const EarthEmptyState(
            message: 'No ranking data available.',
            icon: Icons.leaderboard_outlined,
          ),
        ],
      );
    }

    int maxMem = 1, maxTr = 1, maxBz = 1;
    int maxLeg = 1, maxStd = 1, maxCreds = 1;
    int maxDynLeg = 1, maxDynStd = 1, maxDynGen = 1;
    double maxH = 1, maxE = 1, maxC = 1, maxHl = 100, maxCityTr = 1;

    for (final r in rows) {
      if (isCitizen) {
        maxLeg = math.max(maxLeg, asIntOr(r['legacy'], 0));
        maxStd = math.max(maxStd, asIntOr(r['standing'], 0));
        maxCreds = math.max(maxCreds, asIntOr(r['credits'] ?? r['balance'], 0));
      } else if (isCity) {
        final res = asIntOr(r['residents'], 1);
        final h = asIntOr(r['housing_capacity'], 0) / (res > 0 ? res : 1.0);
        final e = asIntOr(r['energy_capacity'], 0) / (res > 0 ? res : 1.0);
        final c =
            asIntOr(r['connectivity_capacity'], 0) / (res > 0 ? res : 1.0);
        final hl = asIntOr(r['health_capacity'], 0).toDouble();
        final tr = asIntOr(r['treasury'], 0).toDouble();
        if (h > maxH) maxH = h;
        if (e > maxE) maxE = e;
        if (c > maxC) maxC = c;
        if (hl > maxHl) maxHl = hl;
        if (tr > maxCityTr) maxCityTr = tr;
      } else if (isHouse) {
        final legacy = asIntOr(
            r['total_legacy'] ??
                r['house_legacy'] ??
                r['dynasty_legacy'] ??
                r['peak_legacy'] ??
                r['legacy'],
            0);
        final standing = asIntOr(
            r['house_standing'] ??
                r['dynastic_standing'] ??
                r['peak_standing'] ??
                r['standing'],
            0);
        final gen = asIntOr(r['generation'] ?? r['generations'] ?? r['gen'], 1);
        final ancestors = asIntOr(
            r['deceased_count'] ?? r['ancestors_count'] ?? r['ancestors'], 0);
        maxDynLeg = math.max(maxDynLeg, legacy);
        maxDynStd = math.max(maxDynStd, standing);
        maxDynGen = math.max(maxDynGen, gen * 2 + ancestors);
      } else {
        final metrics = resolveCorpMetrics(r);
        maxMem = math.max(maxMem, metrics['residents'] as int);
        maxTr = math.max(maxTr, metrics['capitalization'] as int);
        maxBz = math.max(maxBz, metrics['businesses'] as int);
      }
    }

    int computeScore(Map<String, dynamic> row) {
      if (row['final_score'] != null) return asIntOr(row['final_score'], 0);
      if (row['finalScore'] != null) return asIntOr(row['finalScore'], 0);
      if (row['compositeIndex'] != null)
        return asIntOr(row['compositeIndex'], 0);
      if (row['score'] != null && asIntOr(row['score'], 0) <= 100)
        return asIntOr(row['score'], 0);

      if (isCitizen) {
        final legacy = asIntOr(row['legacy'], 0);
        final standing = asIntOr(row['standing'], 0);
        final creds = asIntOr(row['credits'] ?? row['balance'], 0);
        final nLegacy = (legacy / maxLeg).clamp(0.0, 1.0);
        final nStanding = (standing / maxStd).clamp(0.0, 1.0);
        final nWealth = (creds / maxCreds).clamp(0.0, 1.0);
        return ((nLegacy * 45) + (nStanding * 35) + (nWealth * 20))
            .round()
            .clamp(0, 100);
      } else if (isCity) {
        if (row['qolIndex'] != null) return asIntOr(row['qolIndex'], 0);
        final residents = asIntOr(row['residents'], 1);
        final housing = asIntOr(row['housing_capacity'], 0);
        final energy = asIntOr(row['energy_capacity'], 0);
        final connectivity = asIntOr(row['connectivity_capacity'], 0);
        final health = asIntOr(row['health_capacity'], 0);
        final treasury = asIntOr(row['treasury'], 0);
        final nHousing = ((housing / (residents > 0 ? residents : 1.0)) / maxH)
            .clamp(0.0, 1.0);
        final nEnergy = ((energy / (residents > 0 ? residents : 1.0)) / maxE)
            .clamp(0.0, 1.0);
        final nConnectivity =
            ((connectivity / (residents > 0 ? residents : 1.0)) / maxC)
                .clamp(0.0, 1.0);
        final nHealth = (health / maxHl).clamp(0.0, 1.0);
        final nTreasury = (treasury / maxCityTr).clamp(0.0, 1.0);
        return ((nHousing * 25) +
                (nEnergy * 25) +
                (nConnectivity * 20) +
                (nHealth * 20) +
                (nTreasury * 10))
            .round()
            .clamp(0, 100);
      } else if (isHouse) {
        if (row['house_score'] != null) return asIntOr(row['house_score'], 0);
        if (row['dynasty_score'] != null)
          return asIntOr(row['dynasty_score'], 0);
        if (row['score'] != null) return asIntOr(row['score'], 0);
        final totalLegacy = (row['total_legacy'] ??
                row['house_legacy'] ??
                row['dynasty_legacy'] ??
                row['peak_legacy'] ??
                row['legacy_points'] ??
                row['legacy'] ??
                '0')
            .toString();
        final peakStanding = row['peak_standing'] ??
            row['standing'] ??
            row['house_standing'] ??
            row['dynastic_standing'] ??
            0;
        final count = (row['deceased_count'] ??
                row['ancestors_count'] ??
                row['deceased'] ??
                '0')
            .toString();
        final foundedRaw = row['founded_game_day'] ??
            row['birth_game_day'] ??
            row['founded_day'] ??
            row['start_day'] ??
            1;
        final foundedDayNum = int.tryParse(foundedRaw.toString()) ?? 1;
        final currentDayRaw = row['current_game_day'] ??
            row['game_day'] ??
            widget.state.clock['day'];
        final currentDayNum = int.tryParse(currentDayRaw.toString()) ?? 1200;
        final totalDays = (currentDayNum - foundedDayNum).clamp(0, 9999999);
        final ageY = totalDays ~/ 365;

        final legacyNum = int.tryParse(totalLegacy) ?? 0;
        final standingNum = int.tryParse(peakStanding.toString()) ?? 0;
        final ancestorsNum = int.tryParse(count) ?? 0;
        return (legacyNum * 50 +
            standingNum * 10 +
            ageY * 2 +
            ancestorsNum * 20);
      } else {
        final metrics = resolveCorpMetrics(row);
        final totalRes = metrics['residents'] as int;
        final totalCap = metrics['capitalization'] as int;
        final totalBiz = metrics['businesses'] as int;
        final nMembers = (totalRes / maxMem).clamp(0.0, 1.0);
        final nTreasury = (totalCap / maxTr).clamp(0.0, 1.0);
        final nBusinesses = (totalBiz / maxBz).clamp(0.0, 1.0);
        return ((nTreasury * 45) + (nBusinesses * 30) + (nMembers * 25))
            .round()
            .clamp(0, 100);
      }
    }

    final sortedRows = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => computeScore(b).compareTo(computeScore(a)));

    int myRankIndex = -1;
    if (myAffiliationId != null && myAffiliationId.isNotEmpty) {
      for (int i = 0; i < sortedRows.length; i++) {
        final r = sortedRows[i];
        final eid = r['id']?.toString() ??
            r['human_id']?.toString() ??
            r['city_id']?.toString() ??
            r['corporation_id']?.toString() ??
            r['dynasty_name']?.toString() ??
            r['name']?.toString();
        if (eid == myAffiliationId) {
          myRankIndex = i;
          break;
        }
      }
    }

    final totalPages = math.max(1, (sortedRows.length / pageSize).ceil());
    final safePage = page.clamp(0, totalPages - 1);
    final pagedEntries = sortedRows
        .asMap()
        .entries
        .skip(safePage * pageSize)
        .take(pageSize)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: context.widgetTitleStyle),
            if (formulaInfo != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: formulaInfo,
                child: Semantics(
                  button: true,
                  label: 'Show $title ranking formula',
                  child: InkWell(
                  onTap: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: EarthColors.panelSurface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.white12),
                        ),
                        title: Row(
                          children: [
                            Icon(icon, color: cyanAccentColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$title RANKING FORMULA',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xffeab308),
                                ),
                              ),
                            ),
                          ],
                        ),
                        content: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: SingleChildScrollView(
                            child: Text(
                              formulaInfo,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('GOT IT',
                                style: TextStyle(color: cyanAccentColor)),
                          ),
                        ],
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.info_outline,
                      size: context.iconSize,
                      color: context.mutedColor,
                    ),
                  ),
                ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: context.spacingControl),
        EarthDataList(
          children: pagedEntries.map((entry) {
            final idx = entry.key + 1;
            final row = entry.value;
            final rawName = isCitizen
                ? (row['displayName']?.toString() ??
                    row['display_name']?.toString() ??
                    row['human_id']?.toString() ??
                    row['id']?.toString())
                : (isHouse
                    ? (row['house_name']?.toString() ??
                        row['dynasty_name']?.toString() ??
                        row['name']?.toString() ??
                        'House')
                    : row['name']?.toString());
            final entityId = row['id']?.toString() ??
                row['human_id']?.toString() ??
                row['city_id']?.toString() ??
                row['corporation_id']?.toString() ??
                row['house_name']?.toString() ??
                row['dynasty_name']?.toString();

            final name = (rawName != null && rawName.isNotEmpty)
                ? rawName
                : ((!isCity &&
                        !isCitizen &&
                        !isHouse &&
                        corpNames != null &&
                        corpNames.containsKey(entityId))
                    ? corpNames[entityId]!
                    : (entityId ?? 'Entity'));

            final String subtitle;
            final String? secondarySubtitle;
            final int indexScore = computeScore(row);

            String formatCompact(num val) {
              final n = val.abs();
              if (n >= 1000000000) {
                final v = (val / 1000000000).toStringAsFixed(1);
                return '${v.endsWith(".0") ? v.substring(0, v.length - 2) : v}B';
              }
              if (n >= 1000000) {
                final v = (val / 1000000).toStringAsFixed(1);
                return '${v.endsWith(".0") ? v.substring(0, v.length - 2) : v}M';
              }
              if (n >= 1000) {
                final v = (val / 1000).toStringAsFixed(1);
                return '${v.endsWith(".0") ? v.substring(0, v.length - 2) : v}k';
              }
              return val.round().toString();
            }

            if (row['metrics_line'] != null &&
                row['metrics_line'].toString().isNotEmpty) {
              subtitle = row['metrics_line'].toString();
            } else if (row['metricsLine'] != null &&
                row['metricsLine'].toString().isNotEmpty) {
              subtitle = row['metricsLine'].toString();
            } else if (isCitizen) {
              final legacy = asIntOr(row['legacy'], 0);
              final standing = asIntOr(row['standing'], 0);
              final creds = asIntOr(row['credits'] ?? row['balance'], 0);
              subtitle =
                  '$legacy Leg · $standing Std · ${formatCompact(creds)} Cap';
            } else if (isCity) {
              final residents = asIntOr(row['residents'], 1);
              final treasury = asIntOr(row['treasury'], 0);
              final housing = asIntOr(row['housing_capacity'], 0);
              final energy = asIntOr(row['energy_capacity'], 0);
              final connectivity = asIntOr(row['connectivity_capacity'], 0);
              final health = asIntOr(row['health_capacity'], 0);
              final capitalization = asIntOr(row['capitalization'],
                  treasury + (housing + energy + connectivity + health) * 25);
              final businesses = asIntOr(
                  row['businesses_count'] ??
                      row['active_businesses'] ??
                      row['businesses'],
                  0);
              subtitle =
                  '${formatCompact(capitalization)} Cap · $businesses Biz · $residents Res';
            } else if (isHouse) {
              final legacy = asIntOr(
                  row['total_legacy'] ??
                      row['house_legacy'] ??
                      row['dynasty_legacy'] ??
                      row['peak_legacy'] ??
                      row['legacy'],
                  0);
              final standing = asIntOr(
                  row['house_standing'] ??
                      row['dynastic_standing'] ??
                      row['peak_standing'] ??
                      row['standing'],
                  0);
              final gen = asIntOr(
                  row['generation'] ?? row['generations'] ?? row['gen'], 1);
              subtitle =
                  '${formatCompact(legacy)} Leg · $standing Std · Gen $gen';
            } else {
              final metrics = resolveCorpMetrics(row);
              final totalCap = metrics['capitalization'] as int;
              final totalBiz = metrics['businesses'] as int;
              final totalRes = metrics['residents'] as int;
              subtitle =
                  '${formatCompact(totalCap)} Cap · $totalBiz Biz · $totalRes Res';
            }

            if (isCitizen) {
              if (row['affiliation'] != null &&
                  row['affiliation'].toString().isNotEmpty &&
                  row['affiliation'].toString() != 'Independent') {
                secondarySubtitle = row['affiliation'].toString();
              } else {
                final rawCity =
                    row['cityId']?.toString() ?? row['city_id']?.toString();
                final cityName = (rawCity != null &&
                        cityNames != null &&
                        cityNames.containsKey(rawCity))
                    ? cityNames[rawCity]
                    : rawCity;

                final rawCorp = row['corporation_name']?.toString() ??
                    row['corporationName']?.toString() ??
                    row['corporationId']?.toString() ??
                    row['corporation_id']?.toString() ??
                    (rawCity != null && cityToCorpMap != null
                        ? cityToCorpMap[rawCity]
                        : null);

                final corpName = (rawCorp != null &&
                        corpNames != null &&
                        corpNames.containsKey(rawCorp))
                    ? corpNames[rawCorp]
                    : rawCorp;

                final affParts = <String>[];
                if (corpName != null &&
                    corpName.isNotEmpty &&
                    corpName != 'Independent') {
                  affParts.add(corpName);
                }
                if (cityName != null &&
                    cityName.isNotEmpty &&
                    cityName != 'Independent') {
                  affParts.add(cityName);
                }
                secondarySubtitle =
                    affParts.isNotEmpty ? affParts.join(' · ') : 'Independent';
              }
            } else if (isCity) {
              if (row['affiliation'] != null &&
                  row['affiliation'].toString().isNotEmpty &&
                  row['affiliation'].toString() != 'Independent') {
                secondarySubtitle = row['affiliation'].toString();
              } else {
                final rawCorp = row['corporation_name']?.toString() ??
                    row['corporationName']?.toString() ??
                    row['corporation_id']?.toString();
                final corpName = (rawCorp != null &&
                        corpNames != null &&
                        corpNames.containsKey(rawCorp))
                    ? corpNames[rawCorp]
                    : (rawCorp != null
                        ? rawCorp
                        : (entityId != null && cityToCorpMap != null
                            ? cityToCorpMap[entityId]
                            : null));
                secondarySubtitle = (corpName != null && corpName.isNotEmpty)
                    ? corpName
                    : 'Independent';
              }
            } else if (isHouse) {
              final founder =
                  row['founder_name']?.toString() ?? row['founder']?.toString();
              final heir =
                  row['active_heir']?.toString() ?? row['heir']?.toString();
              final affParts = <String>[];
              if (founder != null && founder.isNotEmpty && founder != '—')
                affParts.add('Founder: $founder');
              if (heir != null && heir.isNotEmpty && heir != '—')
                affParts.add('Heir: $heir');
              secondarySubtitle =
                  affParts.isNotEmpty ? affParts.join(' · ') : null;
            } else {
              secondarySubtitle = null;
            }

            final isMyAffiliation = myAffiliationId != null &&
                entityId != null &&
                (entityId == myAffiliationId);

            return EarthDataRow(
              title: name,
              subtitle: subtitle,
              secondarySubtitle: secondarySubtitle,
              isHighlight: isMyAffiliation,
              onTap: isHouse
                  ? () => showHouseLineageDialog(
                        context,
                        house: row,
                        state: widget.state,
                      )
                  : null,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '#$idx',
                      style: context.widgetTitleStyle.copyWith(
                        color: isMyAffiliation
                            ? context.primaryColor
                            : context.mutedColor,
                      ),
                    ),
                  ),
                  Icon(
                    icon,
                    size: context.iconSize,
                    color: isMyAffiliation
                        ? context.primaryColor
                        : context.mutedColor,
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$indexScore',
                    style: context.widgetTitleStyle.copyWith(
                      color: isMyAffiliation
                          ? context.primaryColor
                          : context.mutedColor,
                    ),
                  ),
                  if (isHouse) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.account_tree_outlined,
                      size: 14,
                      color: isMyAffiliation
                          ? context.primaryColor
                          : context.mutedColor,
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
        if (totalPages > 1) ...[
          SizedBox(height: context.spacingControl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 32),
                    icon: const Icon(Icons.first_page, size: 20),
                    onPressed: safePage > 0 ? () => onPageChanged(0) : null,
                    tooltip: 'First Page',
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 32),
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed:
                        safePage > 0 ? () => onPageChanged(safePage - 1) : null,
                    tooltip: 'Previous Page',
                  ),
                ],
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Page ',
                        style:
                            TextStyle(fontSize: 12, color: context.mutedColor),
                      ),
                      _PageNumberInput(
                        currentPage: safePage + 1,
                        totalPages: totalPages,
                        onSubmitted: (newPage1Indexed) {
                          onPageChanged(
                              (newPage1Indexed - 1).clamp(0, totalPages - 1));
                        },
                      ),
                      Text(
                        ' of $totalPages (${sortedRows.length})',
                        style:
                            TextStyle(fontSize: 12, color: context.mutedColor),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 32),
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: safePage < totalPages - 1
                        ? () => onPageChanged(safePage + 1)
                        : null,
                    tooltip: 'Next Page',
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 32),
                    icon: const Icon(Icons.last_page, size: 20),
                    onPressed: safePage < totalPages - 1
                        ? () => onPageChanged(totalPages - 1)
                        : null,
                    tooltip: 'Last Page',
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PageNumberInput extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onSubmitted;

  const _PageNumberInput({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onSubmitted,
  });

  @override
  State<_PageNumberInput> createState() => _PageNumberInputState();
}

class _PageNumberInputState extends State<_PageNumberInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _submit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _PageNumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage != widget.currentPage && !_focusNode.hasFocus) {
      _controller.text = widget.currentPage.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed != null && parsed >= 1 && parsed <= widget.totalPages) {
      widget.onSubmitted(parsed);
    } else {
      _controller.text = widget.currentPage.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      alignment: Alignment.center,
      child: Semantics(
        textField: true,
        label: 'Page number',
        child: TextField(
          controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
          onSubmitted: (_) => _submit(),
        ),
      ),
    );
  }
}

class CorporationHubPanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CorporationHubPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  State<CorporationHubPanel> createState() => _CorporationHubPanelState();
}

class _CorporationHubPanelState extends State<CorporationHubPanel> {
  Map<String, dynamic>? _selectedCorporation;

  @override
  Widget build(BuildContext context) {
    final membership = widget.state.membership ?? const <String, dynamic>{};
    final currentCorpId = membership['corporation_id']?.toString();
    final isMember = currentCorpId != null && currentCorpId.isNotEmpty;

    final fallbackCorps = widget.state.rankings['corporations'] is List
        ? (widget.state.rankings['corporations'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
        : <Map<String, dynamic>>[];

    final defaultCorp = _selectedCorporation ??
        (isMember
            ? (widget.state.institutions['corporation'] is Map
                ? Map<String, dynamic>.from(
                    widget.state.institutions['corporation'] as Map)
                : null)
            : (fallbackCorps.isNotEmpty ? fallbackCorps.first : null));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Corporations use a single reading flow at every viewport width.
        const isWide = false;

        final directory = CorporationDirectoryPanel(
          state: widget.state,
          busy: widget.busy,
          action: widget.action,
          isExpandable: !isWide,
          showMemberSummary: false,
          selectedCorporationId:
              defaultCorp?['id']?.toString() ?? currentCorpId,
          onSelectCorporation: (corp) {
            setState(() {
              _selectedCorporation = corp;
            });
          },
        );

        final overview = CorporationOverviewPanel(
          state: widget.state,
          busy: widget.busy,
          action: widget.action,
          selectedCorporation: defaultCorp,
        );

        final proposalsAndRoles = [
          if (isMember && currentCorpId != null) ...[
            const SizedBox(height: 34),
            ProposalPanel(
              state: widget.state,
              busy: widget.busy,
              action: widget.action,
              institutionId: currentCorpId,
              scopeLabel: 'CORPORATION',
            ),
            const SizedBox(height: 34),
            RolesPanel(
              state: widget.state,
              busy: widget.busy,
              action: widget.action,
              institutionId: currentCorpId,
            ),
          ],
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    directory,
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    overview,
                    ...proposalsAndRoles,
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            directory,
            const SizedBox(height: 34),
            overview,
            ...proposalsAndRoles,
          ],
        );
      },
    );
  }
}

class CorporationOverviewPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function())? action;
  final Map<String, dynamic>? selectedCorporation;

  const CorporationOverviewPanel({
    super.key,
    required this.state,
    this.busy = false,
    this.action,
    this.selectedCorporation,
  });

  @override
  Widget build(BuildContext context) {
    final myCorp = state.institutions['corporation'] is Map
        ? Map<String, dynamic>.from(state.institutions['corporation'] as Map)
        : const <String, dynamic>{};
    final membership = state.membership ?? const <String, dynamic>{};
    final myCorpId = membership['corporation_id']?.toString();
    final isMember = myCorpId != null && myCorpId.isNotEmpty;

    final targetCorp = selectedCorporation ?? (isMember ? myCorp : null);

    if (targetCorp == null) {
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
                style: context.widgetValueStyle
                    .copyWith(color: context.warningColor)),
            const SizedBox(height: 5),
            Text(
              'Join a corporation to access shared cities, technologies, contracts, and civic influence. Select any corporation in the directory to inspect its details.',
              style: context.widgetFooterStyle,
            ),
          ],
        ),
      );
    }

    final corporation = targetCorp;
    final name = (corporation['name'] ?? 'Corporation').toString();
    final id = corporation['id']?.toString() ?? '—';
    final memberCount =
        asIntOr(corporation['member_count'] ?? corporation['members'], 0);
    final treasury = asDouble(corporation['treasury']);
    final cityId = membership['city_id']?.toString();
    final capitalCityName = corporation['capital_city_name']?.toString() ??
        corporation['capital_city']?.toString() ??
        'Capital City';

    final sharedPatents = corporation['shared_patents'] is List
        ? corporation['shared_patents'] as List
        : (state.technology['corporationSharedPatents'] is List
            ? state.technology['corporationSharedPatents'] as List
            : const <dynamic>[]);

    final isAffiliated = myCorpId != null && myCorpId == id;

    final rules = corporation['rules'] is Map
        ? Map<String, dynamic>.from(corporation['rules'] as Map)
        : const <String, dynamic>{};

    final incomeTaxBps =
        asIntOr(rules['incomeTaxBps'] ?? rules['income_tax_bps'], 200);
    final salesTaxBps =
        asIntOr(rules['salesTaxBps'] ?? rules['sales_tax_bps'], 100);
    final corporateTaxBps =
        asIntOr(rules['corporateTaxBps'] ?? rules['corporate_tax_bps'], 250);

    final canAdoptCity = isAffiliated &&
        state.roles.any((raw) {
          if (raw is! Map) return false;
          final role = raw['role_name'] ?? raw['name'] ?? raw['role'];
          return raw['status']?.toString() == 'active' &&
              role?.toString().toLowerCase() == 'corporation executive';
        });

    return EarthSection(
      title: 'CORPORATION',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Corporation membership determines which shared rules, cities, technologies, contracts, and services are available to you.',
        'A city belongs to a corporation: moving between cities changes your local services and opportunities while preserving corporation membership.',
        'Independent people use Earth default rules and do not participate in corporation decisions.',
        'Corporate Budget: The corporate treasury is separate from city and personal accounts and funds research, patents, payroll, and corporate projects.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: .14),
                        borderRadius:
                            BorderRadius.circular(context.radiusControl),
                      ),
                      child: Icon(Icons.account_balance_outlined,
                          color: context.primaryColor),
                    ),
                    SizedBox(width: context.spacingInline + 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.toUpperCase(),
                              style: context.topicTitleStyle),
                          const SizedBox(height: 4),
                          Text(
                            'CAPITAL: ${capitalCityName.toUpperCase()}',
                            style: context.captionStyle.copyWith(
                                color: context.primaryColor,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    EarthBadge(
                      label: isAffiliated ? 'YOUR CORPORATION' : 'NETWORK',
                      variant: isAffiliated
                          ? EarthBadgeVariant.primary
                          : EarthBadgeVariant.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: context.subtleBorderColor),
                const SizedBox(height: 10),
                LayoutBuilder(
                builder: (context, constraints) {
                    // Match the personal page: two columns when there is room,
                    // with a single-column fallback on narrow screens.
                    final isWide = constraints.maxWidth >= 450;
                    // Keep the detail fields in a predictable alphabetical order so
                    // the same information is easy to scan in every corporation.
                    final attributes = [
                      _buildAttributeRow(
                        context,
                        icon: Icons.shield_outlined,
                        label: 'ADMISSION POLICY',
                        value: (corporation['admission_policy'] ?? 'open')
                            .toString()
                            .toUpperCase(),
                        accentColor: context.primaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.corporate_fare_outlined,
                        label: 'AFFILIATION',
                        value: name,
                        accentColor: context.primaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.hub_outlined,
                        label: 'CHARTERED CITIES',
                        value: '${corporation['city_count'] ?? 1}',
                        accentColor: context.secondaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.science_outlined,
                        label: 'SHARED PATENTS',
                        value: '${sharedPatents.length}',
                        accentColor: context.secondaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.groups_outlined,
                        label: 'MEMBERS',
                        value: '$memberCount',
                        accentColor: context.secondaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.gavel_outlined,
                        label: 'SUPERMAJORITY',
                        value: '67.0% Vote',
                        accentColor: context.primaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'CORPORATE BUDGET',
                        value: treasury == null
                            ? 'UNAVAILABLE'
                            : '${formatWholeNumber(treasury)} C',
                        accentColor: context.warningColor,
                      ),
                    ];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                  child: Column(
                                      children: attributes.take(4).toList())),
                              const SizedBox(width: 24),
                              Expanded(
                                  child: Column(
                                      children: attributes.skip(4).toList())),
                            ],
                          )
                        else ...[
                          ...attributes,
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _institutionBudgetCard(
            context,
            title: 'CORPORATE BUDGET',
            amount: treasury == null
                ? 'UNAVAILABLE'
                : '${formatWholeNumber(treasury)} C',
            icon: Icons.account_balance_wallet_outlined,
            description:
                'Separate corporate funds for research, patents, payroll, and corporate projects. This budget is not the city budget or your personal account.',
            accent: context.warningColor,
          ),
          SizedBox(height: context.spacingTopic),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.primaryColor.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(
                  color: context.primaryColor.withValues(alpha: .22)),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_outlined,
                    size: context.iconSize + 2, color: context.primaryColor),
                SizedBox(width: context.spacingInline),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CORPORATION RESEARCH COMMONS',
                        style: context.captionStyle
                            .copyWith(color: context.primaryColor),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sharedPatents.isEmpty
                            ? 'No shared patents are visible yet for this network.'
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
                    '${(corporateTaxBps / 100).toStringAsFixed(1)}% on affiliated business revenues\nAllocated directly to the sovereign corporate treasury to fund public goods and research. Parent Earth ceiling: Max 15.0%.',
                leading: Icon(Icons.receipt_long_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Market Sales Tax & Exchange Fee',
                subtitle:
                    '${(salesTaxBps / 100).toStringAsFixed(1)}% transaction fee on local commodity and machine trades.',
                leading: Icon(Icons.storefront_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Citizen Income Tax Rate',
                subtitle:
                    '${(incomeTaxBps / 100).toStringAsFixed(1)}% income levy on worker wages and personal distributions.',
                leading: Icon(Icons.person_pin_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Corporate Dividend Distribution',
                subtitle:
                    '50% treasury retained · 50% distributed to equity holders per game-cycle based on registered shareholding.',
                leading: Icon(Icons.payments_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.primary),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Shareholder Supermajority Protection',
                subtitle:
                    '67.0% voting supermajority required for charter amendments, corporate restructuring, or asset liquidations.',
                leading: Icon(Icons.lock_outline_rounded,
                    size: context.iconSize, color: context.primaryColor),
                badges: const [
                  EarthBadge(
                      label: 'IMMUTABLE INVARIANT',
                      variant: EarthBadgeVariant.neutral),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Membership Admission Standards',
                subtitle:
                    'Current policy: ${(corporation['admission_policy'] ?? 'open').toString().toUpperCase()}. Open admission welcomes all universal citizens; approval requires executive review.',
                leading: Icon(Icons.how_to_reg_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: [
                  EarthBadge(
                    label: (corporation['admission_policy'] ?? 'open')
                                .toString()
                                .toLowerCase() ==
                            'open'
                        ? 'EARTH DEFAULT'
                        : 'CUSTOM OVERRIDE',
                    variant: (corporation['admission_policy'] ?? 'open')
                                .toString()
                                .toLowerCase() ==
                            'open'
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
                leading: Icon(Icons.manage_accounts_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'EARTH DEFAULT',
                      variant: EarthBadgeVariant.neutral),
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
          if (id != '—') ...[
            SizedBox(height: context.spacingTitleOffset),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (isAffiliated) ...[
                  EarthButton(
                    label: 'CORPORATION RULES',
                    icon: Icons.gavel_outlined,
                    variant: EarthButtonVariant.secondary,
                    onPressed: busy
                        ? null
                        : () => showTaxCharterDialog(
                            context, action ?? ((_) async {}), id,
                            corporation: true),
                  ),
                  if (canAdoptCity)
                    EarthButton(
                      label: corporation['admission_policy']?.toString() ==
                              'approval'
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
                                currentPolicy: corporation['admission_policy']
                                        ?.toString() ??
                                    'open',
                              ),
                    ),
                  EarthButton(
                    label: 'LEAVE CORPORATION',
                    icon: Icons.logout,
                    variant: EarthButtonVariant.danger,
                    onPressed:
                        busy ? null : () => _confirmLeave(context, name, id),
                  ),
                ] else ...[
                  EarthButton(
                    label: 'JOIN CORPORATION',
                    icon: Icons.login,
                    variant: EarthButtonVariant.primary,
                    onPressed: busy
                        ? null
                        : () => (action ?? ((_) async {}))(() =>
                            const EarthApi()
                                .joinCorporation(corporationId: id)),
                  ),
                ],
              ],
            ),
          ],
          if (state.rankings['cities'] is List &&
              (state.rankings['cities'] as List).isNotEmpty) ...[
            SizedBox(height: context.spacingTopic),
            Text('CORPORATION CITY NETWORK', style: context.widgetTitleStyle),
            const SizedBox(height: 4),
            Text('Rules apply across the constituent municipal network.',
                style: context.widgetFooterStyle),
            SizedBox(height: context.spacingControl),
            EarthDataList(
              children: (state.rankings['cities'] as List)
                  .where((raw) {
                    if (raw is! Map) return false;
                    return raw['corporation_id']?.toString() == id;
                  })
                  .take(8)
                  .map((raw) {
                    final row = Map<String, dynamic>.from(raw as Map);
                    final city = row['id']?.toString() ?? 'City';
                    final isCurrentCity = city == cityId;

                    return EarthDataRow(
                      title: '${row['name'] ?? city}',
                      subtitle: '${row['residents'] ?? 0} residents',
                      leading: Icon(
                        Icons.location_city_outlined,
                        size: context.iconSize,
                        color: isCurrentCity
                            ? context.primaryColor
                            : context.mutedColor,
                      ),
                      trailing: isAffiliated && !isCurrentCity
                          ? EarthButton(
                              label: 'MOVE',
                              variant: EarthButtonVariant.primary,
                              onPressed: busy
                                  ? null
                                  : () => action?.call(() =>
                                      const EarthApi().joinCity(cityId: city)),
                            )
                          : (isCurrentCity
                              ? const EarthBadge(
                                  label: 'RESIDENCE',
                                  variant: EarthBadgeVariant.primary,
                                )
                              : const EarthBadge(
                                  label: 'CHARTERED CITY',
                                  variant: EarthBadgeVariant.neutral,
                                )),
                    );
                  })
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, String corporationName,
      String corporationId) async {
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusPanel),
            side:
                BorderSide(color: context.primaryColor.withValues(alpha: .35)),
          ),
          title: Text(
            'Leave Corporation?',
            style:
                context.topicTitleStyle.copyWith(color: context.warningColor),
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
                onChanged: (value) =>
                    setState(() => confirmed = value.trim() == corporationName),
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
              child: Text('CANCEL',
                  style:
                      context.controlStyle.copyWith(color: context.mutedColor)),
            ),
            EarthButton(
              label: 'LEAVE CORPORATION',
              variant: EarthButtonVariant.danger,
              onPressed: confirmed
                  ? () async {
                      Navigator.pop(dialogContext);
                      await (action ?? ((_) async {}))(() => const EarthApi()
                          .leaveCorporation(corporationId: corporationId));
                    }
                  : null,
            ),
          ],
        ),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: context.bodyStyle.copyWith(
              color: context.mutedColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: context.bodyStyle.copyWith(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
    final cityTreasury = asDouble(city['treasury']) ?? 0.0;

    final isCityResident = state.membership?['city_id'] != null;

    final housingRatio =
        formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio =
        formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);
    final cityMembers = state.json['cityMembers'] is List
        ? List<dynamic>.from(state.json['cityMembers'] as List)
        : const <dynamic>[];
    final playerId = state.human['id']?.toString();
    final standing = asIntOr(state.human['standing'], 0);

    return EarthSection(
      key: panelKey,
      title: 'INSTITUTIONS / CITY & SERVICES',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Municipal Administration & Service Capacity: Oversight of public housing, energy grid, connectivity, and healthcare.',
        'City Standing: Civic prestige and influence among resident citizens.',
        'City Budget: The municipal treasury pays for civic operations, public services, and explicit resident subsidies.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // City Administration Card
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: .14),
                        borderRadius:
                            BorderRadius.circular(context.radiusControl),
                      ),
                      child: Icon(Icons.location_city_outlined,
                          color: context.primaryColor),
                    ),
                    SizedBox(width: context.spacingInline + 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cityName, style: context.topicTitleStyle),
                          const SizedBox(height: 4),
                          Text(
                            'Housing: $housingRatio · Energy: $energyRatio · Connect: $connectRatio · Health: $healthRatio',
                            style: context.captionStyle.copyWith(
                              color: context.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(height: 1, color: context.subtleBorderColor),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final attributes = [
                      _buildAttributeRow(context,
                          icon: Icons.groups_outlined,
                          label: 'RESIDENTS',
                          value: '$residents',
                          accentColor: context.secondaryColor),
                      _buildAttributeRow(context,
                          icon: Icons.home_outlined,
                          label: 'HOUSING CAPACITY',
                          value: '$housingCap',
                          accentColor: context.secondaryColor),
                      _buildAttributeRow(context,
                          icon: Icons.bolt_outlined,
                          label: 'ENERGY CAPACITY',
                          value: '$energyCap',
                          accentColor: context.secondaryColor),
                      _buildAttributeRow(context,
                          icon: Icons.workspace_premium_outlined,
                          label: 'STANDING',
                          value: '$standing',
                          accentColor: context.primaryColor),
                      _buildAttributeRow(context,
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'CITY BUDGET',
                          value: '${formatWholeNumber(cityTreasury)} C',
                          accentColor: context.warningColor),
                    ];
                    if (constraints.maxWidth < 450)
                      return Column(children: attributes);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child:
                                Column(children: attributes.take(2).toList())),
                        const SizedBox(width: 24),
                        Expanded(
                            child:
                                Column(children: attributes.skip(2).toList())),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 12),
                _institutionBudgetCard(
                  context,
                  title: 'CITY BUDGET',
                  amount: '${formatWholeNumber(cityTreasury)} C',
                  icon: Icons.account_balance_wallet_outlined,
                  description:
                      'Municipal funds for civic buildings, public services, maintenance, and explicitly approved resident subsidies. This is separate from personal and corporate money.',
                  accent: context.warningColor,
                ),

                SizedBox(height: context.spacingTitleOffset),

                // City Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    EarthButton(
                      label: 'CHANGE CITY',
                      variant: isCityResident
                          ? EarthButtonVariant.secondary
                          : EarthButtonVariant.primary,
                      onPressed: busy
                          ? null
                          : () => showCityChangeDialog(
                              context, state, cityId, action),
                    ),
                    EarthButton(
                      label: 'PROPOSE BUDGET',
                      icon: Icons.account_balance_wallet_outlined,
                      variant: EarthButtonVariant.secondary,
                      onPressed: busy
                          ? null
                          : () => action(() => const EarthApi()
                              .setCityBudget('maintenance', cityId: cityId)),
                    ),
                    EarthButton(
                      label: 'TAX CHARTER',
                      icon: Icons.receipt_long_outlined,
                      variant: EarthButtonVariant.secondary,
                      onPressed: busy
                          ? null
                          : () => showTaxCharterDialog(context, action, cityId),
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
                                  communityId: (state.communities.first
                                      as Map<String, dynamic>)['id'] as String,
                                ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isCityResident && cityMembers.isNotEmpty) ...[
            SizedBox(height: context.spacingTitleOffset),
            Text('CITY STANDING', style: context.topicTitleStyle),
            SizedBox(height: context.spacingControl),
            EarthDataList(
              children:
                  cityMembers.take(5).toList().asMap().entries.map((entry) {
                final member = Map<String, dynamic>.from(entry.value as Map);
                final isPlayer = member['id']?.toString() == playerId;
                final name = member['display_name']?.toString() ??
                    member['id']?.toString() ??
                    'Resident';
                return EarthDataRow(
                    title: name,
                    subtitle: 'Standing: ${member['standing'] ?? 0}',
                    leading: Text('#${entry.key + 1}',
                        style: context.widgetTitleStyle
                            .copyWith(color: context.primaryColor)),
                    badges: [
                      if (isPlayer)
                        const EarthBadge(
                            label: 'YOU', variant: EarthBadgeVariant.primary)
                    ]);
              }).toList(),
            ),
          ],
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                    fontWeight: FontWeight.w700)),
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
    final pressure =
        asDouble(city['service_pressure'] ?? city['servicePressure']) ??
            [
              asDouble(ratios['housing']),
              asDouble(ratios['energy']),
              asDouble(ratios['connectivity']),
              asDouble(ratios['health']),
            ].whereType<double>().fold<double?>(
                null,
                (lowest, value) =>
                    lowest == null || value < lowest ? value : lowest);
    final taxRate = asDouble(city['tax_rate'] ?? city['taxRate']);
    final business = state.business;
    final operatingEffect = asDouble(business['city_operating_modifier'] ??
        business['cityOperatingModifier']);

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
                value: pressure == null
                    ? 'UNAVAILABLE'
                    : '${(pressure * 100).toStringAsFixed(0)}%',
                subtitle: pressure == null
                    ? 'Pressure data unavailable'
                    : (pressure < .75
                        ? 'Costs under strain'
                        : 'Normal service load'),
                icon: Icons.speed_outlined,
                accentColor: pressure != null && pressure < .75
                    ? context.warningColor
                    : context.primaryColor,
              ),
              EarthMetricTile(
                label: 'BUSINESS EFFECT',
                value: operatingEffect == null
                    ? 'UNAVAILABLE'
                    : '${operatingEffect >= 0 ? '+' : ''}${operatingEffect.toStringAsFixed(1)}%',
                subtitle: operatingEffect == null
                    ? 'No modifier reported'
                    : 'Operating cost modifier',
                icon: Icons.storefront_outlined,
                accentColor: operatingEffect != null && operatingEffect > 0
                    ? context.warningColor
                    : context.successColor,
              ),
              EarthMetricTile(
                label: 'CITY TAX',
                value: taxRate == null
                    ? 'UNAVAILABLE'
                    : '${taxRate.toStringAsFixed(1)}%',
                subtitle: 'Current resident rate',
                icon: Icons.receipt_long_outlined,
                accentColor: context.secondaryColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingTopic),
          Text('MUNICIPAL ORDINANCES & TARIFFS',
              style: context.widgetTitleStyle),
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
                leading: Icon(Icons.bolt_outlined,
                    size: context.iconSize, color: context.warningColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.warning),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Public Housing & Residency Criteria',
                subtitle:
                    'Priority allocation granted to active municipal residents and registered corporate affiliate citizens.',
                leading: Icon(Icons.home_work_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'DELEGATED', variant: EarthBadgeVariant.neutral),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Infrastructure Maintenance Assessment',
                subtitle:
                    'Municipal surcharge funding local transport connectivity, water filtration, and community health centers.',
                leading: Icon(Icons.construction_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: const [
                  EarthBadge(
                      label: 'CUSTOM OVERRIDE',
                      variant: EarthBadgeVariant.warning),
                ],
                showDivider: true,
              ),
              EarthDataRow(
                title: 'Essential Services Minimum Standard',
                subtitle:
                    'Municipal service ratios must maintain minimum survival index (>0.50) as guaranteed by Planetary Law.',
                leading: Icon(Icons.shield_outlined,
                    size: context.iconSize, color: context.primaryColor),
                badges: const [
                  EarthBadge(
                      label: 'IMMUTABLE INVARIANT',
                      variant: EarthBadgeVariant.neutral),
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

class CommunitiesPanel extends StatefulWidget {
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
  State<CommunitiesPanel> createState() => _CommunitiesPanelState();
}

class _CommunitiesPanelState extends State<CommunitiesPanel> {
  String _activeFilter = 'ALL'; // 'ALL', 'MY_COMMUNITIES', 'OPEN_TO_JOIN'
  int _page = 0;
  static const int _pageSize = 10;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _expandedCommunityId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawCommunities = widget.state.communities;

    // Filter active communities
    final activeCommunities = rawCommunities
        .where((raw) {
          final c = raw as Map<String, dynamic>;
          final status = (c['status']?.toString() ?? 'active').toLowerCase();
          return status != 'inactive' && status != 'dissolved';
        })
        .map((raw) => raw as Map<String, dynamic>)
        .toList();

    // Count categories for filter badges
    int myCount = 0;
    int openCount = 0;

    for (final c in activeCommunities) {
      final myRole = c['my_role']?.toString();
      final myRequestStatus = c['my_request_status']?.toString();
      final isOwner = myRole == 'founder';
      final isAdmin = myRole == 'admin';
      final isMember = isOwner || isAdmin || myRole == 'member';
      final isPending = myRequestStatus == 'pending';

      if (isMember || isOwner || isAdmin || isPending) {
        myCount++;
      }
      if (!isMember && !isOwner && !isAdmin && !isPending) {
        openCount++;
      }
    }

    final filteredList = activeCommunities.where((c) {
      final myRole = c['my_role']?.toString();
      final myRequestStatus = c['my_request_status']?.toString();
      final isOwner = myRole == 'founder';
      final isAdmin = myRole == 'admin';
      final isMember = isOwner || isAdmin || myRole == 'member';
      final isPending = myRequestStatus == 'pending';
      final name = c['name']?.toString() ?? '';

      if (_activeFilter == 'MY_COMMUNITIES' &&
          !(isMember || isOwner || isAdmin || isPending)) {
        return false;
      }
      if (_activeFilter == 'OPEN_TO_JOIN' &&
          (isMember || isOwner || isAdmin || isPending)) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final totalCount = filteredList.length;
    final totalPages = math.max(1, (totalCount / _pageSize).ceil());
    final safePage = _page.clamp(0, totalPages - 1);
    final pageItems =
        filteredList.skip(safePage * _pageSize).take(_pageSize).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EarthSection(
            title: 'CITIZEN COMMUNITIES & GUILDS',
            showSurface: false,
            infoBulletPoints: const [
              'Civic Communities & Cooperatives: Grassroots voluntary associations formed by citizens for collective mutual aid, cultural affinity, industry cooperation, and shared services.',
              'Membership & Contributions: Join or leave freely; voluntary treasury contributions fund shared communal initiatives and social crowdfunding campaigns.',
              'Cross-World Belonging: Communities are independent citizen associations spanning across all corporations and cities on Earth.',
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: EarthSearchInput(
                        controller: _searchController,
                        hintText: 'Search communities by name...',
                        onChanged: (value) => setState(() {
                          _searchQuery = value.trim();
                          _page = 0;
                        }),
                        onClear: () => setState(() {
                          _searchQuery = '';
                          _page = 0;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    EarthButton(
                      label: '+ FOUND COMMUNITY',
                      icon: Icons.add_business_outlined,
                      onPressed: widget.busy
                          ? null
                          : () => showCommunityComposer(context, widget.action),
                    ),
                  ],
                ),
                SizedBox(height: context.spacingControl),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(
                      label: 'ALL (${activeCommunities.length})',
                      isSelected: _activeFilter == 'ALL',
                      onTap: () => setState(() {
                        _activeFilter = 'ALL';
                        _page = 0;
                      }),
                    ),
                    _filterChip(
                      label: 'MY COMMUNITIES ($myCount)',
                      isSelected: _activeFilter == 'MY_COMMUNITIES',
                      onTap: () => setState(() {
                        _activeFilter = 'MY_COMMUNITIES';
                        _page = 0;
                      }),
                    ),
                    _filterChip(
                      label: 'OPEN TO JOIN ($openCount)',
                      isSelected: _activeFilter == 'OPEN_TO_JOIN',
                      onTap: () => setState(() {
                        _activeFilter = 'OPEN_TO_JOIN';
                        _page = 0;
                      }),
                    ),
                  ],
                ),
                SizedBox(height: context.spacingControl),
                if (filteredList.isEmpty)
                  EarthEmptyState(
                    message: _searchQuery.isNotEmpty
                        ? 'No communities found matching "$_searchQuery".'
                        : (_activeFilter == 'MY_COMMUNITIES'
                            ? 'You are not currently part of any community.'
                            : (_activeFilter == 'OPEN_TO_JOIN'
                                ? 'No joinable communities available at this time.'
                                : 'No communities registered yet. You can found the first one.')),
                    icon: Icons.groups_outlined,
                  )
                else ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: pageItems.map((community) {
                      final id = community['id']?.toString() ?? 'COM-001';
                      final name = community['name']?.toString() ?? 'Community';
                      final founderName =
                          community['founder_name']?.toString() ?? 'Citizen';
                      final description =
                          community['description']?.toString() ?? '';
                      final admissionPolicy =
                          (community['admission_policy']?.toString() ?? 'open')
                              .toUpperCase();
                      final myRole = community['my_role']?.toString();
                      final myRequestStatus =
                          community['my_request_status']?.toString();
                      final isOwner = myRole == 'founder';
                      final isAdmin = myRole == 'admin';
                      final isMember = isOwner || isAdmin || myRole == 'member';
                      final isPending = myRequestStatus == 'pending';
                      final members = asIntOr(community['member_count'], 12);
                      final sharedCredits =
                          asDouble(community['shared_credits']) ?? 0.0;

                      final isExpanded = _expandedCommunityId == id;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius:
                                BorderRadius.circular(context.radiusCard),
                            border: Border.all(
                                color: isMember
                                    ? context.primaryColor
                                        .withValues(alpha: .35)
                                    : context.subtleBorderColor),
                          ),
                          child: Column(
                            children: [
                              Semantics(
                                button: true,
                                expanded: isExpanded,
                                label: 'Show community $name details',
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(context.radiusCard),
                                  onTap: () => setState(() =>
                                    _expandedCommunityId =
                                        isExpanded ? null : id),
                                  child: Padding(
                                  padding: EdgeInsets.all(context.cardPadding),
                                  child: Row(
                                    children: [
                                      Icon(Icons.groups_outlined,
                                          size: context.iconSize + 2,
                                          color: isMember
                                              ? context.primaryColor
                                              : context.mutedColor),
                                      SizedBox(width: context.spacingInline),
                                      Expanded(
                                          child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: context.widgetValueStyle),
                                          const SizedBox(height: 3),
                                          Text(
                                            description.isEmpty
                                                ? 'No community description has been published.'
                                                : description,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.widgetFooterStyle,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'MEMBERS: $members  ·  TREASURY: ${formatWholeNumber(sharedCredits)} C  ·  ADMISSION: $admissionPolicy',
                                            style: context.captionStyle
                                                .copyWith(
                                                    color: context.mutedColor,
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                        ],
                                      )),
                                      if (isPending)
                                        const EarthBadge(
                                            label: 'PENDING REVIEW',
                                            variant: EarthBadgeVariant.warning),
                                      const SizedBox(width: 6),
                                      Icon(
                                          isExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: context.mutedColor),
                                    ],
                                  ),
                                  ),
                                ),
                              ),
                              if (isExpanded) ...[
                                Divider(
                                    height: 1,
                                    color: context.subtleBorderColor),
                                Padding(
                                  padding: EdgeInsets.all(context.cardPadding),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('FOUNDED BY: $founderName',
                                            style: context.widgetTitleStyle),
                                        SizedBox(
                                            height: context.spacingControl),
                                        Wrap(
                                          alignment: WrapAlignment.start,
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (isPending) ...[
                                              EarthButton(
                                                label: 'CANCEL REQ',
                                                variant:
                                                    EarthButtonVariant.danger,
                                                onPressed: widget.busy
                                                    ? null
                                                    : () => widget.action(() =>
                                                        const EarthApi()
                                                            .leaveCommunity(
                                                                id)),
                                              ),
                                            ] else if (!isMember) ...[
                                              EarthButton(
                                                label: admissionPolicy ==
                                                        'APPROVAL'
                                                    ? 'APPLY'
                                                    : 'JOIN',
                                                variant:
                                                    EarthButtonVariant.primary,
                                                onPressed: widget.busy
                                                    ? null
                                                    : () {
                                                        if (admissionPolicy ==
                                                            'APPROVAL') {
                                                          showCommunityApplicationDialog(
                                                              context,
                                                              community,
                                                              widget.action);
                                                        } else {
                                                          widget.action(() =>
                                                              const EarthApi()
                                                                  .joinCommunity(
                                                                      id));
                                                        }
                                                      },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (totalPages > 1) ...[
                    SizedBox(height: context.spacingControl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 32),
                              icon: const Icon(Icons.first_page, size: 20),
                              onPressed: safePage > 0
                                  ? () => setState(() => _page = 0)
                                  : null,
                              tooltip: 'First Page',
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 32),
                              icon: const Icon(Icons.chevron_left, size: 20),
                              onPressed: safePage > 0
                                  ? () => setState(() => _page = safePage - 1)
                                  : null,
                              tooltip: 'Previous Page',
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Page ',
                                  style: TextStyle(
                                      fontSize: 12, color: context.mutedColor),
                                ),
                                _PageNumberInput(
                                  key: ValueKey(
                                      'comm_page_${safePage + 1}_$totalPages'),
                                  currentPage: safePage + 1,
                                  totalPages: totalPages,
                                  onSubmitted: (newPage) {
                                    setState(() {
                                      _page = newPage - 1;
                                    });
                                  },
                                ),
                                Text(
                                  ' of $totalPages ($totalCount)',
                                  style: TextStyle(
                                      fontSize: 12, color: context.mutedColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 32),
                              icon: const Icon(Icons.chevron_right, size: 20),
                              onPressed: safePage < totalPages - 1
                                  ? () => setState(() => _page = safePage + 1)
                                  : null,
                              tooltip: 'Next Page',
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 32),
                              icon: const Icon(Icons.last_page, size: 20),
                              onPressed: safePage < totalPages - 1
                                  ? () => setState(() => _page = totalPages - 1)
                                  : null,
                              tooltip: 'Last Page',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Show $label communities',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? context.primaryColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                isSelected ? context.primaryColor : context.subtleBorderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: context.controlStyle.copyWith(
            color: isSelected ? context.primaryColor : context.mutedColor,
          ),
        ),
        ),
      ),
    );
  }
}

/// Dedicated management and activity panel for the player's active community.
class MyCommunityPanel extends StatefulWidget {
  final Key? panelKey;
  final String? communityId;
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final ValueChanged<String>? onNavigate;

  const MyCommunityPanel({
    super.key,
    this.panelKey,
    this.communityId,
    required this.state,
    required this.busy,
    required this.action,
    this.onNavigate,
  });

  @override
  State<MyCommunityPanel> createState() => _MyCommunityPanelState();
}

class _MyCommunityPanelState extends State<MyCommunityPanel> {
  List<dynamic> _members = [];
  List<dynamic> _requests = [];
  bool _loading = false;
  String? _loadedCommunityId;

  Map<String, dynamic>? get _community {
    if (widget.communityId != null) {
      for (final c in widget.state.communities) {
        if (c is Map && c['id']?.toString() == widget.communityId) {
          return Map<String, dynamic>.from(c);
        }
      }
    }
    return widget.state.myCommunity;
  }

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void didUpdateWidget(covariant MyCommunityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final comm = _community;
    final currentId = comm?['id']?.toString();
    if (currentId != _loadedCommunityId ||
        oldWidget.communityId != widget.communityId) {
      _fetchDetails();
    }
  }

  Future<void> _fetchDetails() async {
    final myComm = _community;
    if (myComm == null) return;
    final id = myComm['id']?.toString();
    if (id == null) return;

    setState(() {
      _loading = true;
      _loadedCommunityId = id;
    });

    try {
      final memRes = await const EarthApi().listCommunityMembers(id);
      _members = memRes['members'] as List<dynamic>? ?? [];
      final admissionPolicy =
          (myComm['admission_policy']?.toString() ?? 'open').toLowerCase();
      final myRole = myComm['my_role']?.toString();
      final isElevated = myRole == 'founder' || myRole == 'admin';

      if (isElevated && admissionPolicy == 'approval') {
        final reqRes = await const EarthApi().listCommunityRequests(id);
        _requests = reqRes['requests'] as List<dynamic>? ?? [];
      } else {
        _requests = [];
      }
    } catch (_) {
      // Ignored
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmLeave(
      BuildContext context, String communityId, String communityName) async {
    final controller = TextEditingController();
    var confirmed = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.panelColor,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.radiusPanel)),
          title: Text('Leave Community?',
              style: context.topicTitleStyle
                  .copyWith(color: context.warningColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'Type "$communityName" to confirm that you want to leave this community.',
                  style: context.widgetFooterStyle),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (value) => setDialogState(
                    () => confirmed = value.trim() == communityName),
                decoration: InputDecoration(
                    labelText: 'Community name',
                    labelStyle: context.widgetFooterStyle),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('CANCEL',
                    style: context.controlStyle
                        .copyWith(color: context.mutedColor))),
            EarthButton(
              label: 'LEAVE COMMUNITY',
              variant: EarthButtonVariant.danger,
              onPressed: !confirmed || widget.busy
                  ? null
                  : () async {
                      Navigator.pop(dialogContext);
                      await widget.action(
                          () => const EarthApi().leaveCommunity(communityId));
                    },
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Widget _buildAttributeRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myComm = _community;
    if (myComm == null) {
      return EarthSection(
        key: widget.panelKey,
        title: 'COMMUNITY',
        showSurface: false,
        icon: Icons.groups_outlined,
        child: EarthEmptyState(
          message: 'You are not currently an owner or member of any community.',
          icon: Icons.groups_outlined,
        ),
      );
    }

    final id = myComm['id']?.toString() ?? 'COM-001';
    final name = myComm['name']?.toString() ?? 'Community';
    final founderName = myComm['founder_name']?.toString() ?? 'Citizen';
    final description = myComm['description']?.toString() ?? '';
    final admissionPolicy =
        (myComm['admission_policy']?.toString() ?? 'open').toUpperCase();
    final myRole = myComm['my_role']?.toString();
    final isOwner = myRole == 'founder';
    final isAdmin = myRole == 'admin';
    final memberCount = asIntOr(
        myComm['member_count'], _members.isNotEmpty ? _members.length : 1);
    final sharedCredits = asDouble(myComm['shared_credits']) ?? 0.0;

    return EarthSection(
      key: widget.panelKey,
      title: name.toUpperCase(),
      showSurface: false,
      showHeader: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Identity & Action Header Bar
          Container(
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
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.primaryColor.withValues(alpha: .14),
                        borderRadius:
                            BorderRadius.circular(context.radiusControl),
                      ),
                      child: Icon(Icons.groups_outlined,
                          color: context.primaryColor),
                    ),
                    SizedBox(width: context.spacingInline + 4),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.toUpperCase(),
                            style: context.topicTitleStyle),
                        const SizedBox(height: 4),
                        Text('FOUNDED BY: $founderName',
                            style: context.captionStyle.copyWith(
                                color: context.primaryColor,
                                fontWeight: FontWeight.w700)),
                      ],
                    )),
                    Wrap(children: [
                      if (isOwner)
                        const EarthBadge(
                          label: 'OWNER / FOUNDER',
                          variant: EarthBadgeVariant.primary,
                        )
                      else if (isAdmin)
                        const EarthBadge(
                          label: 'ADMIN',
                          variant: EarthBadgeVariant.primary,
                        )
                      else
                        const EarthBadge(
                          label: 'MEMBER',
                          variant: EarthBadgeVariant.success,
                        ),
                    ]),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: context.bodyStyle.copyWith(
                      color: context.mutedColor,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Divider(height: 1, color: context.subtleBorderColor),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final attributes = [
                      _buildAttributeRow(context,
                          icon: Icons.groups_outlined,
                          label: 'MEMBERS',
                          value: '$memberCount',
                          accentColor: context.secondaryColor),
                      _buildAttributeRow(context,
                          icon: Icons.savings_outlined,
                          label: 'COMMUNAL TREASURY',
                          value: '${sharedCredits.toStringAsFixed(2)} C',
                          accentColor: context.warningColor),
                      _buildAttributeRow(context,
                          icon: Icons.policy_outlined,
                          label: 'ADMISSION',
                          value: admissionPolicy,
                          accentColor: context.primaryColor),
                    ];
                    return constraints.maxWidth >= 450
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Expanded(
                                    child: Column(
                                        children: attributes.take(2).toList())),
                                const SizedBox(width: 24),
                                Expanded(
                                    child: Column(
                                        children: attributes.skip(2).toList())),
                              ])
                        : Column(children: attributes);
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (isOwner || isAdmin)
                      EarthButton(
                        label: 'MANAGE COMMUNITY',
                        icon: Icons.settings_outlined,
                        variant: EarthButtonVariant.primary,
                        onPressed: widget.busy
                            ? null
                            : () async {
                                await showCommunityManageDialog(
                                  context,
                                  myComm,
                                  widget.state,
                                  widget.action,
                                );
                                _fetchDetails();
                              },
                      ),
                    if (!isOwner)
                      EarthButton(
                        label: 'LEAVE COMMUNITY',
                        variant: EarthButtonVariant.danger,
                        onPressed: widget.busy
                            ? null
                            : () => _confirmLeave(context, id, name),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 3. Quick Contribution Strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.subtleBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.volunteer_activism_outlined,
                    color: context.primaryColor, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTRIBUTE TO GUILD TREASURY',
                        style: context.widgetTitleStyle
                            .copyWith(color: context.primaryColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Communal funds support shared ventures, municipal infrastructure, and guild services.',
                        style: context.widgetFooterStyle
                            .copyWith(color: context.mutedColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    EarthButton(
                      label: '+100 C',
                      variant: EarthButtonVariant.secondary,
                      onPressed: widget.busy
                          ? null
                          : () => widget.action(() =>
                              const EarthApi().contributeToCommunity(id, 100)),
                    ),
                    EarthButton(
                      label: '+500 C',
                      variant: EarthButtonVariant.secondary,
                      onPressed: widget.busy
                          ? null
                          : () => widget.action(() =>
                              const EarthApi().contributeToCommunity(id, 500)),
                    ),
                    EarthButton(
                      label: 'CUSTOM',
                      icon: Icons.add_circle_outline,
                      variant: EarthButtonVariant.primary,
                      onPressed: widget.busy
                          ? null
                          : () => showCommunityContributionDialog(
                              context, widget.action, id),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. Pending Review Requests (if founder/admin and requests exist)
          if ((isOwner || isAdmin) && _requests.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'PENDING ADMISSION REQUESTS (${_requests.length})',
              style:
                  context.topicTitleStyle.copyWith(color: context.warningColor),
            ),
            const SizedBox(height: 8),
            EarthDataList(
              children: _requests.map((raw) {
                final req = raw as Map<String, dynamic>;
                final reqId = req['id']?.toString() ?? '';
                final applicant = req['human_name']?.toString() ??
                    req['human_id']?.toString() ??
                    '';
                final reqDay = req['requested_game_day'];

                return EarthDataRow(
                  title: applicant,
                  subtitle: 'Requested admission on Game Day $reqDay',
                  leading: Icon(Icons.person_add_outlined,
                      color: context.warningColor),
                  badges: const [
                    EarthBadge(
                      label: 'PENDING REVIEW',
                      variant: EarthBadgeVariant.warning,
                    ),
                  ],
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      EarthButton(
                        label: 'APPROVE',
                        variant: EarthButtonVariant.primary,
                        onPressed: widget.busy
                            ? null
                            : () async {
                                await const EarthApi().decideCommunityRequest(
                                  communityId: id,
                                  requestId: reqId,
                                  action: 'approve',
                                );
                                _fetchDetails();
                              },
                      ),
                      EarthButton(
                        label: 'REJECT',
                        variant: EarthButtonVariant.danger,
                        onPressed: widget.busy
                            ? null
                            : () async {
                                await const EarthApi().decideCommunityRequest(
                                  communityId: id,
                                  requestId: reqId,
                                  action: 'reject',
                                );
                                _fetchDetails();
                              },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 24),

          // 5. Members Directory
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MEMBER ROSTER (${_members.length})',
                style:
                    context.topicTitleStyle.copyWith(color: context.mutedColor),
              ),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  tooltip: 'Refresh Members',
                  onPressed: _fetchDetails,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _members.isEmpty
              ? const EarthEmptyState(
                  message:
                      'Member roster is currently synchronizing or no other members joined yet.',
                  icon: Icons.groups_outlined,
                )
              : EarthDataList(
                  children: _members.map((raw) {
                    final m = raw as Map<String, dynamic>;
                    final hId = m['human_id']?.toString() ?? '';
                    final hName = m['human_name']?.toString() ?? hId;
                    final role =
                        (m['role']?.toString() ?? 'member').toUpperCase();
                    final isMFounder = role == 'FOUNDER';
                    final isMAdmin = role == 'ADMIN';
                    final joinedGameDay = asIntOr(m['joined_game_day'], 1);
                    final joinedYear = ((joinedGameDay - 1) ~/ 365) + 1;
                    final joinedDay = ((joinedGameDay - 1) % 365) + 1;

                    return EarthDataRow(
                      title: hName,
                      subtitle: 'Joined on Year $joinedYear, Day $joinedDay',
                      leading: Icon(
                        isMFounder
                            ? Icons.star_rounded
                            : isMAdmin
                                ? Icons.verified_user_outlined
                                : Icons.person_outline_rounded,
                        color: isMFounder
                            ? context.primaryColor
                            : isMAdmin
                                ? context.secondaryColor
                                : context.mutedColor,
                      ),
                      badges: [
                        EarthBadge(
                          label: role,
                          variant: isMFounder
                              ? EarthBadgeVariant.primary
                              : isMAdmin
                                  ? EarthBadgeVariant.secondary
                                  : EarthBadgeVariant.neutral,
                        ),
                      ],
                      trailing: isOwner && !isMFounder
                          ? isMAdmin
                              ? EarthButton(
                                  label: 'DEMOTE',
                                  variant: EarthButtonVariant.ghost,
                                  onPressed: widget.busy
                                      ? null
                                      : () async {
                                          await const EarthApi()
                                              .setCommunityMemberRole(
                                            communityId: id,
                                            targetHumanId: hId,
                                            role: 'member',
                                          );
                                          _fetchDetails();
                                        },
                                )
                              : EarthButton(
                                  label: 'MAKE ADMIN',
                                  variant: EarthButtonVariant.secondary,
                                  onPressed: widget.busy
                                      ? null
                                      : () async {
                                          await const EarthApi()
                                              .setCommunityMemberRole(
                                            communityId: id,
                                            targetHumanId: hId,
                                            role: 'admin',
                                          );
                                          _fetchDetails();
                                        },
                                )
                          : null,
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }
}
