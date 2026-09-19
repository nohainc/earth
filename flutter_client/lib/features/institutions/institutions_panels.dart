import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

import '../../shared/widgets/format_helpers.dart';
import '../../shared/widgets/credit_income_summary_card.dart';
import '../communications/comm_link_dialog.dart';
import '../house/house_lineage_dialog.dart';
import 'institutions_dialogs.dart';
import 'organization_people_roles_panel.dart';

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
                  Text(title,
                      style: context.captionStyle.copyWith(color: accent)),
                  Text(amount,
                      style: context.widgetValueStyle.copyWith(color: accent)),
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

Widget _institutionFinanceClarityCard(
  BuildContext context, {
  required Map<String, dynamic> institution,
  Map<String, dynamic> projection = const <String, dynamic>{},
}) {
  final treasury = asDouble(projection['treasury'] ??
          projection['cash_treasury'] ??
          institution['treasury']) ??
      0;
  final budget = asDouble(projection['budget_authorized'] ??
          projection['authorized_units'] ??
          projection['budget']) ??
      0;
  final committed = asDouble(projection['budget_committed'] ??
          projection['committed_units'] ??
          projection['committed']) ??
      0;
  final available = asDouble(projection['budget_available'] ??
          projection['available_authority'] ??
          (budget - committed)) ??
      math.max(0, budget - committed);
  final revenue = asDouble(projection['period_revenue'] ??
          projection['daily_revenue'] ??
          projection['revenue']) ??
      0;
  final expenses = asDouble(projection['period_spending'] ??
          projection['daily_expenses'] ??
          projection['expenses']) ??
      0;

  String money(double value) => '${formatWholeNumber(value)} C';
  final values = [
    ('Treasury', money(treasury), Icons.account_balance_wallet_outlined),
    ('Budget', money(budget), Icons.fact_check_outlined),
    ('Committed', money(committed), Icons.assignment_outlined),
    ('Available', money(available), Icons.check_circle_outline),
    ('Revenue', money(revenue), Icons.trending_up_outlined),
    ('Expenses', money(expenses), Icons.trending_down_outlined),
  ];

  return Container(
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
        Text('FINANCIAL POSITION', style: context.topicTitleStyle),
        const SizedBox(height: 4),
        Text(
          'Cash, spending permission, commitments, and activity are shown separately.',
          style: context.widgetFooterStyle,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 430
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 10,
              children: values
                  .map((item) => SizedBox(
                        width: width,
                        child: Row(
                          children: [
                            Icon(item.$3,
                                size: 16, color: context.primaryColor),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.$1, style: context.captionStyle),
                                  Text(item.$2,
                                      style: context.bodyStyle.copyWith(
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            );
          },
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
  String? _error;
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _search.text.trim();
      final rows = await const EarthApi().listCorporations(search: query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _corporations = rows;
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
        final fallback = (widget.state.rankings['corporations'] as List? ?? const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        setState(() {
          if (fallback.isNotEmpty) {
            _corporations = fallback;
            _selected = fallback.first;
            _error = null;
          } else {
            _error = 'Live Corporation directory unavailable.';
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
    final policy =
        (target?['admission_policy']?.toString() ?? 'UNKNOWN').toUpperCase();
    if (!const {'OPEN', 'APPROVAL', 'INVITE_ONLY'}.contains(policy)) return;
    Map<String, dynamic> quote = const {};
    try {
      quote = await const EarthApi().quoteV5CorporationMembership(id);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            'Admission consequences are unavailable. Please try again when the server quote is ready.');
      }
      return;
    }
    if (quote['ok'] != true) return;
    if (!mounted) return;
    final inviteController = TextEditingController();
    try {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(policy == 'OPEN' ? 'JOIN CORPORATION?' : 'REVIEW ADMISSION?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${target?['name'] ?? id}\n\n'
            'Admission: ${_admissionLabel(target ?? const {})}\n'
            'Residential capacity added: 1 unit\n'
            'Current usage: ${quote['capacity'] is Map ? (quote['capacity'] as Map)['currentUsage'] ?? 'Not reported' : 'Not reported'}\n'
            'Incremental daily rent: ${quote['capacity'] is Map ? (quote['capacity'] as Map)['incrementalCharge'] ?? 'Not reported' : 'Not reported'}\n\n'
            'Review this affiliation before continuing. Capacity and pricing are calculated by the server.'),
          if (policy == 'INVITE_ONLY') ...[
            const SizedBox(height: 12),
            TextField(controller: inviteController, obscureText: true, decoration: const InputDecoration(labelText: 'Invitation token')),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                  policy == 'OPEN' ? 'JOIN CORPORATION' : policy == 'APPROVAL' ? 'APPLY TO JOIN' : 'ACCEPT INVITATION')),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await widget.action(() async {
      await const EarthApi().applyV5CorporationMembership(corporationId: id, inviteToken: inviteController.text.trim());
      return const EarthApi().world();
    });
    } finally {
      inviteController.dispose();
    }
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _load);
  }

  String _admissionLabel(Map<String, dynamic> row) {
    switch ((row['admission_policy']?.toString() ?? 'UNKNOWN').toUpperCase()) {
      case 'OPEN':
        return 'OPEN';
      case 'REQUEST':
      case 'APPROVAL':
        return 'APPLICATION';
      case 'INVITE_ONLY':
      case 'INVITE':
        return 'INVITE ONLY';
      case 'CLOSED':
        return 'CLOSED';
      default:
        return 'UNKNOWN';
    }
  }

  String _joinLabel(Map<String, dynamic> row) {
    switch (row['admission_policy']?.toString().toUpperCase()) {
      case 'APPROVAL':
      case 'REQUEST':
        return 'APPLY TO JOIN';
      case 'INVITE_ONLY':
      case 'INVITE':
        return 'ACCEPT INVITATION';
      default:
        return 'JOIN';
    }
  }

  String _rate(dynamic value) {
    final bps = asInt(value);
    return bps == null || bps < 0
        ? 'Not published'
        : '${(bps / 100).toStringAsFixed(1)}%';
  }

  bool _canJoin(Map<String, dynamic> row, bool isAffiliated) {
    if (_isMember || isAffiliated) return false;
    final policy =
        (row['admission_policy']?.toString() ?? 'UNKNOWN').toUpperCase();
    return const {'OPEN', 'APPROVAL', 'INVITE_ONLY'}.contains(policy);
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
                'This will remove you from $name and its current Corporation affiliation. Your businesses and personal assets remain yours.',
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
    final members = asIntOr(row['member_count'] ?? row['members'], 0);
    final treasury = asDouble(row['treasury']) ?? 0.0;
    final territory =
        row['primary_territory_name']?.toString() ?? 'Territory not reported';
    final privateCapacity = asIntOr(row['private_slot_capacity'], 0);
    final privateUsed = asIntOr(row['private_slots_used'], 0);
    final capacityAvailable = math.max(0, privateCapacity - privateUsed);
    final v5Occupied = row['v5_occupied_capacity']?.toString();
    final v5Containers = row['v5_required_territory_units']?.toString();
    final v5Standard = row['v5_standard_territory_capacity']?.toString();
    final admissionPolicy =
        (row['admission_policy'] ?? 'UNKNOWN').toString().toUpperCase();

    final corporateTaxBps = asInt(row['corporate_tax_bps']);
    final propertyTaxBps = asInt(row['property_tax_bps']);

    final sharedPatents = row['shared_patents'] is List
        ? row['shared_patents'] as List
        : const <dynamic>[];

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
        label: 'PROPERTY TAX',
        value: _rate(propertyTaxBps),
        accentColor: context.primaryColor,
      ),
      _buildAttributeRow(
        context,
        icon: Icons.science_outlined,
        label: 'TECHNOLOGY',
        value: sharedPatents.isEmpty
            ? 'Not reported'
            : '${sharedPatents.length} shared',
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
        label: 'TERRITORIES',
        value: '${asIntOr(row['territory_count'], 0)}',
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
            const SizedBox(height: 8),
            Text('PHYSICAL CAPACITY', style: context.captionStyle),
            const SizedBox(height: 6),
            _buildAttributeRow(context,
                icon: Icons.location_on_outlined,
                label: 'PRIMARY TERRITORY',
                value: territory,
                accentColor: context.primaryColor),
            _buildAttributeRow(context,
                icon: Icons.groups_outlined,
                label: 'MEMBERS',
                value: '$members Houses',
                accentColor: context.secondaryColor),
            _buildAttributeRow(context,
                icon: Icons.grid_view_outlined,
                label: 'PRIVATE CAPACITY',
                value: privateCapacity > 0
                    ? '$capacityAvailable available'
                    : 'Not reported',
                accentColor: context.goldColor),
            if (v5Occupied != null) ...[
              _buildAttributeRow(context,
                  icon: Icons.stacked_bar_chart_outlined,
                  label: 'CAPACITY USED / STANDARD',
                  value: '$v5Occupied / ${v5Standard ?? 'Not reported'}',
                  accentColor: context.primaryColor),
              _buildAttributeRow(context,
                  icon: Icons.stacked_bar_chart_outlined,
                  label: 'POOLED CAPACITY',
                  value: '$v5Occupied occupied',
                  accentColor: context.primaryColor),
              _buildAttributeRow(context,
                  icon: Icons.layers_outlined,
                  label: 'STANDARD CONTAINERS',
                  value: '$v5Containers × $v5Standard units',
                  accentColor: context.secondaryColor),
              _buildAttributeRow(context,
                  icon: Icons.public_outlined,
                  label: 'EARTH CAPACITY EXPENSE',
                  value: '${row['v5_earth_capacity_expense']?.toString() ?? 'Not reported'} C/day',
                  accentColor: context.warningColor),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_canJoin(row, isAffiliated))
                  EarthButton(
                    label: admissionPolicy == 'REQUEST'
                        ? 'REQUEST TO JOIN'
                        : 'JOIN',
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
                'ORGANIZATION CHARTER PRINCIPLES',
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
            'Core constitutional rules applied uniformly across all organizations, syndicates, and enterprises on Earth:',
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
                  'Commercial Subsidiarity',
                  'Organizations coordinate enterprise equity and production across territories while respecting local territorial commons.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.biotech_outlined,
                  'Shared Technology & Patents',
                  'Free access to shared organizational technology, patent pool, and joint industrial contracts.',
                ),
                const SizedBox(height: 10),
                _buildBenefitRow(
                  context,
                  Icons.how_to_vote_outlined,
                  'Shareholder Democratic Franchise',
                  'Every member votes on organization leadership, charter amendments, and asset ventures.',
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
                  'Active Executives hold statutory authority to manage operations, proposals, and agreements.',
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
    final members = asIntOr(row['member_count'] ?? row['members'], 0);
    final territory =
        row['primary_territory_name']?.toString() ?? 'Territory not reported';
    final admission = _admissionLabel(row);

    final rules = row['rules'] is Map
        ? Map<String, dynamic>.from(row['rules'] as Map)
        : const <String, dynamic>{};

    final incomeTaxBps = asIntOr(
        row['income_tax_bps'] ??
            rules['incomeTaxBps'] ??
            rules['income_tax_bps'],
        -1);
    final salesTaxBps = asIntOr(
        row['sales_tax_bps'] ?? rules['salesTaxBps'] ?? rules['sales_tax_bps'],
        -1);
    final corporateTaxBps = asIntOr(
        row['corporate_tax_bps'] ??
            rules['corporateTaxBps'] ??
            rules['corporate_tax_bps'],
        -1);

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
                        if (isAffiliated)
                          const EarthBadge(
                              label: 'YOUR CORPORATION',
                              variant: EarthBadgeVariant.primary),
                        if (!isAffiliated)
                          EarthBadge(
                              label: admission,
                              variant: admission == 'OPEN'
                                  ? EarthBadgeVariant.secondary
                                  : EarthBadgeVariant.neutral),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Sorted attributes (alphabetical order, no badges in head record)
                    Wrap(
                      spacing: tokens.number('spacing.titleOffset', 12),
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _nodeMiniStat(context, 'Houses', '$members'),
                        _nodeMiniStat(context, 'Territory', territory),
                        _nodeMiniStat(
                            context, 'Income Tax', _rate(incomeTaxBps)),
                        _nodeMiniStat(context, 'Sales Fee', _rate(salesTaxBps)),
                        _nodeMiniStat(
                            context, 'Corporate Tax', _rate(corporateTaxBps)),
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
                    if (_canJoin(row, isAffiliated))
                      EarthButton(
                        label: _joinLabel(row),
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

    final currentCorpName = current['name']?.toString();
    final cockpit = EarthPageCockpit(
      status: 'WORLD · CORPORATIONS',
      statusColor: context.primaryColor,
      infoTitle: 'HOW CORPORATIONS WORK',
      infoDescription:
          'Corporations are chartered economic organizations. They coordinate enterprise equity, public capacity, research patents, and corporate governance policy across Earth.',
      title: 'CORPORATION DIRECTORY',
      subtitle:
          'Compare corporate policies, shared technology, and membership conditions.',
      metrics: [
        CockpitMetric(
          label: 'Corporations',
          value: '${_corporations.length}',
          icon: Icons.domain_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Affiliation',
          value: _isMember && currentCorpName != null
              ? currentCorpName
              : 'Independent',
          icon: Icons.verified_user_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Open to join',
          value:
              '${_corporations.where((r) => (r['admission_policy']?.toString() ?? 'UNKNOWN').toUpperCase() == 'OPEN').length}',
          icon: Icons.login,
          color: context.goldColor,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cockpit,
        const SizedBox(height: 28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showMemberSummary && _isMember) ...[
              _memberView(current),
              const SizedBox(height: 32),
              Text(
                'ALL CORPORATIONS',
                style:
                    context.topicTitleStyle.copyWith(color: context.mutedColor),
              ),
              const SizedBox(height: 12),
            ],
            _directoryView(),
          ],
        ),
      ],
    );
  }

  Widget _memberView(Map<String, dynamic> current) {
    final name = current['name']?.toString() ?? 'your corporation';
    final territory = current['primary_territory_name']?.toString() ??
        current['territory_name']?.toString() ??
        current['capital_city_name']?.toString() ??
        widget.state.membership?['territory_name']?.toString() ??
        widget.state.membership?['territory_id']?.toString() ??
        'territory';
    final members = current['member_count'] ?? 0;
    final treasury = asDouble(current['treasury']) ?? 0.0;
    final occupied = current['v5_occupied_capacity']?.toString();
    final requiredContainers = current['v5_required_territory_units']?.toString();
    final standardCapacity = current['v5_standard_territory_capacity']?.toString();
    final affiliationSummary = occupied != null
        ? 'Your House is affiliated with $name. The Corporation uses $occupied occupied capacity units across $requiredContainers standardized containers of $standardCapacity units ($members Houses · ${treasury.toStringAsFixed(0)} C treasury reserves).'
        : 'Your House belongs to $name and resides in its primary Territory: $territory ($members Houses · ${treasury.toStringAsFixed(0)} C treasury reserves).';

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.primaryColor.withValues(alpha: .35)),
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
                          label: 'YOUR CORPORATION',
                          variant: EarthBadgeVariant.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      affiliationSummary,
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
        LayoutBuilder(builder: (context, constraints) {
          final action = EarthButton(
            label: 'FOUND CORPORATION',
            icon: Icons.add_business_outlined,
            onPressed: _isMember || widget.busy
                ? null
                : () => showFormationComposer(context, widget.action),
          );
          final search = EarthSearchInput(
            controller: _search,
            hintText: 'Search corporations by name...',
            onChanged: (_) => _scheduleSearch(),
            onClear: _load,
          );
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 10), action],
            );
          }
          return Row(children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            action
          ]);
        }),
        SizedBox(height: context.spacingTitleOffset),
        if (_error != null) ...[
          Row(children: [
            Expanded(
                child: Text(_error!,
                    style: context.widgetFooterStyle
                        .copyWith(color: context.warningColor))),
            TextButton(onPressed: _load, child: const Text('RETRY')),
          ]),
          const SizedBox(height: 8),
        ],
        if (_loading)
          Center(child: CircularProgressIndicator(color: context.primaryColor))
        else if (_corporations.isEmpty)
          const EarthEmptyState(
            message: 'No corporations found matching your search.',
            icon: Icons.domain_disabled_outlined,
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _corporations.length,
            itemBuilder: (context, index) {
              final row = _corporations[index];
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
            },
          ),
      ],
    );
  }
}

