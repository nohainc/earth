import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/ui_style_tokens.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

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

class _HouseTreeDialogState extends State<HouseTreeDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  String? _successMessage;

  Map<String, dynamic> _house = {};
  List<Map<String, dynamic>> _lineage = [];
  List<Map<String, dynamic>> _perks = [];
  List<Map<String, dynamic>> _heirlooms = [];
  List<Map<String, dynamic>> _catalogPerks = [];

  Map<String, dynamic>? _selectedMember;
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHouseData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHouseData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.houseOverview();
      final houseData =
          Map<String, dynamic>.from((res['house'] ?? res['dynasty']) as Map? ?? {});
      final lineageList = ((res['lineage'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final perksList = ((res['perks'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final heirloomsList = ((res['heirlooms'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final catalogList = ((res['catalogPerks'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      Map<String, dynamic>? selected;
      if (widget.initialMemberId != null) {
        selected = lineageList.firstWhere(
          (m) => m['id'] == widget.initialMemberId,
          orElse: () => lineageList.isNotEmpty ? lineageList.first : {},
        );
      } else {
        selected = lineageList.isNotEmpty ? lineageList.first : null;
      }

      if (mounted) {
        setState(() {
          _house = houseData;
          _lineage = lineageList;
          _perks = perksList;
          _heirlooms = heirloomsList;
          _catalogPerks = catalogList;
          _selectedMember =
              selected != null && selected.isNotEmpty ? selected : null;
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

  Future<void> _unlockPerk(String perkKey, String perkName) async {
    setState(() {
      _isActionInProgress = true;
      _error = null;
    });
    try {
      final res = await widget.api.unlockHousePerk(perkKey);
      if (mounted) {
        final remaining = res['remainingPoints'] ?? '';
        setState(() {
          _isActionInProgress = false;
          _successMessage =
              'Hereditary Trait "$perkName" unlocked! ($remaining LP remaining)';
        });
        await _loadHouseData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _equipHeirloom(String heirloomId, String name) async {
    setState(() {
      _isActionInProgress = true;
      _error = null;
    });
    try {
      final res = await widget.api.equipHouseHeirloom(heirloomId);
      if (mounted) {
        final isEquipped = res['isEquipped'] == true ||
            res['isEquipped'] == 'true' ||
            res['is_equipped'] == true ||
            res['is_equipped'] == 'true';
        final equippedBy = res['equippedBy'] ?? res['equipped_by_human_id'];
        setState(() {
          _isActionInProgress = false;
          _successMessage = isEquipped
              ? '$name equipped to current Head of House.'
              : '$name returned to the Heritage Vault.';
          _heirlooms = _heirlooms.map((h) {
            if (h['id']?.toString() == heirloomId) {
              final copy = Map<String, dynamic>.from(h);
              copy['is_equipped'] = isEquipped;
              copy['isEquipped'] = isEquipped;
              copy['equipped_by_human_id'] =
                  isEquipped ? (equippedBy ?? 'H-0044') : null;
              copy['equippedBy'] =
                  isEquipped ? (equippedBy ?? 'H-0044') : null;
              return copy;
            }
            return h;
          }).toList();
        });
        await _loadHouseData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _error = e.toString().replaceFirst('Exception: ', '');
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
    final nameCtrl =
        TextEditingController(text: _house['house_name']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
          side: BorderSide(color: themeColor.withValues(alpha: .35)),
        ),
        title: Row(
          children: [
            Icon(Icons.edit, color: themeColor, size: tokens.number('controls.iconSize', 16)),
            SizedBox(width: tokens.number('spacing.inline', 8)),
            Text('EDIT HOUSE NAME',
                style: TextStyle(
                    color: themeColor,
                    fontSize: tokens.number('typography.topicTitle.size', 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4))),
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
                    letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))),
          ),
          SizedBox(
            height: tokens.number('controls.buttonHeight', 34),
            child: ElevatedButton(
              key: const Key('btn-save-motto'),
              onPressed: () async {
                if (nameCtrl.text.trim().length < 2) return;
                Navigator.of(ctx).pop();
                try {
                  await widget.api.updateHouseMotto(
                    motto: '',
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
                  borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                ),
              ),
              child: Text('SAVE',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: tokens.number('typography.control.size', 10),
                      letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))),
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

    final houseName = (_house['house_name'] ?? _house['dynasty_name'] ?? 'House')
        .toString()
        .replaceFirst(RegExp(r'^house\s+', caseSensitive: false), '');
    final legacyPoints = _parseInt(_house['legacy_points'], fallback: 0);

    Widget topicsList = LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840;

        final leftColumn = [
          if (!_loading) _buildHouseIdentitySection(houseName, legacyPoints),
          if (!_loading && _catalogPerks.isNotEmpty) ...[
            const SizedBox(height: 34),
            _buildPerksSection(),
          ],
          if (!_loading && _heirlooms.isNotEmpty) ...[
            const SizedBox(height: 34),
            _buildHeirloomsSection(),
          ],
        ];

        final rightColumn = [
          if (!_loading) _buildLineageSection(),
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
        color: widget.isPageMode ? Colors.transparent : tokens.color('colors.canvas', canvasColor),
        borderRadius:
            widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(tokens.number('radius.panel', 14)),
        border: widget.isPageMode
            ? null
            : Border.all(color: themeColor.withValues(alpha: .35)),
        boxShadow: widget.isPageMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .85),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius:
            widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(tokens.number('radius.panel', 14)),
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
                      padding: EdgeInsets.all(tokens.number('spacing.page', 24)),
                      child: CircularProgressIndicator(
                          color: themeColor)))
            else if (widget.isPageMode)
              topicsList
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
        border: const Border(bottom: BorderSide(color: Colors.white12)),
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
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white70),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildHouseIdentitySection(String rawHouseName, int legacyPoints) {
    final tokens = UiStyleTokens.current;
    final houseName = rawHouseName.trim().toUpperCase();
    final initials = houseName.length >= 2 ? houseName.substring(0, 2) : 'HO';

    final activeHumanName = (widget.state?.human['display_name'] ?? widget.state?.human['name'] ?? '').toString().trim();
    final gen1Member = _lineage.firstWhere(
      (m) => _parseInt(m['generation'], fallback: 0) == 1,
      orElse: () => _lineage.isNotEmpty ? _lineage.first : const <String, dynamic>{},
    );
    final isIncumbentGen1 = gen1Member['is_incumbent'] == true || _lineage.length <= 1;
    final founder = (isIncumbentGen1 && activeHumanName.isNotEmpty)
        ? activeHumanName
        : (_house['founder_name'] ?? _house['founder'] ?? gen1Member['name'] ?? (activeHumanName.isNotEmpty ? activeHumanName : 'Founding Ancestor')).toString();
    final rawFoundedDay = _parseInt(_house['founded_game_day'] ?? _house['founded_day'] ?? gen1Member['birth_game_day'], fallback: 1);
    final fYear = ((rawFoundedDay - 1) ~/ 365) + 1;
    final fDay = ((rawFoundedDay - 1) % 365) + 1;
    final foundedText = 'Year $fYear, Day $fDay';

    final legacy = _parseNum(_house['legacy_points'] ?? _house['total_legacy'] ?? widget.state?.json['legacy_score'] ?? legacyPoints);
    final standing = _parseNum(_house['standing'] ?? _house['civic_standing'] ?? _house['peak_standing'] ?? widget.state?.human['civic_standing'] ?? widget.state?.json['civic_standing']);
    final rawScore = _house['house_score'] ?? _house['score'] ?? _house['dynasty_score'];
    final houseScore = (rawScore != null && _parseNum(rawScore) > 0)
        ? _parseNum(rawScore)
        : (legacy * 50 + standing * 10);

    final successor = widget.state?.life['successor'];
    final successorName = successor is Map
        ? (successor['successor_name'] ?? successor['name'])?.toString()
        : null;
    final activeHeir = (_house['active_heir'] ?? _house['heir_name'] ?? successorName ?? 'Undesignated').toString();

    return EarthSection(
      title: 'HOUSE IDENTITY',
      showSurface: false,
      showHeader: false,
      infoBulletPoints: const [
        'The foundational identity and generational prestige of your House.',
        'Legacy Points (LP) measure permanent cultural influence passed across successions.',
        'House score aggregates total wealth, enacted proposals, and historic achievements across all generations.',
      ],
      child: Container(
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
            // Header Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: context.primaryColor.withValues(alpha: .15),
                  child: Text(
                    initials,
                    style: context.widgetTitleStyle.copyWith(
                      color: context.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          houseName,
                          style: context.topicTitleStyle.copyWith(
                            color: context.inkColor,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'HOUSE',
                        style: TextStyle(
                          color: context.mutedColor,
                          fontWeight: FontWeight.w700,
                          fontSize: tokens.number('typography.widgetTitle.size', 10),
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        key: const Key('btn-edit-motto-dialog'),
                        tooltip: 'Edit house name',
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: context.primaryColor,
                        ),
                        onPressed: _showEditMottoDialog,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: context.subtleBorderColor),
            const SizedBox(height: 10),
            // 2-Column Key-Value Attribute Table (3x2 symmetrical)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 450;
                final leftColumn = [
                  _buildAttributeRow(
                    context,
                    icon: Icons.person_outline,
                    label: 'FOUNDER',
                    value: founder,
                    accentColor: context.primaryColor,
                  ),
                  _buildAttributeRow(
                    context,
                    icon: Icons.cake_outlined,
                    label: 'FOUNDED',
                    value: foundedText,
                    accentColor: context.primaryColor,
                  ),
                  _buildAttributeRow(
                    context,
                    icon: Icons.emoji_events_outlined,
                    label: 'HOUSE SCORE',
                    value: '${formatWholeNumber(houseScore)} PTS',
                    accentColor: context.secondaryColor,
                  ),
                ];

                final rightColumn = [
                  _buildAttributeRow(
                    context,
                    icon: Icons.auto_awesome_outlined,
                    label: 'LEGACY',
                    value: '${formatWholeNumber(legacy)} LP',
                    accentColor: context.secondaryColor,
                  ),
                  _buildAttributeRow(
                    context,
                    icon: Icons.verified_user_outlined,
                    label: 'STANDING',
                    value: '${formatWholeNumber(standing)} Std',
                    accentColor: context.primaryColor,
                  ),
                  _buildAttributeRow(
                    context,
                    icon: Icons.how_to_reg_outlined,
                    label: 'ACTIVE HEIR',
                    value: activeHeir,
                    accentColor: context.successColor,
                  ),
                ];

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: leftColumn)),
                      const SizedBox(width: 24),
                      Expanded(child: Column(children: rightColumn)),
                    ],
                  );
                }

                return Column(
                  children: [
                    ...leftColumn,
                    ...rightColumn,
                  ],
                );
              },
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

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final color = isError ? Colors.redAccent : themeColor;
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
                  letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0)),
            ),
          ),
          IconButton(
            icon:
                Icon(Icons.close, size: 14, color: tokens.color('colors.muted', EarthColors.textMuted)),
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

  Widget _buildLineageSection() {
    return EarthSection(
      title: 'LINEAGE & HEIRS',
      showSurface: false,
      infoBulletPoints: const [
        'Ancestral tree tracking all generations of your House across world history.',
        'Tap any generation record to expand its full chronicle, lifetime wealth, and historical milestones.',
        'The active head inherits all equipped heirlooms and carries your House forward.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _lineage.map((member) {
          final isExpanded = _selectedMember?['id'] == member['id'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(context.radiusCard),
              onTap: () => setState(() {
                if (_selectedMember?['id'] == member['id']) {
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

  Widget _buildMemberNodeCard(Map<String, dynamic> member, bool isExpanded) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = tokens.color('colors.secondary', violetColor);
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final gen = member['generation'] ?? 1;
    final isIncumbent = member['is_incumbent'] == true;
    final activeHumanName = (widget.state?.human['display_name'] ?? widget.state?.human['name'] ?? '').toString().trim();
    final name = (isIncumbent && activeHumanName.isNotEmpty)
        ? activeHumanName
        : (member['name'] ?? 'House Heir').toString();
    final birth = _parseInt(member['birth_game_day'], fallback: 1);
    final death = member['death_game_day'] != null ? _parseInt(member['death_game_day']) : null;
    final wealth = isIncumbent
        ? _parseNum(widget.state?.human['credits'] ?? member['lifetime_wealth'] ?? 18420)
        : _parseNum(member['lifetime_wealth']);
    final legacy = isIncumbent
        ? _parseNum(widget.state?.human['legacy'] ?? member['legacy_score'] ?? 31)
        : _parseNum(member['legacy_score'] ?? 0);
    final standing = isIncumbent
        ? _parseNum(widget.state?.human['standing'] ?? widget.state?.human['civic_standing'] ?? member['standing'] ?? 742)
        : _parseNum(member['standing'] ?? member['final_standing'] ?? (legacy * 3));
    final age = isIncumbent
        ? _parseInt(widget.state?.human['age_years'] ?? member['age_years'], fallback: 31)
        : _parseInt(member['age_years'], fallback: (((death ?? (birth + 140)) - birth) ~/ 365) + 18);

    final epitaph = (member['epitaph'] ?? '').toString().trim();

    final cardBorderColor = isExpanded
        ? themeColor.withValues(alpha: .6)
        : (isIncumbent ? themeColor.withValues(alpha: .35) : context.subtleBorderColor);

    return Container(
      padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 12)),
      decoration: BoxDecoration(
        color: isExpanded
            ? context.surfaceColor
            : context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: cardBorderColor, width: isExpanded ? 1.5 : 1.0),
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
                              color: isIncumbent ? themeColor : context.inkColor,
                              fontWeight: FontWeight.w700,
                              fontSize: tokens.number('typography.widgetValue.size', 13),
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isIncumbent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                              border: Border.all(color: themeColor.withValues(alpha: .35)),
                            ),
                            child: Text(
                              'ACTIVE HEAD',
                              style: TextStyle(
                                color: themeColor,
                                fontWeight: FontWeight.w700,
                                fontSize: tokens.number('typography.caption.size', 8),
                                letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4),
                              ),
                            ),
                          )
                        else
                          Text(
                            'Day $birth – Day ${death ?? 'Present'}',
                            style: TextStyle(
                              color: mutedColor,
                              fontSize: tokens.number('typography.widgetFooter.size', 10),
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1.0,
                            ),
                          ),
                      ],
                    ),
                    if (epitaph.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        epitaph,
                        style: TextStyle(
                          color: context.mutedColor,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: tokens.number('spacing.titleOffset', 12),
                      runSpacing: 4,
                      children: [
                        _nodeMiniStat('Age', '$age'),
                        _nodeMiniStat('Standing', formatWholeNumber(standing)),
                        _nodeMiniStat('Legacy', '${formatWholeNumber(legacy)} LP'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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

  double _calculateActiveCapital() {
    if (widget.state == null) return 18420.0;
    final state = widget.state!;

    final explicitNw = state.json['total_net_worth'] ??
        state.json['net_worth'] ??
        state.finance['net_worth'] ??
        state.finance['total_net_worth'] ??
        state.personalFinance['net_worth'] ??
        state.personalFinance['total_net_worth'];
    if (explicitNw != null && _parseNum(explicitNw) > 0) {
      return _parseNum(explicitNw);
    }

    double total = _parseNum(state.human['credits']);
    final res = state.resources;
    final mat = _parseNum(res['material']);
    final energy = _parseNum(res['energy']);
    final compute = _parseNum(res['compute']);
    final food = _parseNum(res['food']);
    total += (mat * 12.0) + (energy * 6.0) + (compute * 25.0) + (food * 8.0);

    for (final m in state.machines) {
      if (m is Map) {
        total += _parseNum(m['cost'] ?? m['valuation'] ?? m['price'] ?? 5000.0);
      }
    }

    for (final b in state.buildings) {
      if (b is Map) {
        total += _parseNum(b['value'] ?? b['cost'] ?? 10000.0);
      }
    }

    for (final s in state.investmentShares) {
      if (s is Map) {
        total += _parseNum(s['value'] ?? s['valuation'] ?? s['total_value'] ?? 2500.0);
      }
    }

    return total > 0 ? total : _parseNum(state.human['credits'], fallback: 18420.0);
  }

  Widget _buildMemberInspectorContent(Map<String, dynamic> member) {
    final isIncumbent = member['is_incumbent'] == true;
    final birth = _parseInt(member['birth_game_day'], fallback: 1);
    final bYear = ((birth - 1) ~/ 365) + 1;
    final bDay = ((birth - 1) % 365) + 1;
    final birthDayFormatted = 'Year $bYear, Day $bDay';

    final wealth = isIncumbent
        ? _calculateActiveCapital()
        : _parseNum(member['lifetime_wealth'] ?? member['capital_generated'] ?? member['total_wealth']);
    final legacy = isIncumbent
        ? _parseNum(widget.state?.human['legacy'] ?? member['legacy_score'] ?? 31)
        : _parseNum(member['legacy_score'] ?? 0);

    final activeCityName = widget.state?.institutions['city'] is Map
        ? (widget.state!.institutions['city'] as Map)['name']?.toString().toUpperCase()
        : null;
    final activeCorporationName = (widget.state?.institutions['corporation'] is Map
            ? (widget.state!.institutions['corporation'] as Map)['name']?.toString().toUpperCase()
            : null) ??
        (widget.state?.membership?['corporation_name']?.toString().toUpperCase()) ??
        (widget.state?.membership?['name']?.toString().toUpperCase());

    final rawCity = isIncumbent
        ? (activeCityName ?? widget.state?.human['city_name'] ?? widget.state?.human['city_id'])
        : (member['city_name'] ?? member['city']);
    final rawCorp = isIncumbent
        ? (activeCorporationName ?? widget.state?.human['corporation_name'] ?? widget.state?.human['corporation_id'])
        : (member['corporation_name'] ?? member['corporation']);

    final city = (rawCity != null && rawCity.toString().trim().isNotEmpty && rawCity.toString() != 'null')
        ? rawCity.toString().replaceAll('city-', '').replaceAll('-', ' ').toUpperCase()
        : 'INDEPENDENT';
    final corporation = (rawCorp != null && rawCorp.toString().trim().isNotEmpty && rawCorp.toString() != 'null')
        ? rawCorp.toString().replaceAll('corp-', '').replaceAll('-', ' ').toUpperCase()
        : 'INDEPENDENT';

    final businesses = member['businesses_founded'] ?? 0;
    final proposals = member['proposals_authored'] ?? 0;

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
          icon: Icons.location_city_outlined,
          label: 'RESIDENCE',
          value: city,
          accentColor: context.secondaryColor,
        ),
        _buildAttributeRow(
          context,
          icon: Icons.corporate_fare_outlined,
          label: 'CORPORATION',
          value: corporation,
          accentColor: context.primaryColor,
        ),
        const SizedBox(height: 14),
        Text(
          'HISTORICAL MILESTONES & ACHIEVEMENTS',
          style: TextStyle(
            color: context.mutedColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(context.radiusCard),
            border: Border.all(color: context.subtleBorderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _milestoneTileRow(
                'Total Capital & Wealth Generated',
                '${formatWholeNumber(wealth)} CR',
                Icons.account_balance,
                isLast: false,
              ),
              _milestoneTileRow(
                'Corporations & Enterprises Founded',
                '$businesses Enterprises',
                Icons.business,
                isLast: false,
              ),
              _milestoneTileRow(
                'World Senate Proposals Passed',
                '$proposals Enacted',
                Icons.gavel,
                isLast: false,
              ),
              _milestoneTileRow(
                'Generational Legacy Contribution',
                '${formatWholeNumber(legacy)} LP',
                Icons.auto_awesome,
                isLast: true,
              ),
            ],
          ),
        ),
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
              letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0),
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
              letterSpacing: tokens.number('typography.widgetValue.letterSpacing', 1.4)),
        ),
      ],
    );
  }

  Widget _milestoneTileRow(String label, String value, IconData icon,
      {required bool isLast}) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: tokens.number('pageTopics.cardPadding', 10),
          vertical: tokens.number('spacing.inline', 8)),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: Colors.white10),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: tokens.number('controls.iconSize', 16) - 2, color: themeColor),
          SizedBox(width: tokens.number('spacing.inline', 8)),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: mutedColor,
                    fontSize: tokens.number('typography.widgetFooter.size', 10),
                    fontWeight: FontWeight.w400,
                    letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0))),
          ),
          Text(value,
              style: TextStyle(
                  color: inkColor,
                  fontWeight: FontWeight.w700,
                  fontSize: tokens.number('typography.widgetValue.size', 12),
                  letterSpacing: tokens.number('typography.widgetValue.letterSpacing', 1.4))),
        ],
      ),
    );
  }

  Widget _buildPerksSection() {
    final themeColor = Theme.of(context).colorScheme.primary;
    final userPoints = _parseInt(_house['legacy_points'], fallback: 0);

    return EarthSection(
      title: 'HEREDITARY PERKS',
      showSurface: false,
      infoBulletPoints: const [
        'Hereditary traditions provide permanent passive advantages across generations.',
        'Unlock new traits using accumulated House Legacy Points (LP).',
        'Traits remain permanently bound to your House lineage.',
      ],
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: _catalogPerks.indexed.map((indexed) {
            final perk = indexed.$2;
            final isLast = indexed.$1 == _catalogPerks.length - 1;
            final perkKey = perk['key']?.toString() ?? '';
            final name = perk['name']?.toString() ?? 'Trait';
            final category = perk['category']?.toString() ?? 'Operations';
            final cost = _parseInt(perk['cost'], fallback: 100);
            final desc = perk['description']?.toString() ?? '';

            final isUnlocked = _perks.any((p) => p['perk_key'] == perkKey);
            final canAfford = userPoints >= cost;

            return Container(
              key: Key('perk-card-$perkKey'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast ? BorderSide.none : BorderSide(color: context.subtleBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isUnlocked
                          ? themeColor.withValues(alpha: .2)
                          : context.surfaceColor,
                      border: Border.all(
                        color: isUnlocked ? themeColor : context.subtleBorderColor,
                      ),
                    ),
                    child: Icon(
                      isUnlocked ? Icons.check_circle : Icons.lock_outline,
                      color: isUnlocked ? themeColor : context.mutedColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              name,
                              style: context.bodyStyle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                category.toUpperCase(),
                                style: TextStyle(
                                  color: themeColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          style: context.bodyStyle.copyWith(
                            color: context.mutedColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isUnlocked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: context.successColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.successColor.withValues(alpha: .35)),
                      ),
                      child: Text(
                        'UNLOCKED',
                        style: TextStyle(
                          color: context.successColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    )
                  else
                    EarthButton(
                      buttonKey: Key('btn-unlock-perk-$perkKey'),
                      label: _isActionInProgress ? 'UNLOCKING...' : 'UNLOCK ($cost LP)',
                      variant: EarthButtonVariant.ghost,
                      isLoading: _isActionInProgress,
                      onPressed: (!canAfford || _isActionInProgress)
                          ? null
                          : () => _unlockPerk(perkKey, name),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHeirloomsSection() {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;

    return EarthSection(
      title: 'SHARED HEIRLOOMS & RELICS',
      showSurface: false,
      infoBulletPoints: const [
        'Ancestral relics passed across generations providing active buffs to the incumbent.',
        'Equip relics to the Head of House to gain their stat bonuses.',
        'Preserve heirlooms across succession cycles to retain dynastic power.',
      ],
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(context.radiusCard),
          border: Border.all(color: context.subtleBorderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: _heirlooms.indexed.map((indexed) {
            final h = indexed.$2;
            final isLast = indexed.$1 == _heirlooms.length - 1;
            final id = h['id']?.toString() ?? '';
            final name = h['name']?.toString() ?? 'Heirloom';
            final quality = h['quality_tier']?.toString() ?? h['quality']?.toString() ?? 'Common';
            final statBuff = h['stat_buff']?.toString() ?? 'None';
            final inscription = h['inscription']?.toString() ?? '';
            final isEquipped = h['is_equipped'] == true ||
                h['isEquipped'] == true ||
                (h['equipped_by_human_id'] != null &&
                    h['equipped_by_human_id'].toString().isNotEmpty &&
                    h['equipped_by_human_id'].toString() != 'null') ||
                (h['equippedBy'] != null &&
                    h['equippedBy'].toString().isNotEmpty &&
                    h['equippedBy'].toString() != 'null');

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast ? BorderSide.none : BorderSide(color: context.subtleBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber.withValues(alpha: .15),
                      border: Border.all(color: Colors.amber.withValues(alpha: .5)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield_outlined,
                        color: Colors.amber,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              name,
                              style: context.bodyStyle.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                quality.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isEquipped)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.primaryColor.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: context.primaryColor.withValues(alpha: .4)),
                                ),
                                child: Text(
                                  'EQUIPPED TO HEAD',
                                  style: TextStyle(
                                    color: context.primaryColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Buff: $statBuff · Inscription: $inscription',
                          style: context.bodyStyle.copyWith(
                            color: context.mutedColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  EarthButton(
                    buttonKey: Key('btn-equip-heirloom-$id'),
                    label: isEquipped ? 'UNEQUIP' : 'EQUIP TO HEAD',
                    variant: isEquipped ? EarthButtonVariant.secondary : EarthButtonVariant.primary,
                    onPressed: _isActionInProgress ? null : () => _equipHeirloom(id, name),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
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
