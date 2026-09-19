import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/house_profile.dart';
import '../../core/ui_style_tokens.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

void showHouseTreeDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String? initialMemberId,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => HouseTreeDialog(
      api: api,
      state: state,
      initialMemberId: initialMemberId,
    ),
  );
}

// Backwards compatibility alias
void showDynastyTreeDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String? initialMemberId,
}) =>
    showHouseTreeDialog(
      context,
      api: api,
      state: state,
      initialMemberId: initialMemberId,
    );

typedef DynastyTreeDialog = HouseTreeDialog;

class HouseTreeDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialMemberId;
  final bool isPageMode;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function()? onRefresh;

  const HouseTreeDialog({
    super.key,
    required this.api,
    this.state,
    this.initialMemberId,
    this.isPageMode = false,
    this.onNavigate,
    this.onRefresh,
  });

  @override
  State<HouseTreeDialog> createState() => _HouseTreeDialogState();
}

class _HouseTreeDialogState extends State<HouseTreeDialog> {
  bool _loading = true;
  String? _error;
  String? _successMessage;

  HouseProfile? _profile;
  List<HouseLineageEntry> _lineage = [];

  HouseLineageEntry? _selectedMember;

  @override
  void initState() {
    super.initState();
    _loadHouseData();
  }

  Future<void> _loadHouseData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await widget.api.houseProfile();
      final lineageList = profile.lineage;
      HouseLineageEntry? selected;
      if (widget.initialMemberId != null) {
        selected = lineageList.firstWhere(
          (m) => m.humanId == widget.initialMemberId,
          orElse: () => lineageList.isNotEmpty
              ? lineageList.first
              : const HouseLineageEntry(
                  humanId: '',
                  displayName: '',
                  generation: 0,
                  birthGameDay: 0,
                  deathGameDay: null,
                  status: 'UNKNOWN',
                  standing: '0',
                  finalLegacy: '0',
                  relationship: 'UNLINKED',
                  relatedHumanId: null,
                  successionEventId: null,
                  successionStatus: null,
                  effectiveGameDay: null),
        );
      } else {
        selected = lineageList.isNotEmpty ? lineageList.first : null;
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _lineage = lineageList;
          _selectedMember =
              selected?.humanId.isNotEmpty == true ? selected : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _showEditMottoDialog() {
    final tokens = UiStyleTokens.current;
    final theme = Theme.of(context);
    final themeColor = theme.colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final inkColor = theme.colorScheme.onSurface;
    final canvasColor = theme.colorScheme.surface;
    final nameCtrl = TextEditingController(text: _profile?.identity.name ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.circular(tokens.number('radius.panel', 14)),
          side: BorderSide(color: themeColor.withValues(alpha: .35)),
        ),
        title: Row(
          children: [
            Icon(Icons.edit,
                color: themeColor,
                size: tokens.number('controls.iconSize', 16)),
            SizedBox(width: tokens.number('spacing.inline', 8)),
            Text('EDIT HOUSE NAME',
                style: TextStyle(
                    color: themeColor,
                    fontSize: tokens.number('typography.topicTitle.size', 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number(
                        'typography.topicTitle.letterSpacing', 1.4))),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'House Name',
            labelStyle: TextStyle(
                color: mutedColor,
                fontSize: tokens.number('typography.widgetFooter.size', 10)),
          ),
          style: TextStyle(
              color: inkColor,
              fontSize: tokens.number('typography.body.size', 10)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL',
                style: TextStyle(
                    color: mutedColor,
                    fontSize: tokens.number('typography.control.size', 10),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number(
                        'typography.control.letterSpacing', 1.4))),
          ),
          SizedBox(
            height: tokens.number('controls.buttonHeight', 34),
            child: ElevatedButton(
              key: const Key('btn-save-motto'),
              onPressed: () async {
                if (nameCtrl.text.trim().length < 2) return;
                Navigator.of(ctx).pop();
                try {
                  await widget.api.updateHouseProfile(
                    motto: _profile?.identity.motto ?? '',
                    houseName: nameCtrl.text.trim(),
                  );
                  if (mounted) {
                    setState(() =>
                        _successMessage = 'House name updated successfully.');
                    await _loadHouseData();
                    await widget.onRefresh?.call();
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() =>
                        _error = e.toString().replaceFirst('Exception: ', ''));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: tokens.color('colors.canvas', canvasColor),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(tokens.number('radius.control', 6)),
                ),
              ),
              child: const Text('SAVE',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 1.4)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final canvasColor = Theme.of(context).colorScheme.surface;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(1060.0, screenSize.width - 24);
    final dialogHeight = math.min(840.0, screenSize.height - 24);

    final houseName = (_profile?.identity.name ?? 'House')
        .replaceFirst(RegExp(r'^house\s+(of\s+)?', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^of\s+', caseSensitive: false), '');
    final legacy = _parseNum(_profile?.economics.dynastyLegacyUnits);
    final activeHeir = _profile?.succession?.successorName;
    final generation = _profile?.identity.generation ?? 0;

    final cockpit = EarthPageCockpit(
      status: 'ANCESTRAL HERITAGE',
      statusColor: context.goldColor,
      infoTitle: 'DYNASTY HERITAGE & SUCCESSION ARCHITECTURE',
      infoDescription:
          '• Generational Continuity: Preserves your family lineage across biological successions, retaining House identity and accumulated capital.\n\n• Succession: Appointed successors inherit House-controlled assets and ongoing economic continuity.\n\n• Human offices and personal status do not transfer automatically after mortality.',
      title: 'HOUSE OF ${houseName.toUpperCase()}',
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'HOUSE OF ',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: context.mutedColor,
            ),
          ),
          Flexible(
            child: Text(
              houseName.toUpperCase(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: context.inkColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('btn-edit-motto-dialog'),
            tooltip: 'Edit house name',
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: context.primaryColor,
            ),
            onPressed: _showEditMottoDialog,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      subtitle:
          'House identity, durable assets, generational continuity, and succession across Earth',
      metrics: [
        CockpitMetric(
          label: 'Legacy',
          value: formatWholeNumber(legacy),
          icon: Icons.auto_awesome_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Generation',
          value: generation > 0 ? '$generation' : 'UNAVAILABLE',
          icon: Icons.how_to_reg_outlined,
          color: context.successColor,
        ),
      ],
    );

    Widget topicsList = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        final leftColumn = [
          if (!_loading) ...[
            _buildHouseIdentitySection(houseName),
            const SizedBox(height: 24),
            _buildCapacitySection(),
          ],
        ];

        final rightColumn = [
          if (!_loading) ...[
            _buildSuccessionSection(activeHeir),
            const SizedBox(height: 24),
            _buildNavigationSection(),
            const SizedBox(height: 24),
            _buildLineageSection(),
            const SizedBox(height: 24),
            _buildHistorySection(),
          ],
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: leftColumn,
                ),
              ),
              const SizedBox(width: 40),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rightColumn,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...leftColumn,
            if (!_loading) ...[
              const SizedBox(height: 34),
              ...rightColumn,
            ],
          ],
        );
      },
    );

    Widget content = Container(
      width: widget.isPageMode ? double.infinity : dialogWidth,
      height: widget.isPageMode ? null : dialogHeight,
      decoration: BoxDecoration(
        color: widget.isPageMode
            ? Colors.transparent
            : tokens.color('colors.canvas', canvasColor),
        borderRadius: widget.isPageMode
            ? BorderRadius.zero
            : BorderRadius.circular(tokens.number('radius.panel', 14)),
        border: widget.isPageMode
            ? null
            : Border.all(color: themeColor.withValues(alpha: .35)),
        boxShadow: widget.isPageMode
            ? null
            : [
                BoxShadow(
                  color: context.canvasColor.withValues(alpha: .85),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: widget.isPageMode
            ? BorderRadius.zero
            : BorderRadius.circular(tokens.number('radius.panel', 14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: widget.isPageMode ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (!widget.isPageMode) _buildModalHeader(houseName),
            if (_error != null) _buildAlertBanner(_error!, isError: true),
            if (_successMessage != null)
              _buildAlertBanner(_successMessage!, isError: false),
            if (_loading && _lineage.isEmpty)
              Center(
                  child: Padding(
                      padding:
                          EdgeInsets.all(tokens.number('spacing.page', 24)),
                      child: CircularProgressIndicator(color: themeColor)))
            else if (widget.isPageMode)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cockpit,
                  const SizedBox(height: 28),
                  topicsList,
                ],
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: topicsList,
                ),
              ),
          ],
        ),
      ),
    );

    if (widget.isPageMode) {
      return content;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: content,
    );
  }