class WorldRankingsPanel extends StatefulWidget {
  final EarthState state;
  const WorldRankingsPanel({super.key, required this.state});

  @override
  State<WorldRankingsPanel> createState() => _WorldRankingsPanelState();
}

// Kept as a source-compatible alias for downstream page integrations.
typedef CivicRankingsPanel = WorldRankingsPanel;

class _WorldRankingsPanelState extends State<WorldRankingsPanel> {
  int _singleTab = 0; // Legacy compatibility view.
  int _leftTab = 0; // 0: Citizens, 1: Houses
  int _rightTab = 0; // 0: Corporations, 1: Territories
  int _metricTab = 0;
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
        final canonicalMetrics =
            _canonicalMetrics(widget.state.rankings['metrics']);
        if (canonicalMetrics.isNotEmpty) {
          return _buildCanonicalMetricRankings(
              context,
              canonicalMetrics,
              widget.state.rankings['gameDay'],
              widget.state.rankings['rulesVersion']);
        }

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
              'Corporation Ranking Index (0–100):\n\n• 1. Total Enterprise Capitalization: 45%\n  Corporate treasury + sum of affiliated Territory valuations.\n\n• 2. Productive Ecosystem: 30%\n  Active businesses operating across affiliated Territories.\n\n• 3. Regional Excellence: 15%\n  Average ranking score across affiliated Territories.\n\n• 4. Total Population: 10%\n  Aggregated workforce and residents.\n\nNote: Each metric is scaled dynamically (0.0 to 1.0) against the highest live value in the world economy.\n\n2nd Line: Cap · Biz · Res (Capitalization · Businesses · Population).',
        );

        final colCities = _rankingColumn(
          context,
          'TERRITORIES',
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
              'Territory Ranking Index (0–100):\n\n• 1. Territory Capitalization: 35%\n  Physical capacity and infrastructure equity.\n\n• 2. Infrastructure Coverage: 35%\n  Housing, energy, connectivity & health vs population.\n\n• 3. Commercial Vitality: 20%\n  Active local operating businesses.\n\n• 4. Demographic Population: 10%\n  Settled active residents.\n\nNote: Each metric is scaled dynamically (0.0 to 1.0) against the highest live value in the world economy.\n\n2nd Line: Cap · Biz · Res (Capacity · Businesses · Residents).\n\n3rd Line: Affiliated Corporation.',
        );

        final cockpit = EarthPageCockpit(
          status: 'LIVE CIVIC INDEX',
          statusColor: context.goldColor,
          infoTitle: 'CIVIC RANKINGS & LEADERBOARD ARCHITECTURE',
          infoDescription:
              '• Planetary Index (0–100): Normalized dynamic rating across citizens, dynasties, organizations, and territories evaluated against real-time planetary economy metrics.\n\n• Citizen Index: Personal Legacy (45%) + Civic Standing (35%) + Capitalization (20%).\n\n• Dynastic House Index: Ancestral Inscriptions + Accumulated House Standing + Generational Peak Legacy.\n\n• Organization Index: Total Enterprise Capitalization (45%) + Productive Ecosystem (30%) + Commercial Vitality (15%) + Workforce Population (10%).\n\n• Territory Index: Municipal Capitalization (35%) + Infrastructure Coverage (35%) + Commercial Vitality (20%) + Demographic Population (10%).\n\n• Prestige Tiers: Sovereign (90–100), Patrician (75–89), Pioneer (50–74), Citizen (0–49).',
          title: 'CIVIC RANKINGS',
          subtitle:
              'Global prestige and economic hierarchy across citizens, dynasties, organizations, and territories',
          metrics: [
            CockpitMetric(
              label: 'Citizens',
              value: '${citizens.length}',
              icon: Icons.person_outline,
              color: context.primaryColor,
            ),
            CockpitMetric(
              label: 'Houses',
              value: '${houses.length}',
              icon: Icons.shield_outlined,
              color: context.warningColor,
            ),
            CockpitMetric(
              label: 'Organizations',
              value: '${corp.length}',
              icon: Icons.account_balance_outlined,
              color: context.secondaryColor,
            ),
            CockpitMetric(
              label: 'Territories',
              value: '${cities.length}',
              icon: Icons.location_on_outlined,
              color: context.goldColor,
            ),
          ],
        );

        final contentWidget = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Column 1: Sovereign & Lineage Sphere (Citizens / Dynasties)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin:
                              EdgeInsets.only(bottom: context.spacingControl),
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
                                  isSelected: _leftTab == 0,
                                  onTap: () => setState(() => _leftTab = 0),
                                ),
                              ),
                              Expanded(
                                child: _buildNarrowTabButton(
                                  context,
                                  title: 'HOUSES',
                                  icon: Icons.shield_outlined,
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
                  // Column 2: Institutional & Territorial Sphere (Organizations / Territories)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin:
                              EdgeInsets.only(bottom: context.spacingControl),
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
                                  title: 'ORGANIZATIONS',
                                  icon: Icons.account_balance_outlined,
                                  isSelected: _rightTab == 0,
                                  onTap: () => setState(() => _rightTab = 0),
                                ),
                              ),
                              Expanded(
                                child: _buildNarrowTabButton(
                                  context,
                                  title: 'TERRITORIES',
                                  icon: Icons.location_on_outlined,
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
              )
            : Column(
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
                            isSelected: _singleTab == 0,
                            onTap: () => setState(() => _singleTab = 0),
                          ),
                        ),
                        Expanded(
                          child: _buildNarrowTabButton(
                            context,
                            title: 'HOUSES',
                            icon: Icons.shield_outlined,
                            isSelected: _singleTab == 1,
                            onTap: () => setState(() => _singleTab = 1),
                          ),
                        ),
                        Expanded(
                          child: _buildNarrowTabButton(
                            context,
                            title: 'ORGANIZATIONS',
                            icon: Icons.account_balance_outlined,
                            isSelected: _singleTab == 2,
                            onTap: () => setState(() => _singleTab = 2),
                          ),
                        ),
                        Expanded(
                          child: _buildNarrowTabButton(
                            context,
                            title: 'TERRITORIES',
                            icon: Icons.location_on_outlined,
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cockpit,
            const SizedBox(height: 28),
            contentWidget,
          ],
        );
      },
    );
  }

  Map<String, List<Map<String, dynamic>>> _canonicalMetrics(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in raw.entries) {
      final rows = entry.value is List
          ? (entry.value as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];
      if (rows.isNotEmpty) result[entry.key.toString()] = rows;
    }
    return result;
  }

  Widget _buildCanonicalMetricRankings(
    BuildContext context,
    Map<String, List<Map<String, dynamic>>> metrics,
    dynamic rawGameDay,
    dynamic rulesVersion,
  ) {
    const coreMetricDefinitions = [
      (
        code: 'LEGACY',
        label: 'LEGACY',
        icon: Icons.shield_outlined,
      ),
      (
        code: 'WEALTH',
        label: 'WEALTH',
        icon: Icons.account_balance_wallet_outlined,
      ),
      (
        code: 'PRODUCTIVE_CAPACITY',
        label: 'BUILDINGS',
        icon: Icons.domain_outlined,
      ),
      (
        code: 'TECHNOLOGY',
        label: 'TECHNOLOGY',
        icon: Icons.biotech_outlined,
      ),
    ];

    final availableCore = coreMetricDefinitions
        .where((m) => metrics.containsKey(m.code))
        .toList();
    final activeList = availableCore.isNotEmpty
        ? availableCore
        : metrics.keys
            .map((k) => (
                  code: k,
                  label: k.replaceAll('_', ' '),
                  icon: Icons.leaderboard_outlined,
                ))
            .toList();

    final metricIndex = activeList.isEmpty
        ? 0
        : (_metricTab < activeList.length ? _metricTab : 0);
    final selectedItem = activeList.isEmpty ? null : activeList[metricIndex];
    final selectedCode = selectedItem?.code ?? '';
    final rows = selectedCode.isNotEmpty
        ? (metrics[selectedCode] ?? const <Map<String, dynamic>>[])
        : const <Map<String, dynamic>>[];
    final title = selectedItem?.label ??
        (selectedCode.isEmpty
            ? 'NO SETTLED LEADERBOARDS'
            : selectedCode.replaceAll('_', ' '));
    final gameDay = rawGameDay?.toString() ?? '—';
    final version = rulesVersion?.toString() ?? '—';
    final houseName = (widget.state.human['house_name'] ??
            widget.state.human['houseName'] ??
            widget.state.membership?['house_name'] ??
            widget.state.membership?['houseName'])
        ?.toString();
    final myHouseId = widget.state.human['house_id']?.toString() ??
        widget.state.membership?['house_id']?.toString();
    final myHouse = rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) =>
              row?['subject_id']?.toString() == myHouseId ||
              (houseName != null &&
                  row?['subject_name']?.toString() == houseName),
          orElse: () => null,
        );
    String topPercent(dynamic raw) {
      final value = asDouble(raw);
      if (value == null) return '—';
      if (value >= 99) return 'Top 1%';
      if (value >= 90) return 'Top 10%';
      if (value >= 75) return 'Top 25%';
      return '${value.toStringAsFixed(1)} percentile';
    }

    String description(String code) => switch (code) {
          'WEALTH' =>
            'Total settled House account balances at the latest daily snapshot.',
          'PRODUCTIVE_CAPACITY' =>
            'Active and under-construction buildings owned by the House.',
          'LEGACY' =>
            'The House legacy recorded by the canonical lineage system.',
          'TECHNOLOGY' =>
            'Patents and Corporation technology access attributed to the House.',
          'PUBLIC_GOODS' => 'Settled contributions to public projects.',
          'ORGANIZATION_SCALE' =>
            'Active memberships held by the House in Organizations.',
          'TERRITORY_QUALITY' =>
            'Latest settled service capacity of the House primary Territory.',
          'MARKET_ROLE' => 'Completed market fills associated with the House.',
          _ =>
            'Published House performance dimension from the daily ranking snapshot.',
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthPageCockpit(
          status: activeList.isEmpty ? 'NOT SETTLED' : 'WORLD · RANKINGS',
          statusColor: context.goldColor,
          infoTitle: 'HOW RANKINGS WORK',
          infoDescription:
              'Each leaderboard is an independent, server-settled metric snapshot. Values are not combined into a hidden composite score. Rankings are ordered by the finalized game day. Rules version: $version.',
          title: 'WORLD RANKINGS',
          subtitle:
              'Compare Houses across independent, published performance dimensions.',
          metrics: [
            CockpitMetric(
                label: 'Categories',
                value: '${activeList.length}',
                icon: Icons.stacked_bar_chart_outlined,
                color: context.primaryColor),
            CockpitMetric(
                label: 'Total Houses',
                value:
                    '${widget.state.rankings['populationSize'] ?? (rows.isEmpty ? '—' : rows.first['population_size'] ?? '—')}',
                icon: Icons.shield_outlined,
                color: context.goldColor),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          margin: EdgeInsets.only(bottom: context.spacingControl),
          decoration: BoxDecoration(
            color: context.surfaceColor.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.subtleBorderColor),
          ),
          child: Row(
            children: [
              for (var index = 0; index < activeList.length; index++)
                Expanded(
                  child: _buildNarrowTabButton(
                    context,
                    title: activeList[index].label,
                    icon: activeList[index].icon,
                    isSelected: index == metricIndex,
                    onTap: () {
                      EarthAudioEngine.instance.playClick();
                      setState(() => _metricTab = index);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (myHouse != null || houseName != null) ...[
          Container(
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(
                  color: context.primaryColor.withValues(alpha: .35)),
            ),
            child: Row(children: [
              Icon(Icons.shield_outlined, color: context.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('YOUR HOUSE',
                        style: context.captionStyle
                            .copyWith(color: context.primaryColor)),
                    Text(
                        houseName ??
                            myHouse?['subject_name']?.toString() ??
                            'House',
                        style: context.widgetValueStyle),
                  ])),
              if (myHouse != null)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('#${myHouse['rank'] ?? '—'}',
                      style: context.widgetValueStyle
                          .copyWith(color: context.goldColor)),
                  Text(topPercent(myHouse['percentile']),
                      style: context.captionStyle),
                ]),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        EarthSection(
          title: '',
          showHeader: false,
          showSurface: false,
          child: rows.isEmpty
              ? EarthEmptyState(
                  message: activeList.isEmpty
                      ? 'Rankings are not settled yet. The first snapshot will be published after the next completed daily settlement.'
                      : 'No finalized entries exist for this ranking dimension yet.',
                  icon: Icons.hourglass_empty_outlined)
              : Column(
                  children: [
                    for (final row in rows)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(context.cardPadding),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius:
                              BorderRadius.circular(context.radiusCard),
                          border: Border.all(color: context.subtleBorderColor),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 42,
                                child: Text('#${row['rank'] ?? '—'}',
                                    style: context.widgetValueStyle
                                        .copyWith(color: context.goldColor))),
                            Expanded(
                                child: Text(
                                    row['subject_name']?.toString() ??
                                        row['subject_id']?.toString() ??
                                        'Unknown subject',
                                    style: context.bodyStyle.copyWith(
                                        fontWeight: FontWeight.w700))),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(row['metric_value']?.toString() ?? '0',
                                      style: context.widgetValueStyle),
                                  Text(topPercent(row['percentile']),
                                      style: context.captionStyle),
                                ]),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        if (selectedCode.isNotEmpty)
          Text(description(selectedCode), style: context.widgetFooterStyle),
      ],
    );
  }

  Widget _buildNarrowTabButton(
    BuildContext context, {
    required String title,
    required IconData icon,
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
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                size: 14,
                color: isSelected ? context.primaryColor : context.mutedColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.controlStyle.copyWith(
                    color:
                        isSelected ? context.primaryColor : context.mutedColor,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
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
      return asIntOr(c['capitalization'], treasury);
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
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EarthEmptyState(
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
      if (row['compositeIndex'] != null) {
        return asIntOr(row['compositeIndex'], 0);
      }
      if (row['score'] != null && asIntOr(row['score'], 0) <= 100) {
        return asIntOr(row['score'], 0);
      }

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
        final nConnectivity =
            ((connectivity / (residents > 0 ? residents : 1.0)) / maxC)
                .clamp(0.0, 1.0);
        final nHealth = (health / maxHl).clamp(0.0, 1.0);
        final nTreasury = (treasury / maxCityTr).clamp(0.0, 1.0);
        return ((nConnectivity * 40) +
                (nHealth * 40) +
                (nTreasury * 20))
            .round()
            .clamp(0, 100);
      } else if (isHouse) {
        if (row['house_score'] != null) return asIntOr(row['house_score'], 0);
        if (row['dynasty_score'] != null) {
          return asIntOr(row['dynasty_score'], 0);
        }
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
              final capitalization = asIntOr(row['capitalization'], treasury);
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
                    : (rawCorp ??
                        (entityId != null && cityToCorpMap != null
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
              if (founder != null && founder.isNotEmpty && founder != '—') {
                affParts.add('Founder: $founder');
              }
              if (heir != null && heir.isNotEmpty && heir != '—') {
                affParts.add('Heir: $heir');
              }
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
    final myCorp = state.json['corporation'] is Map
        ? Map<String, dynamic>.from(state.json['corporation'] as Map)
        : (state.institutions['corporation'] is Map
            ? Map<String, dynamic>.from(
                state.institutions['corporation'] as Map)
            : const <String, dynamic>{});
    final membership = state.membership ?? const <String, dynamic>{};
    final myCorpId = membership['corporation_id']?.toString() ??
        membership['organization_id']?.toString() ??
        myCorp['id']?.toString();
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
              'Join a corporation to access shared Territories, technologies, contracts, and civic influence. Select any corporation in the directory to inspect its details.',
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
    final pooledCapacity = corporation['v5_occupied_capacity']?.toString();
    final standardUnits = corporation['v5_required_territory_units']?.toString();
    final treasury = asDouble(corporation['treasury']);
    final operatingBudget = asDouble(corporation['operating_budget']);
    final reserve = asDouble(corporation['reserve']);
    final territoryName = corporation['primary_territory_name']?.toString() ??
        corporation['territory_name']?.toString() ??
        'Primary Territory';

    final sharedPatents = corporation['shared_patents'] is List
        ? corporation['shared_patents'] as List
        : const <dynamic>[];

    final isAffiliated = myCorpId != null && myCorpId == id;

    final incomeTaxBps = asInt(corporation['income_tax_bps']);
    final salesTaxBps = asInt(corporation['sales_tax_bps']);
    final corporateTaxBps = asInt(corporation['corporate_tax_bps']);

    String formatRate(int? bps) =>
        bps == null || bps < 0 ? 'UNAVAILABLE' : '${(bps / 100).toStringAsFixed(1)}%';

    final rawGovProposals = state.governance['proposals'];
    final corpProposalsCount =
        (rawGovProposals is List ? rawGovProposals : const [])
            .where((raw) {
      if (raw is! Map) return false;
      final pInst = (raw['institution_id'] ?? raw['institutionId'])?.toString();
      return pInst == id;
    }).length;

    final cockpit = EarthPageCockpit(
      status: isAffiliated ? 'AFFILIATED ENTERPRISE' : 'CHARTERED ENTERPRISE',
      statusColor: isAffiliated ? context.successColor : context.primaryColor,
      infoTitle: 'CORPORATE GOVERNANCE & COMMONS ARCHITECTURE',
      infoDescription:
          '• Chartered Governance: Corporations establish versioned bylaws, taxation rates, and future-effective governance changes.\n\n• Pooled Capacity: Affiliated Houses and public infrastructure consume shared capacity, with standardized units calculated automatically.\n\n• Corporate Treasury & Commons: Distinct institutional CREDIT accounts fund public infrastructure, research, shared patents, and collective expansion.',
      title: name.toUpperCase(),
      subtitle:
          'Chartered corporate governance, Territory infrastructure, and shared enterprise commons across Earth',
      metrics: [
        CockpitMetric(
          label: 'Members',
          value: '$memberCount',
          icon: Icons.groups_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Occupied capacity',
          value: pooledCapacity ?? 'UNAVAILABLE',
          icon: Icons.stacked_bar_chart_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Standard units',
          value: standardUnits ?? 'UNAVAILABLE',
          icon: Icons.layers_outlined,
          color: context.goldColor,
        ),
        CockpitMetric(
          label: 'Proposals',
          value: '$corpProposalsCount',
          icon: Icons.how_to_vote_outlined,
          color: context.goldColor,
        ),
        CockpitMetric(
          label: 'Patents',
          value: '${sharedPatents.length}',
          icon: Icons.science_outlined,
          color: context.successColor,
        ),
      ],
    );

    return EarthSection(
      title: 'CORPORATION',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Corporation membership determines which shared rules, Territories, technologies, contracts, and services are available to you.',
            'Corporation capacity is pooled; standardized Territory units are calculated from the occupied footprint.',
        'Independent people use Earth default rules and do not participate in corporation decisions.',
        'Corporate Budget: the Corporation treasury funds public infrastructure, services, research, and corporate projects.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cockpit,
          const SizedBox(height: 18),
          CorporationTerritorySection(corporationId: id),
          const SizedBox(height: 28),
          OrganizationPeopleRolesPanel(organizationId: 'ORG-CORP-$id'),
          const SizedBox(height: 28),
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
                        value: (corporation['admission_policy'] ?? 'UNKNOWN')
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
                        label: 'TERRITORIES',
                        value:
                            '${corporation['territory_count'] ?? 'UNAVAILABLE'}',
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
                      _buildAttributeRow(
                        context,
                        icon: Icons.settings_suggest_outlined,
                        label: 'OPERATING BUDGET',
                        value: operatingBudget == null
                            ? 'UNAVAILABLE'
                            : '${formatWholeNumber(operatingBudget)} C',
                        accentColor: context.secondaryColor,
                      ),
                      _buildAttributeRow(
                        context,
                        icon: Icons.shield_outlined,
                        label: 'RESERVE',
                        value: reserve == null
                            ? 'UNAVAILABLE'
                            : '${formatWholeNumber(reserve)} C',
                        accentColor: context.successColor,
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
                'Corporation CREDIT accounts are separated into treasury, operating budget, and reserve. Corporations do not hold player resources.',
            accent: context.warningColor,
          ),
          const SizedBox(height: 12),
          _institutionFinanceClarityCard(
            context,
            institution: corporation,
            projection: corporation['financial_projection'] is Map
                ? Map<String, dynamic>.from(
                    corporation['financial_projection'] as Map)
                : const <String, dynamic>{},
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
                    '${formatRate(corporateTaxBps)} on affiliated business revenues\nAllocated directly to the corporate treasury to fund public goods and research. Parent Earth ceiling: governed by the active Earth tax rule.',
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
                    '${formatRate(salesTaxBps)} transaction fee on local commodity and machine trades.',
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
                    '${formatRate(incomeTaxBps)} income levy on worker wages and personal distributions.',
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
                    'Current policy: ${(corporation['admission_policy'] ?? 'UNKNOWN').toString().toUpperCase()}. Admission consequences are determined by the corporation charter.',
                leading: Icon(Icons.how_to_reg_outlined,
                    size: context.iconSize, color: context.secondaryColor),
                badges: [
                  EarthBadge(
                    label: (corporation['admission_policy'] ?? 'UNKNOWN')
                                .toString()
                                .toLowerCase() ==
                            'open'
                        ? 'EARTH DEFAULT'
                        : 'CUSTOM OVERRIDE',
                    variant: (corporation['admission_policy'] ?? 'UNKNOWN')
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
                    'Active Corporation Executives hold statutory authority to govern assigned Territories and introduce governance proposals.',
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
            'Choose belonging · compare Territories · support or challenge corporation rules · use shared technology · build a business network · move when another Territory offers a better future.',
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
                    label: 'FORM CORPORATION',
                    icon: Icons.add_business_outlined,
                    variant: EarthButtonVariant.primary,
                    onPressed: busy
                        ? null
                        : () => showFormationComposer(
                              context,
                              action ?? ((_) async {}),
                              territoryName: territoryName,
                            ),
                  ),
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
                            const EarthApi().joinV5Corporation(corporationId: id)),
                  ),
                ],
              ],
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

class CorporationTerritorySection extends StatefulWidget {
  final String corporationId;

  const CorporationTerritorySection({super.key, required this.corporationId});

  @override
  State<CorporationTerritorySection> createState() =>
      _CorporationTerritorySectionState();
}

Widget _capacityAttributeRow(
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

class _CorporationTerritorySectionState
    extends State<CorporationTerritorySection> {
  late Future<Map<String, dynamic>> _territories;
  late Future<Map<String, dynamic>> _capacity;

  @override
  void initState() {
    super.initState();
    _territories =
        const EarthApi().listCorporationTerritories(widget.corporationId);
    _capacity = const EarthApi().getV5CorporationCapacity(widget.corporationId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _territories,
      builder: (context, snapshot) {
        final rows = snapshot.data?['territories'] is List
            ? (snapshot.data!['territories'] as List).whereType<Map>().toList()
            : const <Map>[];
        return FutureBuilder<Map<String, dynamic>>(
          future: _capacity,
          builder: (context, capacitySnapshot) {
            final capacity = capacitySnapshot.data?['capacity'] is Map
                ? Map<String, dynamic>.from(
                    capacitySnapshot.data!['capacity'] as Map)
                : const <String, dynamic>{};
            final occupied = capacity['totalOccupiedUnits']?.toString() ??
                capacity['total_occupied_units']?.toString();
            final standard = capacity['standardTerritoryCapacity']?.toString() ??
                capacity['standard_territory_capacity']?.toString();
            final required = capacity['requiredTerritoryUnits']?.toString() ??
                capacity['required_territory_units']?.toString();
            final residential = capacity['residentialUnits']?.toString() ??
                capacity['residential_units']?.toString();
            final privateUnits = capacity['privateBuildingUnits']?.toString() ??
                capacity['private_building_units']?.toString();
            final publicUnits = capacity['publicBuildingUnits']?.toString() ??
                capacity['public_building_units']?.toString();
            final denominator = int.tryParse(
                capacity['utilizationDenominator']?.toString() ??
                    capacity['utilization_denominator']?.toString() ??
                    '0');
            final numerator = int.tryParse(
                capacity['utilizationNumerator']?.toString() ??
                    capacity['utilization_numerator']?.toString() ??
                    '0');
            final utilization = denominator != null && denominator > 0
                ? '${((numerator ?? 0) * 100 / denominator).toStringAsFixed(1)}%'
                : 'UNAVAILABLE';

            return EarthSection(
          title: 'CORPORATION CAPACITY',
          showSurface: true,
          infoBulletPoints: const [
            'Corporation capacity is pooled across affiliated Houses and public infrastructure.',
            'Standardized Territory units are calculated automatically from occupied capacity.',
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (capacitySnapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator()
              else if (capacity.isEmpty)
                Text('V5 capacity is not available yet.',
                    style: context.widgetFooterStyle)
              else ...[
                _capacityAttributeRow(context,
                    icon: Icons.stacked_bar_chart_outlined,
                    label: 'OCCUPIED CAPACITY',
                    value: occupied ?? 'UNAVAILABLE',
                    accentColor: context.primaryColor),
                _capacityAttributeRow(context,
                    icon: Icons.home_outlined,
                    label: 'MEMBER RESIDENTIAL',
                    value: residential ?? 'UNAVAILABLE',
                    accentColor: context.secondaryColor),
                _capacityAttributeRow(context,
                    icon: Icons.business_outlined,
                    label: 'PRIVATE / PUBLIC FOOTPRINT',
                    value: '${privateUnits ?? '—'} / ${publicUnits ?? '—'}',
                    accentColor: context.goldColor),
                _capacityAttributeRow(context,
                    icon: Icons.layers_outlined,
                    label: 'STANDARD UNITS',
                    value: '${required ?? '—'} × ${standard ?? '—'} capacity',
                    accentColor: context.primaryColor),
                _capacityAttributeRow(context,
                    icon: Icons.speed_outlined,
                    label: 'UTILIZATION',
                    value: utilization,
                    accentColor: context.successColor),
              ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('COMPATIBILITY TERRITORY RECORDS',
                    style: context.widgetFooterStyle),
                ...rows.map((row) {
                  final name = row['name']?.toString() ??
                      row['id']?.toString() ?? 'Territory';
                  final status = row['status']?.toString() ?? 'ACTIVE';
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.map_outlined),
                    title: Text(name),
                    subtitle: Text(
                        '${row['territory_type'] ?? 'TERRITORY'} · $status'),
                  );
                }),
              ],
            ],
          ),
        );
          },
        );
      },
    );
  }
}

class AffiliationRequiredPanel extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const AffiliationRequiredPanel({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return EarthSection(
      title: title,
      showSurface: false,
      infoBulletPoints: const [
        'Affiliation is optional. Independent people can inspect the available institutions and join when they are ready.',
      ],
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.warningColor, size: 22),
            SizedBox(width: context.spacingInline),
            Expanded(
              child: Text(message, style: context.widgetFooterStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class CorporationFormationAccessPanel extends StatelessWidget {
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const CorporationFormationAccessPanel({
    super.key,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthSection(
      title: 'CORPORATION FORMATION',
      showSurface: false,
      infoBulletPoints: const [
        'Corporations are local polities. Capacity and standardized Territory units are calculated automatically after founding.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are not affiliated with a Corporation yet. Found a Corporation to establish its pooled capacity policy and local public budget.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),
          EarthButton(
            label: 'FORM CORPORATION',
            icon: Icons.add_business_outlined,
            variant: EarthButtonVariant.primary,
            onPressed: busy
                ? null
                : () => showFormationComposer(
                      context,
                      action,
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
    final city = state.institutions['territory'] is Map<String, dynamic>
        ? (state.institutions['territory'] as Map<String, dynamic>)
        : state.institutions['city'] is Map<String, dynamic>
            ? (state.institutions['city'] as Map<String, dynamic>)
            : <String, dynamic>{};
    final cityId =
        city['id']?.toString() ?? state.residency['territory_id']?.toString();
    final cityName =
        (city['name']?.toString() ?? 'TERRITORY UNAVAILABLE').toUpperCase();
    final residents = asInt(city['residents']);
    final housingCap = asInt(city['housing_capacity']);
    final energyCap = asInt(city['energy_capacity']);
    final cityFinance = state.json['territoryFinance'] is Map
        ? Map<String, dynamic>.from(state.json['territoryFinance'] as Map)
        : state.json['cityFinance'] is Map
            ? Map<String, dynamic>.from(state.json['cityFinance'] as Map)
            : const <String, dynamic>{};
    final cityResources = cityFinance['resources'] is Map
        ? Map<String, dynamic>.from(cityFinance['resources'] as Map)
        : const <String, dynamic>{};
    final cityTreasury =
        asDouble(cityFinance['treasury']) ?? asDouble(city['treasury']) ?? 0.0;
    final cityBuildings = state.buildings
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where(
          (building) =>
              (building['territory_id']?.toString() == cityId ||
                  building['city_id']?.toString() == cityId) &&
              building['ownership_class']?.toString() == 'civic' &&
              building['status']?.toString() == 'active',
        )
        .toList();
    final cityDailyIncome = _dailyCityIncome(cityBuildings);
    final cityCashflow = cityFinance['dailyCashflow'] is Map
        ? Map<String, dynamic>.from(cityFinance['dailyCashflow'] as Map)
        : const <String, dynamic>{};
    final cityCreditStatement =
        _cityCreditStatement(cityCashflow, cityBuildings);

    final isCityResident = state.residency['territory_id'] != null ||
        state.membership?['territory_id'] != null ||
        state.membership?['city_id'] != null;

    final housingRatio =
        formatPercent(state.world['serviceRatios']?['housing']);
    final energyRatio = formatPercent(state.world['serviceRatios']?['energy']);
    final connectRatio =
        formatPercent(state.world['serviceRatios']?['connectivity']);
    final healthRatio = formatPercent(state.world['serviceRatios']?['health']);
    final cityMembers = state.json['territoryMembers'] is List
        ? List<dynamic>.from(state.json['territoryMembers'] as List)
        : state.json['cityMembers'] is List
            ? List<dynamic>.from(state.json['cityMembers'] as List)
            : const <dynamic>[];
    final playerId = state.human['id']?.toString();
    final standing = asIntOr(state.human['standing'], 0);

    final cockpit = EarthPageCockpit(
      status: isCityResident ? 'RESIDENT CHARTER' : 'MUNICIPAL JURISDICTION',
      statusColor: isCityResident ? context.successColor : context.primaryColor,
      infoTitle: 'MUNICIPAL GOVERNANCE & SERVICES ARCHITECTURE',
      infoDescription:
          '• Service Capacities & Grid: Oversight of public housing, municipal energy distribution, network connectivity, and healthcare coverage.\n\n• Municipal Treasury: Dedicated civic funds designated strictly for municipal maintenance, infrastructure upgrades, and resident subsidies.\n\n• Local Governance & Ordinances: City-level proposals, active municipal statutes, and local council appointments.',
      title: cityName,
      subtitle:
          'Municipal governance, public utility capacity, civic treasury, and resident welfare across Earth',
      metrics: [
        CockpitMetric(
          label: 'Residents',
          value: '$residents',
          icon: Icons.groups_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Treasury',
          value: formatWholeNumber(cityTreasury),
          icon: Icons.account_balance_wallet_outlined,
          color: context.successColor,
        ),
      ],
    );

    return EarthSection(
      key: panelKey,
      title: 'TERRITORIES / SERVICES',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'Municipal Administration & Service Capacity: Oversight of public housing, energy grid, connectivity, and healthcare.',
        'Territory Standing: Civic prestige and influence among resident Houses.',
        'Territory Budget: The territorial treasury pays for civic operations, public services, and explicit resident subsidies.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cockpit,
          const SizedBox(height: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final attributes = [
                    _buildAttributeRow(context,
                        icon: Icons.home_outlined,
                        label: 'HOUSING',
                        value: housingRatio,
                        accentColor: context.primaryColor),
                    _buildAttributeRow(context,
                        icon: Icons.bolt_outlined,
                        label: 'ENERGY',
                        value: energyRatio,
                        accentColor: context.primaryColor),
                    _buildAttributeRow(context,
                        icon: Icons.hub_outlined,
                        label: 'CONNECTIVITY',
                        value: connectRatio,
                        accentColor: context.primaryColor),
                    _buildAttributeRow(context,
                        icon: Icons.local_hospital_outlined,
                        label: 'HEALTHCARE',
                        value: healthRatio,
                        accentColor: context.primaryColor),
                    _buildAttributeRow(context,
                        icon: Icons.domain_outlined,
                        label: 'HOUSING CAPACITY',
                        value: '$housingCap',
                        accentColor: context.secondaryColor),
                    _buildAttributeRow(context,
                        icon: Icons.workspace_premium_outlined,
                        label: 'TERRITORY STANDING',
                        value: '$standing',
                        accentColor: context.goldColor),
                    _buildAttributeRow(context,
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'TERRITORY BUDGET',
                        value: '${formatWholeNumber(cityTreasury)} C',
                        accentColor: context.warningColor),
                  ];
                  if (constraints.maxWidth < 520) {
                    return Column(children: attributes);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Column(children: attributes.take(4).toList())),
                      const SizedBox(width: 24),
                      Expanded(
                          child: Column(children: attributes.skip(4).toList())),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _institutionBudgetCard(
                context,
                title: 'TERRITORY BUDGET',
                amount: '${formatWholeNumber(cityTreasury)} C',
                icon: Icons.account_balance_wallet_outlined,
                description:
                    'Municipal funds for civic buildings, public services, maintenance, and explicitly approved resident subsidies. This is separate from personal and corporate money.',
                accent: context.warningColor,
              ),
              const SizedBox(height: 12),
              _institutionFinanceClarityCard(
                context,
                institution: city,
                projection: cityFinance,
              ),
              SizedBox(height: context.spacingTitleOffset),
              Text('TERRITORY RESERVES', style: context.topicTitleStyle),
              SizedBox(height: context.spacingControl),
              _resourceSummary(context, cityResources, credits: cityTreasury),
              SizedBox(height: context.spacingTitleOffset),
              Text('DAILY TERRITORY INCOME', style: context.topicTitleStyle),
              SizedBox(height: context.spacingControl),
              _resourceSummary(context, cityDailyIncome, signed: true),
              const SizedBox(height: 12),
              _cityCreditIncomeCard(context, cityCreditStatement),
              SizedBox(height: context.spacingTitleOffset),
            ],
          ),
          if (isCityResident && cityMembers.isNotEmpty) ...[
            SizedBox(height: context.spacingTitleOffset),
            Text('TERRITORY STANDING', style: context.topicTitleStyle),
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

  static Map<String, double> _dailyCityIncome(
      Iterable<Map<String, dynamic>> buildings) {
    final totals = <String, double>{
      'credits': 0,
      'energy': 0,
      'food': 0,
      'materials': 0,
      'components': 0,
      'compute': 0,
    };
    for (final building in buildings) {
      final outputMultiplier = asDoubleOr(building['output_multiplier'], 1.0);
      final costMultiplier = asDoubleOr(building['cost_multiplier'], 1.0);
      for (final resource in totals.keys) {
        var output = asDoubleOr(building['output_$resource'], 0);
        if (output == 0 &&
            building['resource_output_type']?.toString() == resource) {
          output = asDoubleOr(building['resource_output_amount'], 0);
        }
        var operating = asDoubleOr(building['operating_$resource'], 0);
        if (resource == 'credits' && operating == 0) {
          operating = asDoubleOr(building['daily_operating_credits'], 0);
        }
        final upkeep = asDoubleOr(building['upkeep_$resource'], 0);
        totals[resource] = (totals[resource] ?? 0) +
            output * outputMultiplier -
            (upkeep + operating) * costMultiplier;
      }
    }
    return totals;
  }

  static Map<String, double> _cityCreditStatement(
      Map<String, dynamic> cashflow, Iterable<Map<String, dynamic>> buildings) {
    var civicBuildingIncome = 0.0;
    var buildingCosts = 0.0;
    for (final building in buildings) {
      final outputMultiplier = asDoubleOr(building['output_multiplier'], 1.0);
      final costMultiplier = asDoubleOr(building['cost_multiplier'], 1.0);
      var output = asDoubleOr(building['output_credits'], 0);
      if (output == 0 &&
          (building['resource_output_type']?.toString() == 'credits' ||
              building['resource_output_type'] == null)) {
        output = asDoubleOr(building['resource_output_amount'], 0);
      }
      final operating = asDoubleOr(building['operating_credits'], 0) == 0
          ? asDoubleOr(building['daily_operating_credits'], 0)
          : asDoubleOr(building['operating_credits'], 0);
      civicBuildingIncome += output * outputMultiplier;
      buildingCosts += (asDoubleOr(building['upkeep_credits'], 0) + operating) *
          costMultiplier;
    }
    final cityTaxes = asDoubleOr(cashflow['city_taxes'], 0);
    final investmentIncome = asDoubleOr(cashflow['bank_deposit_interest'], 0);
    final residentDividends = asDoubleOr(cashflow['corporation_income_tax'], 0);
    final civicBuildings = civicBuildingIncome - buildingCosts;
    final gross = civicBuildings + cityTaxes + investmentIncome;
    return {
      'civicBuildingIncome': civicBuildings,
      'cityTaxes': cityTaxes,
      'investmentIncome': investmentIncome,
      'gross': gross,
      'buildingCosts': buildingCosts,
      'residentDividends': residentDividends,
      'net': gross - residentDividends,
    };
  }

  static Widget _cityCreditIncomeCard(
          BuildContext context, Map<String, double> statement) =>
      CreditIncomeSummaryCard(
        grossItems: [
          CreditIncomeLineItem(
              'Civic buildings', statement['civicBuildingIncome'] ?? 0),
          CreditIncomeLineItem(
              'City taxes received', statement['cityTaxes'] ?? 0),
          CreditIncomeLineItem(
              'Bank deposit interest', statement['investmentIncome'] ?? 0),
        ],
        deductionItems: [
          CreditIncomeLineItem(
              'Corporation income tax', statement['residentDividends'] ?? 0),
        ],
      );

  static Widget _resourceSummary(
      BuildContext context, Map<String, dynamic> values,
      {double? credits, bool signed = false}) {
    const resources = [
      ('credits', Icons.account_balance_wallet_outlined),
      ('energy', Icons.bolt_rounded),
      ('food', Icons.eco_outlined),
      ('materials', Icons.terrain_outlined),
      ('components', Icons.precision_manufacturing_outlined),
      ('compute', Icons.memory_rounded),
    ];
    return Center(
        child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: resources.map((item) {
        final value = item.$1 == 'credits'
            ? (credits ?? asDoubleOr(values[item.$1], 0))
            : asDoubleOr(values[item.$1], 0);
        final prefix = signed && value > 0
            ? '+'
            : value < 0
                ? '-'
                : '';
        final color = signed
            ? (value < 0
                ? context.errorColor
                : value > 0
                    ? context.successColor
                    : context.mutedColor)
            : EarthResourceMeta.forCommodity(item.$1).color;
        return SizedBox(
          width: 78,
          child: Column(children: [
            Icon(item.$2,
                size: 17, color: EarthResourceMeta.forCommodity(item.$1).color),
            const SizedBox(height: 3),
            Text('$prefix${formatWholeNumber(value.abs())}',
                style: context.bodyStyle.copyWith(
                    color: color, fontWeight: FontWeight.w800, fontSize: 12)),
            Text(item.$1.toUpperCase(),
                style: context.captionStyle.copyWith(fontSize: 8)),
          ]),
        );
      }).toList(),
    ));
  }
}

class CityImpactPanel extends StatelessWidget {
  final EarthState state;

  const CityImpactPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final city = state.institutions['territory'] is Map
        ? Map<String, dynamic>.from(state.institutions['territory'] as Map)
        : state.institutions['city'] is Map
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

    return EarthSection(
      title: 'TERRITORY EFFECTS / LIFE & BUSINESS',
      showSurface: false,
      infoBulletPoints: const [
        'Territory conditions affect your life and businesses through services, taxes, workforce quality, and operating costs.',
        'Pressure above the territory baseline can increase friction and reduce service reliability.',
        'Values marked unavailable require current territory or business data; they are not estimates.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            city['name'] == null
                ? 'No territory effect is currently reported.'
                : 'Living in ${city['name']} changes your services, costs, and opportunities.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingTitleOffset),
          EarthMetricGrid(
            metrics: [
              EarthMetricTile(
                label: 'TERRITORY PRESSURE',
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
                label: 'TERRITORY TAX',
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
          Text('TERRITORY ORDINANCES & TARIFFS',
              style: context.widgetTitleStyle),
          const SizedBox(height: 4),
          Text(
            'Local ordinances and service tariffs set by this territory. Restricted by Organization Charters and Earth Law.',
            style: context.widgetFooterStyle,
          ),
          SizedBox(height: context.spacingControl),
          EarthDataList(
            children: [
              EarthDataRow(
                title: 'Municipal Energy & Grid Tariff',
                subtitle:
                    '${taxRate == null ? 'UNAVAILABLE' : (taxRate * 100).toStringAsFixed(1)}% consumption tariff\nApplied to territory energy grid load and infrastructure utility draws.',
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
  final EarthApi communityApi;
  final ValueChanged<String>? onNavigate;

  const CommunitiesPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
    this.communityApi = const EarthApi(),
    this.onNavigate,
  });

  @override
  State<CommunitiesPanel> createState() => _CommunitiesPanelState();
}

class _CommunitiesPanelState extends State<CommunitiesPanel> {
  String _activeFilter =
      'ALL'; // 'ALL', 'MY_COMMUNITIES', 'PENDING', 'OPEN_TO_JOIN'
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
    int pendingCount = 0;
    int openCount = 0;

    for (final c in activeCommunities) {
      final viewer = c['viewer'] is Map
          ? Map<String, dynamic>.from(c['viewer'] as Map)
          : const <String, dynamic>{};
      final myRole = viewer['role']?.toString();
      final myRequestStatus = viewer['requestStatus']?.toString();
      final isOwner = myRole == 'OWNER';
      final isAdmin = myRole == 'MODERATOR';
      final isMember = isOwner || isAdmin || myRole == 'MEMBER';
      final isPending = myRequestStatus == 'PENDING';

      if (isMember) {
        myCount++;
      }
      if (isPending) {
        pendingCount++;
      }
      if (viewer['canJoin'] == true) {
        openCount++;
      }
    }

    final filteredList = activeCommunities.where((c) {
      final viewer = c['viewer'] is Map
          ? Map<String, dynamic>.from(c['viewer'] as Map)
          : const <String, dynamic>{};
      final myRole = viewer['role']?.toString();
      final myRequestStatus = viewer['requestStatus']?.toString();
      final isOwner = myRole == 'OWNER';
      final isAdmin = myRole == 'MODERATOR';
      final isMember = isOwner || isAdmin || myRole == 'MEMBER';
      final isPending = myRequestStatus == 'PENDING';
      final name = c['name']?.toString() ?? '';
      final searchText = [
        name,
        c['description']?.toString() ?? '',
        c['founder_house_name']?.toString() ?? '',
      ].join(' ').toLowerCase();

      if (_activeFilter == 'MY_COMMUNITIES' && !isMember) {
        return false;
      }
      if (_activeFilter == 'PENDING' && !isPending) {
        return false;
      }
      if (_activeFilter == 'OPEN_TO_JOIN' && viewer['canJoin'] != true) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !searchText.contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    final totalCount = filteredList.length;
    final totalPages = math.max(1, (totalCount / _pageSize).ceil());
    final safePage = _page.clamp(0, totalPages - 1);
    final pageItems =
        filteredList.skip(safePage * _pageSize).take(_pageSize).toList();

    final cockpit = EarthPageCockpit(
      status: 'CIVIC NETWORK',
      statusColor: context.primaryColor,
      infoTitle: 'HOW COMMUNITIES WORK',
      infoDescription:
          '• Civic Communities: Voluntary associations for social, cultural, and professional coordination.\n\n• House Membership: Your House remains affiliated across Human succession; the current Human acts and speaks for the House.\n\n• Cross-World Belonging: Communities are independent associations spanning organizations and Territories on Earth, without a treasury or economic settlement.',
      title: 'COMMUNITIES & GUILDS',
      subtitle:
          'Grassroots civic associations, trade guilds, and mutual aid cooperatives across Earth',
      metrics: [
        CockpitMetric(
          label: 'Network',
          value: '${activeCommunities.length}',
          icon: Icons.groups_outlined,
          color: context.primaryColor,
          onTap: () => setState(() {
            _activeFilter = 'ALL';
            _page = 0;
          }),
        ),
        CockpitMetric(
          label: 'My Communities',
          value: '$myCount',
          icon: Icons.how_to_reg_outlined,
          color: context.secondaryColor,
          onTap: () => setState(() {
            _activeFilter = _activeFilter == 'MY_COMMUNITIES' ? 'ALL' : 'MY_COMMUNITIES';
            _page = 0;
          }),
        ),
        CockpitMetric(
          label: 'Pending',
          value: '$pendingCount',
          icon: Icons.hourglass_top_outlined,
          color: context.warningColor,
          onTap: () => setState(() {
            _activeFilter = _activeFilter == 'PENDING' ? 'ALL' : 'PENDING';
            _page = 0;
          }),
        ),
        CockpitMetric(
          label: 'Open to Join',
          value: '$openCount',
          icon: Icons.lock_open_outlined,
          color: context.successColor,
          onTap: () => setState(() {
            _activeFilter = _activeFilter == 'OPEN_TO_JOIN' ? 'ALL' : 'OPEN_TO_JOIN';
            _page = 0;
          }),
        ),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = EarthSearchInput(
                    controller: _searchController,
                    hintText: 'Search communities by name or purpose...',
                    onChanged: (value) => setState(() {
                      _searchQuery = value.trim();
                      _page = 0;
                    }),
                    onClear: () => setState(() {
                      _searchQuery = '';
                      _page = 0;
                    }),
                  );
                  final found = EarthButton(
                    label: '+ FOUND COMMUNITY',
                    icon: Icons.add_business_outlined,
                    onPressed: widget.busy
                        ? null
                        : () => showCommunityComposer(context, widget.action,
                            api: widget.communityApi),
                  );
                  if (constraints.maxWidth < 460) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [search, const SizedBox(height: 10), found],
                    );
                  }
                  return Row(children: [
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    found,
                  ]);
                },
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
                    label: 'OPEN TO JOIN ($openCount)',
                    isSelected: _activeFilter == 'OPEN_TO_JOIN',
                    onTap: () => setState(() {
                      _activeFilter = 'OPEN_TO_JOIN';
                      _page = 0;
                    }),
                  ),
                  if (_activeFilter == 'MY_COMMUNITIES')
                    _filterChip(
                      label: 'MY COMMUNITIES ($myCount)',
                      isSelected: true,
                      onTap: () => setState(() {
                        _activeFilter = 'ALL';
                        _page = 0;
                      }),
                    ),
                  if (_activeFilter == 'PENDING')
                    _filterChip(
                      label: 'PENDING ($pendingCount)',
                      isSelected: true,
                      onTap: () => setState(() {
                        _activeFilter = 'ALL';
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
                              : (_activeFilter == 'PENDING'
                                  ? 'You have no pending community applications.'
                                  : 'No communities registered yet. You can found the first one.'))),
                  icon: Icons.groups_outlined,
                )
              else ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: pageItems.map((community) {
                    final id = community['id']?.toString() ?? '';
                    final name = community['name']?.toString() ?? '';
                    final founderName =
                        community['founder_house_name']?.toString() ??
                            'Unknown House';
                    final description =
                        community['description']?.toString() ?? '';
                    final admissionPolicy =
                        (community['join_policy']?.toString() ?? 'OPEN')
                            .toUpperCase();
                    final viewer = community['viewer'] is Map
                        ? Map<String, dynamic>.from(community['viewer'] as Map)
                        : const <String, dynamic>{};
                    final myRole = viewer['role']?.toString();
                    final myRequestStatus = viewer['requestStatus']?.toString();
                    final isOwner = myRole == 'OWNER';
                    final isAdmin = myRole == 'MODERATOR';
                    final isMember = isOwner || isAdmin || myRole == 'MEMBER';
                    final isPending = myRequestStatus == 'PENDING';
                    final members = asIntOr(community['member_count'], 0);

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
                                  ? context.primaryColor.withValues(alpha: .35)
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
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: context.widgetFooterStyle,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'MEMBERS: $members  ·  ADMISSION: $admissionPolicy',
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
                                  height: 1, color: context.subtleBorderColor),
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
                                      SizedBox(height: context.spacingControl),
                                      Wrap(
                                        alignment: WrapAlignment.start,
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          if (isMember)
                                            EarthButton(
                                              label: 'OPEN COMMUNITY',
                                              icon: Icons.open_in_new,
                                              onPressed: widget.onNavigate ==
                                                      null
                                                  ? null
                                                  : () => widget.onNavigate!(
                                                      'my-community:$id'),
                                            ),
                                          if (isPending) ...[
                                            const EarthBadge(
                                              label: 'REQUEST PENDING',
                                              variant:
                                                  EarthBadgeVariant.warning,
                                            ),
                                          ] else if (viewer['canJoin'] ==
                                              true) ...[
                                            EarthButton(
                                              label:
                                                  admissionPolicy == 'REQUEST'
                                                      ? 'APPLY'
                                                      : 'JOIN',
                                              variant:
                                                  EarthButtonVariant.primary,
                                              onPressed: widget.busy
                                                  ? null
                                                  : () {
                                                      if (admissionPolicy ==
                                                          'REQUEST') {
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
  String? _membersError;
  String? _requestsError;
  String? _loadedCommunityId;
  String? _selectedCommunityId;

  Map<String, dynamic>? get _community {
    if (widget.communityId != null) {
      for (final c in widget.state.communities) {
        if (c is Map && c['id']?.toString() == widget.communityId) {
          return Map<String, dynamic>.from(c);
        }
      }
    }
    final selectedId = _selectedCommunityId;
    if (selectedId != null) {
      for (final c in widget.state.myCommunities) {
        if (c['id']?.toString() == selectedId) return c;
      }
    }
    return widget.state.myCommunities.isNotEmpty
        ? widget.state.myCommunities.first
        : null;
  }

  @override
  void initState() {
    super.initState();
    _selectedCommunityId = widget.communityId ??
        (widget.state.myCommunities.isNotEmpty
            ? widget.state.myCommunities.first['id']?.toString()
            : null);
    _fetchDetails();
  }

  @override
  void didUpdateWidget(covariant MyCommunityPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final comm = _community;
    final currentId = comm?['id']?.toString();
    if (currentId != _loadedCommunityId ||
        oldWidget.communityId != widget.communityId) {
      if (widget.communityId != null) {
        _selectedCommunityId = widget.communityId;
      }
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
      _membersError = null;
      _requestsError = null;
    });

    try {
      final memRes = await const EarthApi().listCommunityMembers(id);
      _members = memRes['members'] as List<dynamic>? ?? [];
    } catch (_) {
      _members = [];
      _membersError = 'Could not load the member roster.';
    }

    try {
      final admissionPolicy =
          (myComm['join_policy']?.toString() ?? 'OPEN').toUpperCase();
      final viewer = myComm['viewer'] is Map
          ? Map<String, dynamic>.from(myComm['viewer'] as Map)
          : const <String, dynamic>{};
      final myRole = viewer['role']?.toString();
      final isElevated = myRole == 'OWNER' || myRole == 'MODERATOR';

      if (viewer['canApproveRequests'] == true &&
          admissionPolicy == 'REQUEST') {
        final reqRes = await const EarthApi().listCommunityRequests(id);
        _requests = reqRes['requests'] as List<dynamic>? ?? [];
      } else {
        _requests = [];
      }
    } catch (_) {
      _requests = [];
      _requestsError = 'Could not load admission requests.';
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
        child: const EarthEmptyState(
          message: 'You are not currently an owner or member of any community.',
          icon: Icons.groups_outlined,
        ),
      );
    }

    final id = myComm['id']?.toString() ?? '';
    final name = myComm['name']?.toString() ?? '';
    final founderName =
        myComm['founder_house_name']?.toString() ?? 'Unknown House';
    final description = myComm['description']?.toString() ?? '';
    final admissionPolicy =
        (myComm['join_policy']?.toString() ?? 'OPEN').toUpperCase();
    final viewer = myComm['viewer'] is Map
        ? Map<String, dynamic>.from(myComm['viewer'] as Map)
        : const <String, dynamic>{};
    final myRole = viewer['role']?.toString();
    final isOwner = myRole == 'OWNER';
    final isAdmin = myRole == 'MODERATOR';
    final memberCount = asIntOr(myComm['member_count'], _members.length);

    final statusText = isOwner
        ? 'FOUNDER'
        : isAdmin
            ? 'MODERATOR'
            : 'MEMBER';
    final statusColor =
        isOwner || isAdmin ? context.primaryColor : context.successColor;

    final cockpit = EarthPageCockpit(
      status: statusText,
      statusColor: statusColor,
      infoTitle: 'ABOUT COMMUNITIES',
      infoDescription:
          '• Civic Guilds & Cooperatives: Grassroots voluntary associations formed by citizens for collective mutual aid, cultural affinity, industry cooperation, and shared services.\n\n• Admission & Membership: Open or approval-based membership with shared governance rights.',
      title: name.toUpperCase(),
      subtitle: description.isNotEmpty ? description : null,
      actions: [
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
      ],
      metrics: [
        CockpitMetric(
          label: 'Members',
          value: '$memberCount',
          icon: Icons.groups_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Admission',
          value: admissionPolicy,
          icon: Icons.policy_outlined,
          color: context.secondaryColor,
        ),
      ],
      metricWidgets: [
        InkWell(
          onTap: () {
            if (widget.onNavigate != null) {
              widget.onNavigate!('messages:channel-community-$id');
            } else {
              showCommLinkDialog(
                context,
                state: widget.state,
                initialChannelId: 'channel-community-$id',
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.primaryColor.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_outlined,
                        size: 10, color: context.primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'COMMUNICATION',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                        color: context.mutedColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'COMMUNITY CHAT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.primaryColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return EarthSection(
      key: widget.panelKey,
      title: name.toUpperCase(),
      showSurface: false,
      showHeader: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.communityId == null &&
              widget.state.myCommunities.length > 1) ...[
            Text('YOUR COMMUNITIES', style: context.topicTitleStyle),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: id,
              decoration: const InputDecoration(
                labelText: 'Select a community',
                border: OutlineInputBorder(),
              ),
              items: widget.state.myCommunities.map((community) {
                final communityId = community['id']?.toString() ?? '';
                return DropdownMenuItem<String>(
                  value: communityId,
                  child: Text(community['name']?.toString() ?? communityId),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedCommunityId = value);
                _fetchDetails();
              },
            ),
            const SizedBox(height: 18),
          ],
          cockpit,
          // 4. Pending Review Requests (if founder/admin and requests exist)
          if ((isOwner || isAdmin) && _requestsError != null) ...[
            const SizedBox(height: 24),
            EarthDataRow(
              title: 'Admission requests unavailable',
              subtitle: _requestsError!,
              leading: Icon(Icons.error_outline, color: context.warningColor),
              trailing: EarthButton(
                label: 'RETRY',
                onPressed: _loading ? null : _fetchDetails,
              ),
            ),
          ],
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
                'MEMBER ROSTER',
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
          _membersError != null
              ? EarthDataRow(
                  title: 'Member roster unavailable',
                  subtitle: _membersError!,
                  leading:
                      Icon(Icons.error_outline, color: context.warningColor),
                  trailing: EarthButton(
                    label: 'RETRY',
                    onPressed: _loading ? null : _fetchDetails,
                  ),
                )
              : _members.isEmpty
                  ? const EarthEmptyState(
                      message: 'No other members have joined yet.',
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
                        final isMAdmin = role == 'ADMIN' || role == 'MODERATOR';
                        final joinedGameDay = asIntOr(m['joined_game_day'], 1);
                        final joinedYear = ((joinedGameDay - 1) ~/ 365) + 1;
                        final joinedDay = ((joinedGameDay - 1) % 365) + 1;

                        return EarthDataRow(
                          title: hName,
                          subtitle:
                              'Joined on Year $joinedYear, Day $joinedDay',
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
                              label: isMFounder
                                  ? 'FOUNDER'
                                  : isMAdmin
                                      ? 'MODERATOR'
                                      : 'MEMBER',
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
                                                targetHouseId: hId,
                                                role: 'MEMBER',
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
                                                targetHouseId: hId,
                                                role: 'MODERATOR',
                                              );
                                              _fetchDetails();
                                            },
                                    )
                              : null,
                        );
                      }).toList(),
                    ),
          if (!isOwner) ...[
            const SizedBox(height: 28),
            Container(
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LEAVE COMMUNITY',
                          style: context.widgetTitleStyle.copyWith(
                            color: context.warningColor,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Resign your membership in this community. You can rejoin or request admission again later.',
                          style: context.widgetFooterStyle.copyWith(
                            color: context.mutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  EarthButton(
                    label: 'LEAVE COMMUNITY',
                    variant: EarthButtonVariant.danger,
                    onPressed: widget.busy
                        ? null
                        : () => _confirmLeave(context, id, name),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OrganizationCapTablePanel extends StatefulWidget {
  final String organizationId;
  final String? assetId;
  final EarthApi? api;
  final VoidCallback? onRefresh;

  const OrganizationCapTablePanel({
    super.key,
    required this.organizationId,
    this.assetId,
    this.api,
    this.onRefresh,
  });

  @override
  State<OrganizationCapTablePanel> createState() =>
      _OrganizationCapTablePanelState();
}

class _OrganizationCapTablePanelState extends State<OrganizationCapTablePanel> {
  bool _isLoading = false;
  Map<String, dynamic>? _ownershipData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCapTable();
  }

  @override
  void didUpdateWidget(covariant OrganizationCapTablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.assetId != widget.assetId) {
      _loadCapTable();
    }
  }

  Future<void> _loadCapTable() async {
    if (widget.api == null || widget.organizationId.isEmpty) return;
    final assetId = widget.assetId ?? '1';
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.api!.getAssetOwnership(
        organizationId: widget.organizationId,
        assetId: assetId,
      );
      setState(() {
        _ownershipData = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showSubscribeDialog(BuildContext context) async {
    final unitsCtrl = TextEditingController(text: '100');
    final priceCtrl = TextEditingController(text: '100');
    final assetId = widget.assetId ?? '1';

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('SUBSCRIBE TO SHARE ISSUANCE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Organization: ${widget.organizationId}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: unitsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Share Units (Basis points / units)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total Price (CREDIT)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Capital subscription moves CREDIT into the Organization operations account and issues fractional equity units.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () async {
              final units = unitsCtrl.text.trim();
              final price = priceCtrl.text.trim();
              if (units.isEmpty || price.isEmpty) return;
              Navigator.of(dialogCtx).pop();
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _isLoading = true);
              try {
                await widget.api!.subscribeToAssetOwnership(
                  organizationId: widget.organizationId,
                  assetId: assetId,
                  units: units,
                  priceUnits: price,
                  sourceAccountId: '1',
                );
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('Subscription completed successfully')),
                  );
                  _loadCapTable();
                  widget.onRefresh?.call();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text('Subscription failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('SUBSCRIBE'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDistributeDialog(BuildContext context) async {
    final amountCtrl = TextEditingController(text: '1000');
    final assetId = widget.assetId ?? '1';

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('DISTRIBUTE PROPORTIONAL DIVIDEND'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total Distribution Amount (CREDIT)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dividends are paid from Organization Operations account to all registered shareholders according to cap table proportions.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('CANCEL')),
          FilledButton(
            onPressed: () async {
              final amount = amountCtrl.text.trim();
              if (amount.isEmpty) return;
              Navigator.of(dialogCtx).pop();
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _isLoading = true);
              try {
                await widget.api!.distributeOwnership(
                  organizationId: widget.organizationId,
                  assetId: assetId,
                  amountUnits: amount,
                );
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('Dividend distribution executed')),
                  );
                  _loadCapTable();
                  widget.onRefresh?.call();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                        content: Text('Distribution failed: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('EXECUTE DISTRIBUTION'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positions = (_ownershipData?['positions'] as List<dynamic>?) ?? [];
    return EarthSection(
      title: 'CAP TABLE & SHARED OWNERSHIP',
      showSurface: false,
      infoBulletPoints: const [
        'Shared ownership distributes equity positions across member and investor Houses.',
        'Cap table tracks share units, voting weight, and proportional dividend rights.',
        'Dividends distribute real CREDIT ledger balances with integer precision.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading) const LinearProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SHAREHOLDERS & POSITIONS', style: context.topicTitleStyle),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showSubscribeDialog(context),
                    icon: const Icon(Icons.add_chart_outlined, size: 16),
                    label: const Text('SUBSCRIBE'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _showDistributeDialog(context),
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('DISTRIBUTE'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Notice: $_error',
                style: TextStyle(color: context.warningColor))
          else if (positions.isEmpty)
            Text(
                '100% direct founder ownership. No secondary fractional shares issued yet.',
                style: context.widgetFooterStyle)
          else
            ...positions.whereType<Map>().map((p) {
              final owner = p['owner_id']?.toString() ??
                  p['holder_id']?.toString() ??
                  'House';
              final units = p['share_units']?.toString() ?? '0';
              final pct =
                  ((double.tryParse(units) ?? 0) / 100.0).toStringAsFixed(2);
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text('$owner · $pct%',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Units: $units · Rights Class: ${p['rights_class'] ?? 'COMMON'}'),
                  trailing: Text('${p['status'] ?? 'ACTIVE'}'),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class OrganizationContractsPanel extends StatefulWidget {
  final String organizationId;
  final EarthApi? api;
  final VoidCallback? onRefresh;

  const OrganizationContractsPanel({
    super.key,
    required this.organizationId,
    this.api,
    this.onRefresh,
  });

  @override
  State<OrganizationContractsPanel> createState() =>
      _OrganizationContractsPanelState();
}

class _OrganizationContractsPanelState
    extends State<OrganizationContractsPanel> {
  bool _isLoading = false;
  List<dynamic> _contracts = [];
  List<dynamic> _performance = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContracts();
  }

  @override
  void didUpdateWidget(covariant OrganizationContractsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      _loadContracts();
    }
  }

  Future<void> _loadContracts() async {
    if (widget.api == null || widget.organizationId.isEmpty) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.api!
          .listOrganizationContracts(organizationId: widget.organizationId);
      final performanceRes =
          await widget.api!.listContractPerformance(widget.organizationId);
      final list = (res['contracts'] as List<dynamic>?) ?? [];
      setState(() {
        _contracts = list;
        _performance = (performanceRes['performance'] as List<dynamic>?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _performanceAction(String performanceId, String action) async {
    if (widget.api == null) return;
    final note = TextEditingController();
    final units = TextEditingController(text: '1');
    final quality = TextEditingController(text: '10000');
    String resolution = 'ACCEPTED';
    final result = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
            builder: (dialogCtx, setDialogState) => AlertDialog(
                  title: Text(action == 'deliver'
                      ? 'SUBMIT DELIVERY'
                      : action == 'resolve'
                          ? 'RESOLVE DISPUTE'
                          : '${action.toUpperCase()} DELIVERY'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (action == 'deliver') ...[
                      TextField(
                          controller: units,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Delivered units')),
                      TextField(
                          controller: quality,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Quality score (0–10000)')),
                    ],
                    if (action == 'resolve')
                      DropdownButtonFormField<String>(
                          value: resolution,
                          items: const [
                            DropdownMenuItem(
                                value: 'ACCEPTED', child: Text('Accept')),
                            DropdownMenuItem(
                                value: 'FAILED', child: Text('Fail')),
                            DropdownMenuItem(
                                value: 'WAIVED', child: Text('Waive'))
                          ],
                          onChanged: (value) => setDialogState(
                              () => resolution = value ?? resolution)),
                    TextField(
                        controller: note,
                        onChanged: (_) => setDialogState(() {}),
                        maxLines: 3,
                        decoration: const InputDecoration(
                            labelText: 'Evidence / reason')),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: const Text('CANCEL')),
                    FilledButton(
                        onPressed:
                            note.text.trim().isEmpty && action != 'deliver'
                                ? null
                                : () => Navigator.pop(dialogCtx, true),
                        child: const Text('SUBMIT'))
                  ],
                )));
    if (result != true || !mounted) {
      note.dispose();
      units.dispose();
      quality.dispose();
      return;
    }
    try {
      await widget.api!.contractPerformanceAction(
          organizationId: widget.organizationId,
          performanceId: performanceId,
          action: action,
          note: note.text.trim(),
          units: action == 'deliver' ? units.text.trim() : null,
          qualityBps:
              action == 'deliver' ? int.tryParse(quality.text.trim()) : null,
          resolution: action == 'resolve' ? resolution : null);
      await _loadContracts();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Performance action failed: $error')));
      }
    }
    note.dispose();
    units.dispose();
    quality.dispose();
  }

  Future<void> _signContract(String contractId) async {
    if (widget.api == null) return;
    setState(() => _isLoading = true);
    try {
      await widget.api!.signOrganizationContract(
        organizationId: widget.organizationId,
        contractId: contractId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contract signed successfully')),
        );
        _loadContracts();
        widget.onRefresh?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Signing failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCreateContractDialog(BuildContext context) async {
    if (widget.organizationId.isEmpty) return;
    final directory = await widget.api!.listOrganizations();
    if (!context.mounted) return;
    final counterparties = (directory['organizations'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['id']?.toString() != widget.organizationId)
        .toList();
    final templateCtrl = TextEditingController(text: 'SUPPLY_AGREEMENT');
    final amountCtrl = TextEditingController();
    int startDay = 1;
    int endDay = 30;
    String? selectedCounterparty;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('DRAFT B2B CONTRACT'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: counterparties.any((row) =>
                          row['id']?.toString() == selectedCounterparty)
                      ? selectedCounterparty
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Counterparty organization',
                      border: OutlineInputBorder()),
                  items: counterparties
                      .map((row) => DropdownMenuItem(
                          value: row['id']?.toString(),
                          child: Text('${row['name'] ?? row['id']}')))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedCounterparty = value),
                  hint: Text(counterparties.isEmpty
                      ? 'No eligible counterparties found'
                      : 'Select an organization'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: templateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Template ID / Contract Type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount Per Period (CREDIT)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Start Day',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => startDay = int.tryParse(v) ?? 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'End Day',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => endDay = int.tryParse(v) ?? 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bilateral contracts require mutual digital signatures before financial and delivery obligations materialize.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('CANCEL')),
            FilledButton(
              onPressed: () async {
                final counterparty = selectedCounterparty ?? '';
                final amount = amountCtrl.text.trim();
                final parsedAmount = double.tryParse(amount);
                if (counterparty.isEmpty ||
                    templateCtrl.text.trim().isEmpty ||
                    parsedAmount == null ||
                    !parsedAmount.isFinite ||
                    parsedAmount <= 0 ||
                    startDay < 1 ||
                    endDay < startDay) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(
                        content: Text(
                            'Enter a positive amount and valid contract days.')));
                  }
                  return;
                }
                Navigator.of(dialogCtx).pop();
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);
                try {
                  await widget.api!.createOrganizationContract(
                    organizationId: widget.organizationId,
                    counterpartyOrganizationId: counterparty,
                    templateId: templateCtrl.text.trim(),
                    terms: {'rate': amount, 'delivery': 'STANDARD'},
                    startGameDay: startDay,
                    endGameDay: endDay,
                    amountPerPeriod: amount,
                    periodDays: 1,
                  );
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text('Contract drafted successfully')),
                    );
                    _loadContracts();
                    widget.onRefresh?.call();
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                          content: Text('Drafting failed: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text('SUBMIT DRAFT'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOrganization = widget.organizationId.isNotEmpty;
    return EarthSection(
      title: 'B2B CONTRACTS & PROCUREMENT',
      showSurface: false,
      infoBulletPoints: const [
        'Organizations establish formal supply and procurement contracts.',
        'Both counterparty organizations must digitally sign before obligations take effect.',
        'Settled contracts generate double-entry financial obligations in the daily ledger.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasOrganization)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Join an organization to view and create procurement contracts.',
                style: context.widgetFooterStyle,
              ),
            ),
          if (_isLoading) const LinearProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ACTIVE & PENDING CONTRACTS',
                  style: context.topicTitleStyle),
              FilledButton.icon(
                onPressed: hasOrganization && !_isLoading
                    ? () => _showCreateContractDialog(context)
                    : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('DRAFT CONTRACT'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text('Notice: $_error',
                style: TextStyle(color: context.warningColor))
          else if (!hasOrganization)
            Text('No organization is associated with this account.',
                style: context.widgetFooterStyle)
          else if (_contracts.isEmpty)
            Text(
                'No active or pending contracts registered for this organization.',
                style: context.widgetFooterStyle)
          else
            ..._contracts.whereType<Map>().map((c) {
              final id = c['id']?.toString() ?? '—';
              final counterparty =
                  c['counterparty_organization_id']?.toString() ?? '—';
              final status = c['status']?.toString() ?? 'PENDING';
              final amount = c['amount_per_period']?.toString() ?? '—';
              final start = c['start_game_day']?.toString() ?? '1';
              final end = c['end_game_day']?.toString() ?? '—';
              final periodDays = c['period_days']?.toString() ?? '—';
              final template = c['template_id']?.toString() ?? '—';
              final terms = c['terms'] is Map
                  ? Map<String, dynamic>.from(c['terms'] as Map)
                  : const <String, dynamic>{};
              final delivery = terms['delivery']?.toString() ?? '—';
              final signed = c['signed'] == true || status == 'ACTIVE';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text('$id · With: $counterparty',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      'Template: $template · Amount: $amount CREDIT/period · Delivery: $delivery\nDays: $start–$end · Period: $periodDays days · Status: $status'),
                  trailing: !signed && status == 'PENDING'
                      ? FilledButton.tonal(
                          onPressed: () => _signContract(id),
                          child: const Text('SIGN'),
                        )
                      : Chip(
                          label: Text(status),
                          backgroundColor: status == 'ACTIVE'
                              ? Colors.green.withOpacity(0.2)
                              : null,
                        ),
                ),
              );
            }),
          if (_performance.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('DELIVERY PERFORMANCE', style: context.topicTitleStyle),
            ..._performance.whereType<Map>().map((p) {
              final status = p['status']?.toString() ?? 'DUE';
              final id = p['id']?.toString() ?? '';
              final actions = status == 'DUE'
                  ? const ['deliver']
                  : status == 'DELIVERED'
                      ? const ['accept', 'reject', 'dispute']
                      : status == 'DISPUTED'
                          ? const ['resolve']
                          : const <String>[];
              return Card(
                  child: ListTile(
                      title: Text('$id · $status'),
                      subtitle: Text(
                          'Period ${p['period_start_game_day'] ?? '—'}–${p['period_end_game_day'] ?? '—'}${p['delivery_note'] == null ? '' : '\n${p['delivery_note']}'}'),
                      trailing: actions.isEmpty
                          ? null
                          : Wrap(
                              spacing: 4,
                              children: actions
                                  .map((action) => TextButton(
                                      onPressed: () =>
                                          _performanceAction(id, action),
                                      child: Text(action.toUpperCase())))
                                  .toList())));
            }),
          ],
        ],
      ),
    );
  }
}