  Widget _buildModalHeader(String houseName) {
    final themeColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        border: Border(bottom: BorderSide(color: context.subtleBorderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: themeColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'HOUSE OF $houseName'.toUpperCase(),
                style: TextStyle(
                  color: themeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('btn-edit-motto-dialog'),
                tooltip: 'Edit house name',
                icon: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: themeColor,
                ),
                onPressed: _showEditMottoDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: context.mutedColor),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildHouseIdentitySection(String rawHouseName) {
    final houseName = rawHouseName.trim().toUpperCase();
    final profile = _profile!;
    final affiliation = profile.affiliation;

    return EarthSection(
      title: 'HOUSE IDENTITY',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'The foundational identity and generational continuity of your House.',
        'Only canonical House identity facts are shown here.',
      ],
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(context.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAttributeRow(context,
                icon: Icons.shield_outlined,
                label: 'HOUSE',
                value: houseName,
                accentColor: context.primaryColor),
            _buildAttributeRow(context,
                icon: Icons.info_outline,
                label: 'STATUS',
                value: profile.identity.status,
                accentColor: context.successColor),
            _buildAttributeRow(context,
                icon: Icons.layers_outlined,
                label: 'GENERATION',
                value: '${profile.identity.generation}',
                accentColor: context.secondaryColor),
            _buildAttributeRow(context,
                icon: Icons.person_outline,
                label: 'CURRENT HUMAN',
                value: profile.currentHuman.displayName,
                accentColor: context.primaryColor),
            _buildAttributeRow(context,
                icon: Icons.business_outlined,
                label: 'CORPORATION',
                value: affiliation?.corporationName.isNotEmpty == true
                    ? affiliation!.corporationName
                    : 'INDEPENDENT',
                accentColor: context.primaryColor),
            _buildAttributeRow(context,
                icon: Icons.auto_awesome_outlined,
                label: 'DYNASTY LEGACY',
                value: formatWholeNumber(
                    _parseNum(profile.economics.dynastyLegacyUnits)),
                accentColor: context.secondaryColor),
            if (profile.identity.motto?.trim().isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('“${profile.identity.motto}”',
                    style: context.bodyStyle.copyWith(
                        color: context.mutedColor,
                        fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapacitySection() {
    final profile = _profile!;
    final capacity = profile.settlementProfile;
    return EarthSection(
      title: 'CAPACITY & ESTATE',
      showSurface: false,
      infoBulletPoints: const [
        'Capacity values are the latest server-derived V5 settlement profile for this House.',
        'Building count reflects active buildings included in that profile.',
      ],
      child: Container(
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        child: Column(children: [
          _buildAttributeRow(context,
              icon: Icons.home_work_outlined,
              label: 'RESIDENTIAL CAPACITY',
              value: capacity?.residentialCapacityUnits ?? 'UNAVAILABLE',
              accentColor: context.primaryColor),
          _buildAttributeRow(context,
              icon: Icons.factory_outlined,
              label: 'PRODUCTIVE CAPACITY',
              value: capacity?.productiveCapacityUnits ?? 'UNAVAILABLE',
              accentColor: context.secondaryColor),
          _buildAttributeRow(context,
              icon: Icons.stacked_bar_chart_outlined,
              label: 'TOTAL CAPACITY',
              value: capacity?.totalCapacityUnits ?? 'UNAVAILABLE',
              accentColor: context.successColor),
          _buildAttributeRow(context,
              icon: Icons.apartment_outlined,
              label: 'ACTIVE BUILDINGS',
              value: capacity == null
                  ? 'UNAVAILABLE'
                  : '${capacity.activeBuildingCount}',
              accentColor: context.primaryColor),
        ]),
      ),
    );
  }

  Widget _buildNavigationSection() {
    final links = <({String label, String route, IconData icon})>[
      (label: 'CITIZEN', route: 'life', icon: Icons.person_outline),
      (
        label: 'MY CORPORATION',
        route: 'my-corporation',
        icon: Icons.business_outlined
      ),
      (label: 'BUILDINGS', route: 'buildings', icon: Icons.domain_outlined),
      (
        label: 'FINANCE',
        route: 'finance',
        icon: Icons.account_balance_wallet_outlined
      ),
    ];
    return EarthSection(
      title: 'HOUSE SERVICES',
      showSurface: false,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: links
            .map((link) => OutlinedButton.icon(
                  onPressed: widget.onNavigate == null
                      ? null
                      : () => widget.onNavigate!(link.route),
                  icon: Icon(link.icon, size: 15),
                  label: Text(link.label),
                ))
            .toList(),
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
                color: context.inkColor,
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

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final color = isError ? context.errorColor : themeColor;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: tokens.number('pageTopics.cardPadding', 14), vertical: 6),
      color: color.withValues(alpha: .15),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: color, size: 15),
          SizedBox(width: tokens.number('spacing.inline', 8)),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: color,
                  fontSize: tokens.number('typography.widgetFooter.size', 10),
                  fontWeight: FontWeight.w700,
                  letterSpacing: tokens.number(
                      'typography.widgetFooter.letterSpacing', 1.0)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 14,
                color: tokens.color('colors.muted', EarthColors.textMuted)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() {
              _error = null;
              _successMessage = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessionSection(String? successorName) {
    final profile = _profile!;
    final currentHead = _profile?.currentHuman.displayName;
    final status = _profile?.succession?.status.toUpperCase();
    final policy = profile.successionPolicy;
    final quote = profile.successionQuote;

    return EarthSection(
      title: 'SUCCESSION & CURRENT HEAD',
      showSurface: false,
      infoBulletPoints: const [
        'The House is persistent; the current Human is its representative.',
        'The designated successor receives executive agency when succession is activated.',
        'Only server-confirmed succession facts are shown.',
      ],
      child: Container(
        padding: EdgeInsets.all(context.cardPadding),
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        child: Column(
          children: [
            _buildAttributeRow(
              context,
              icon: Icons.person_outline,
              label: 'HEAD OF HOUSE',
              value: currentHead ?? 'UNAVAILABLE',
              accentColor: context.primaryColor,
            ),
            _buildAttributeRow(
              context,
              icon: Icons.how_to_reg_outlined,
              label: 'SUCCESSOR',
              value: successorName ?? 'UNDESIGNATED',
              accentColor: context.successColor,
            ),
            _buildAttributeRow(
              context,
              icon: Icons.verified_outlined,
              label: 'STATUS',
              value: status ?? 'UNAVAILABLE',
              accentColor: context.secondaryColor,
            ),
            const SizedBox(height: 10),
            _buildAttributeRow(context,
                icon: Icons.payments_outlined,
                label: 'FIXED COST',
                value: formatCreditUnits(policy.fixedCostUnits),
                accentColor: context.secondaryColor),
            _buildAttributeRow(context,
                icon: Icons.percent,
                label: 'PERCENTAGE COST',
                value: _formatRateBps(policy.percentageCostBps),
                accentColor: context.secondaryColor),
            _buildAttributeRow(context,
                icon: Icons.hourglass_bottom_outlined,
                label: 'TRANSITION',
                value: '${policy.transitionDays} GAME DAYS',
                accentColor: context.secondaryColor),
            _buildAttributeRow(context,
                icon: Icons.request_quote_outlined,
                label: 'ESTIMATED COST',
                value: formatCreditUnits(quote.estimatedCostUnits),
                accentColor: quote.affordable
                    ? context.successColor
                    : context.errorColor),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'The House, its capacity, buildings, economic balances, and Corporation affiliation persist. The Human, personal offices, and personal status do not transfer automatically; the successor becomes the House representative when succession is activated.',
                style: context.bodyStyle
                    .copyWith(color: context.mutedColor, fontSize: 11),
              ),
            ),
            if (widget.onNavigate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _showSuccessionDialog,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(successorName == null
                      ? 'DESIGNATE SUCCESSOR'
                      : 'UPDATE SUCCESSOR'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSuccessionDialog() async {
    final controller =
        TextEditingController(text: _profile?.succession?.successorName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('HOUSE SUCCESSION'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Successor name',
            hintText: 'Leave blank to clear the plan',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('SAVE')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      await widget.api.registerHouseSuccessor(name);
      if (mounted) {
        setState(() => _successMessage = 'House succession plan updated.');
        await _loadHouseData();
        await widget.onRefresh?.call();
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Widget _buildLineageSection() {
    return EarthSection(
      title: 'LINEAGE & HEIRS',
      showSurface: false,
      infoBulletPoints: const [
        'Immutable generational history is reconstructed from canonical Humans and succession events.',
        'Each record includes birth, death, standing, final legacy, and its succession relationship.',
        'Tap any generation record to inspect the authoritative history.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _lineage.isEmpty
            ? [
                const EarthEmptyState(
                  message:
                      'No canonical lineage records are available for this House.',
                  icon: Icons.account_tree_outlined,
                ),
              ]
            : _lineage.map((member) {
                final isExpanded = _selectedMember?.humanId == member.humanId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    onTap: () => setState(() {
                      if (_selectedMember?.humanId == member.humanId) {
                        _selectedMember = null;
                      } else {
                        _selectedMember = member;
                      }
                    }),
                    child: _buildMemberNodeCard(member, isExpanded),
                  ),
                );
              }).toList(),
      ),
    );
  }

  Widget _buildHistorySection() {
    final history = _profile?.history ?? const <HouseHistoryEntry>[];
    return EarthSection(
      title: 'HOUSE HISTORY',
      showSurface: false,
      infoBulletPoints: const [
        'Read-only milestones are taken from the authoritative game event journal.',
        'No milestone is inferred from counters or displayed when the underlying event is unavailable.',
      ],
      child: history.isEmpty
          ? const EarthEmptyState(
              message: 'No canonical House milestones are recorded yet.',
              icon: Icons.history_outlined,
            )
          : Column(
              children: history.map((event) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_historyIcon(event.category),
                      color: context.primaryColor, size: 18),
                  title: Text(event.title,
                      style: context.bodyStyle.copyWith(
                          color: context.inkColor,
                          fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'Day ${event.gameDay} · ${event.category} · ${event.eventType}',
                      style: context.bodyStyle
                          .copyWith(color: context.mutedColor, fontSize: 10)),
                );
              }).toList(),
            ),
    );
  }

  static IconData _historyIcon(String category) {
    switch (category.toUpperCase()) {
      case 'LIFECYCLE':
        return Icons.autorenew_outlined;
      case 'BUILDING':
        return Icons.domain_outlined;
      case 'AFFILIATION':
        return Icons.link_outlined;
      case 'INSTITUTION':
        return Icons.groups_outlined;
      case 'RESEARCH':
        return Icons.biotech_outlined;
      default:
        return Icons.history_outlined;
    }
  }

  Widget _buildMemberNodeCard(HouseLineageEntry member, bool isExpanded) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = tokens.color('colors.secondary', violetColor);
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final gen = member.generation.toString();
    final isIncumbent = member.relationship == 'CURRENT';
    final name = member.displayName;
    final birth = member.birthGameDay.toString();
    final death = member.deathGameDay;

    final cardBorderColor = isExpanded
        ? themeColor.withValues(alpha: .6)
        : (isIncumbent
            ? themeColor.withValues(alpha: .35)
            : context.subtleBorderColor);

    return Container(
      padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 12)),
      decoration: BoxDecoration(
        color: isExpanded
            ? context.surfaceColor
            : context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border:
            Border.all(color: cardBorderColor, width: isExpanded ? 1.5 : 1.0),
        boxShadow: isExpanded
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
          // Header Row (Clickable Gen Summary)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isIncumbent
                      ? themeColor.withValues(alpha: .2)
                      : secondaryColor.withValues(alpha: .15),
                  border: Border.all(
                    color: isIncumbent ? themeColor : secondaryColor,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    'GEN\n$gen',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isIncumbent ? themeColor : secondaryColor,
                      fontWeight: FontWeight.w700,
                      fontSize: tokens.number('typography.caption.size', 8),
                      height: 1.1,
                    ),
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
                              color:
                                  isIncumbent ? themeColor : context.inkColor,
                              fontWeight: FontWeight.w700,
                              fontSize: tokens.number(
                                  'typography.widgetValue.size', 13),
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isIncumbent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(
                                  tokens.number('radius.control', 6)),
                              border: Border.all(
                                  color: themeColor.withValues(alpha: .35)),
                            ),
                            child: Text(
                              'ACTIVE HEAD',
                              style: TextStyle(
                                color: themeColor,
                                fontWeight: FontWeight.w700,
                                fontSize:
                                    tokens.number('typography.caption.size', 8),
                                letterSpacing: tokens.number(
                                    'typography.caption.letterSpacing', 1.4),
                              ),
                            ),
                          )
                        else
                          Text(
                            'Day $birth – Day ${death ?? 'Present'}',
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: tokens.number(
                                  'typography.widgetFooter.size', 10),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1.0,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: tokens.number('spacing.titleOffset', 12),
                      runSpacing: 4,
                      children: [
                        _nodeMiniStat('Standing', member.standing),
                        _nodeMiniStat('Final legacy', member.finalLegacy),
                        _nodeMiniStat('Relation', member.relationship),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: isExpanded ? themeColor : mutedColor,
                size: 22,
              ),
            ],
          ),

          // Expandable Dossier Content
          if (isExpanded) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: context.subtleBorderColor),
            const SizedBox(height: 12),
            _buildMemberInspectorContent(member),
          ],
        ],
      ),
    );
  }

  Widget _nodeMiniStat(String label, String value) {
    final tokens = UiStyleTokens.current;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final themeColor = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(
                color: mutedColor,
                fontSize: tokens.number('typography.widgetTitle.size', 10),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number(
                    'typography.widgetTitle.letterSpacing', 1.4))),
        Text(value,
            style: TextStyle(
                color: themeColor,
                fontWeight: FontWeight.w700,
                fontSize: tokens.number('typography.widgetValue.size', 12),
                letterSpacing: tokens.number(
                    'typography.widgetValue.letterSpacing', 1.4))),
      ],
    );
  }

  Widget _buildMemberInspectorContent(HouseLineageEntry member) {
    final birth = member.birthGameDay;
    final birthDayFormatted = birth > 0 ? _formatGameDay(birth) : 'UNAVAILABLE';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAttributeRow(
          context,
          icon: Icons.cake_outlined,
          label: 'BIRTH DAY',
          value: birthDayFormatted,
          accentColor: context.primaryColor,
        ),
        _buildAttributeRow(
          context,
          icon: Icons.flag_outlined,
          label: 'STATUS',
          value: member.status,
          accentColor: context.primaryColor,
        ),
        _buildAttributeRow(context,
            icon: Icons.how_to_reg_outlined,
            label: 'STANDING',
            value: member.standing,
            accentColor: context.secondaryColor),
        _buildAttributeRow(context,
            icon: Icons.auto_awesome_outlined,
            label: 'FINAL LEGACY',
            value: member.finalLegacy,
            accentColor: context.secondaryColor),
        if (member.relatedHumanId != null)
          _buildAttributeRow(context,
              icon: Icons.swap_horiz_outlined,
              label: member.relationship,
              value: member.relatedHumanId!,
              accentColor: context.successColor),
        if (member.effectiveGameDay != null)
          _buildAttributeRow(context,
              icon: Icons.event_outlined,
              label: 'EFFECTIVE DAY',
              value: 'Day ${member.effectiveGameDay}',
              accentColor: context.successColor),
      ],
    );
  }

  Widget _inspectorRow(String label, String val) {
    final tokens = UiStyleTokens.current;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: mutedColor,
              fontSize: tokens.number('typography.widgetFooter.size', 10),
              fontWeight: FontWeight.w400,
              letterSpacing:
                  tokens.number('typography.widgetFooter.letterSpacing', 1.0),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          val,
          style: TextStyle(
              color: inkColor,
              fontWeight: FontWeight.w700,
              fontSize: tokens.number('typography.widgetValue.size', 12),
              letterSpacing:
                  tokens.number('typography.widgetValue.letterSpacing', 1.4)),
        ),
      ],
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static String _formatRateBps(String value) {
    final bps = BigInt.tryParse(value) ?? BigInt.zero;
    final whole = bps ~/ BigInt.from(100);
    final fraction = (bps % BigInt.from(100)).toString().padLeft(2, '0');
    return '$whole.$fraction%';
  }

  static String _formatGameDay(int day) {
    final year = ((day - 1) ~/ 365) + 1;
    final yearDay = ((day - 1) % 365) + 1;
    return 'Year $year, Day $yearDay';
  }

  static int _parseInt(dynamic val, {int fallback = 0}) {
    if (val is num) {
      return val.toInt();
    }
    if (val is String) {
      return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
    }
    return fallback;
  }
}
