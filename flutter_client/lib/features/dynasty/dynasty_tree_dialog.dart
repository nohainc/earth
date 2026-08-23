import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/ui_style_tokens.dart';

void showDynastyTreeDialog(
  BuildContext context, {
  required EarthApi api,
  EarthState? state,
  String? initialMemberId,
}) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => DynastyTreeDialog(
      api: api,
      state: state,
      initialMemberId: initialMemberId,
    ),
  );
}

class DynastyTreeDialog extends StatefulWidget {
  final EarthApi api;
  final EarthState? state;
  final String? initialMemberId;
  final bool isPageMode;
  final ValueChanged<String>? onNavigate;
  final Future<void> Function()? onRefresh;

  const DynastyTreeDialog({
    super.key,
    required this.api,
    this.state,
    this.initialMemberId,
    this.isPageMode = false,
    this.onNavigate,
    this.onRefresh,
  });

  @override
  State<DynastyTreeDialog> createState() => _DynastyTreeDialogState();
}

class _DynastyTreeDialogState extends State<DynastyTreeDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _error;
  String? _successMessage;

  Map<String, dynamic> _dynasty = {};
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
    _loadDynastyData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDynastyData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.dynastyOverview();
      final dynastyData =
          Map<String, dynamic>.from(res['dynasty'] as Map? ?? {});
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
          _dynasty = dynastyData;
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
      final res = await widget.api.unlockDynastyPerk(perkKey);
      if (mounted) {
        final remaining = res['remainingPoints'] ?? '';
        setState(() {
          _isActionInProgress = false;
          _successMessage =
              'Hereditary Trait "$perkName" unlocked! ($remaining LP remaining)';
        });
        await _loadDynastyData();
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
      final res = await widget.api.equipDynastyHeirloom(heirloomId);
      if (mounted) {
        final isEquipped =
            res['isEquipped'] == true || res['isEquipped'] == 'true';
        setState(() {
          _isActionInProgress = false;
          _successMessage = isEquipped
              ? '$name equipped to current Dynastic Head.'
              : '$name returned to the Heritage Vault.';
        });
        await _loadDynastyData();
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
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final mottoCtrl =
        TextEditingController(text: _dynasty['motto']?.toString() ?? '');
    final nameCtrl =
        TextEditingController(text: _dynasty['dynasty_name']?.toString() ?? '');

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
            Text('EDIT DYNASTY CREED',
                style: TextStyle(
                    color: themeColor,
                    fontSize: tokens.number('typography.topicTitle.size', 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Dynasty Name',
                labelStyle: TextStyle(
                    color: mutedColor,
                    fontSize: tokens.number('typography.widgetFooter.size', 10)),
              ),
              style: TextStyle(
                  color: inkColor,
                  fontSize: tokens.number('typography.body.size', 10)),
            ),
            SizedBox(height: tokens.number('spacing.titleOffset', 12)),
            TextField(
              controller: mottoCtrl,
              decoration: InputDecoration(
                labelText: 'Dynasty Motto / Creed',
                labelStyle: TextStyle(
                    color: mutedColor,
                    fontSize: tokens.number('typography.widgetFooter.size', 10)),
              ),
              style: TextStyle(
                  color: inkColor,
                  fontSize: tokens.number('typography.body.size', 10)),
            ),
          ],
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
                  await widget.api.updateDynastyMotto(
                    motto: mottoCtrl.text.trim(),
                    dynastyName: nameCtrl.text.trim(),
                  );
                  if (mounted) {
                    setState(() =>
                        _successMessage = 'Dynasty creed updated successfully.');
                    await _loadDynastyData();
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
              child: Text('SAVE CREED',
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
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(1060.0, screenSize.width - 24);
    final dialogHeight = math.min(740.0, screenSize.height - 24);

    final dynastyName = (_dynasty['dynasty_name'] ?? 'Dynasty')
        .toString()
        .replaceFirst(RegExp(r'^house\s+', caseSensitive: false), '');
    final motto =
        (_dynasty['motto'] ?? 'From the Red Dust We Build Eternity').toString();
    final legacyPoints = _dynasty['legacy_points'] ?? 0;
    final familyDirection = (_dynasty['family_direction'] ??
            _dynasty['dynasty_direction'] ??
            'No family direction chosen yet')
        .toString();

    Widget topicsList = LayoutBuilder(
      builder: (context, constraints) {
        final lineage =
            !_loading ? _buildLineageSection() : const SizedBox.shrink();
        final perks = (!_loading && _catalogPerks.isNotEmpty)
            ? _buildPerksSection()
            : const SizedBox.shrink();
        final heirlooms = (!_loading && _heirlooms.isNotEmpty)
            ? _buildHeirloomsSection()
            : const SizedBox.shrink();

        if (constraints.maxWidth > 1000) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    lineage,
                  ],
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_loading) _buildFamilyIdentity(familyDirection),
                    if (!_loading && _catalogPerks.isNotEmpty) ...[
                      if (!_loading) SizedBox(height: tokens.number('spacing.section', 34)),
                      perks,
                    ],
                    if (!_loading && _heirlooms.isNotEmpty) ...[
                      if (!_loading && _catalogPerks.isNotEmpty)
                        SizedBox(height: tokens.number('spacing.section', 34)),
                      heirlooms,
                    ],
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            lineage,
            if (!_loading) ...[
              SizedBox(height: tokens.number('spacing.section', 34)),
              _buildFamilyIdentity(familyDirection),
            ],
            if (!_loading && _catalogPerks.isNotEmpty) ...[
              SizedBox(height: tokens.number('spacing.section', 34)),
              perks,
            ],
            if (!_loading && _heirlooms.isNotEmpty) ...[
              SizedBox(height: tokens.number('spacing.section', 34)),
              heirlooms,
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
            _buildTopHeader(dynastyName, motto, legacyPoints),
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
                  padding: EdgeInsets.only(bottom: tokens.number('spacing.topic', 16)),
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
      insetPadding: EdgeInsets.symmetric(
          horizontal: tokens.number('spacing.titleOffset', 12),
          vertical: tokens.number('spacing.titleOffset', 12)),
      child: content,
    );
  }

  Widget _buildTopHeader(
      String dynastyName, String motto, dynamic legacyPoints) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Container(
      padding: widget.isPageMode
          ? EdgeInsets.only(bottom: tokens.number('spacing.titleOffset', 12))
          : EdgeInsets.symmetric(
              horizontal: tokens.number('spacing.topic', 16),
              vertical: tokens.number('spacing.titleOffset', 12)),
      decoration: BoxDecoration(
        color: widget.isPageMode
            ? Colors.transparent
            : tokens.color('colors.surface', EarthColors.cardSurface),
        border: widget.isPageMode
            ? null
            : const Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  dynastyName.toUpperCase(),
                  style: TextStyle(
                    color: themeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: tokens.number('typography.pageTitle.size', 16),
                    letterSpacing:
                        tokens.number('typography.pageTitle.letterSpacing', 1.4),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: tokens.number('spacing.inline', 8)),
              Text(
                'DYNASTY',
                style: TextStyle(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  fontSize: tokens.number('typography.widgetTitle.size', 10),
                  letterSpacing: tokens.number('typography.widgetTitle.letterSpacing', 1.4),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                key: const Key('btn-edit-motto-dialog'),
                onTap: _showEditMottoDialog,
                child: Icon(Icons.edit,
                    size: tokens.number('controls.iconSize', 16),
                    color: themeColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '"$motto"',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mutedColor,
              fontSize: tokens.number('typography.topicTitle.size', 12),
              fontWeight: FontWeight.w700,
              letterSpacing:
                  tokens.number('typography.topicTitle.letterSpacing', 1.4),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: tokens.number('spacing.control', 10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _headerStatPill('LEGACY POINTS', '$legacyPoints LP',
                  Icons.auto_awesome, themeColor),
              SizedBox(width: tokens.number('spacing.inline', 8)),
              _headerStatPill(
                  'GENERATIONS',
                  '${_lineage.isEmpty ? 0 : _lineage.map((m) => _parseInt(m['generation'])).reduce(math.max)}',
                  Icons.groups_outlined,
                  themeColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStatPill(
      String label, String value, IconData icon, Color color) {
    final tokens = UiStyleTokens.current;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: tokens.number('spacing.inline', 8), vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .15),
        borderRadius:
            BorderRadius.circular(tokens.number('radius.control', 6)),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: tokens.number('controls.iconSize', 16), color: color),
          const SizedBox(width: 5),
          Text('$label: ',
              style:
                  TextStyle(
                      color: mutedColor,
                      fontSize: tokens.number('typography.widgetTitle.size', 10),
                      fontWeight: FontWeight.w700,
                      letterSpacing: tokens.number(
                          'typography.widgetTitle.letterSpacing', 1.4))),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize:
                      tokens.number('typography.widgetValue.size', 12),
                  letterSpacing: tokens.number(
                      'typography.widgetValue.letterSpacing', 1.4))),
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
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFamilyToday(),
        SizedBox(height: tokens.number('spacing.titleGap', 24)),
        Row(
          children: [
            Text(
              'PEOPLE & RELATIONSHIPS',
              style: TextStyle(
                color: mutedColor,
                fontSize: tokens.number('typography.topicTitle.size', 12),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: tokens.number('controls.iconSize', 16), color: themeColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
                      side: BorderSide(color: themeColor.withValues(alpha: .35)),
                    ),
                    title: Text(
                      'PEOPLE & RELATIONSHIPS',
                      style: TextStyle(
                        fontSize: tokens.number('typography.topicTitle.size', 12),
                        fontWeight: FontWeight.w700,
                        letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4),
                        color: themeColor,
                      ),
                    ),
                    content: Text(
                      '• Review the people who carry this family story forward.\n\n• Select a family member to understand their role, history, and readiness to carry responsibility.\n\n• Formal succession choices are managed from Life & Legacy.',
                      style: TextStyle(
                        fontSize: tokens.number('typography.body.size', 10),
                        color: inkColor.withValues(alpha: .8),
                        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('CLOSE',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: tokens.number('typography.control.size', 10),
                                fontWeight: FontWeight.w700,
                                letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        SizedBox(height: tokens.number('spacing.inline', 8)),
        // Ancestor Cards List Container
        Container(
          decoration: BoxDecoration(
            color: tokens.color('colors.surface', EarthColors.cardSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: _lineage.indexed.map((indexed) {
              final member = indexed.$2;
              final isLast = indexed.$1 == _lineage.length - 1;
              final isSelected = _selectedMember?['id'] == member['id'];
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : const BorderSide(color: Colors.white10),
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() => _selectedMember = member),
                  child: _buildMemberNodeCard(member, isSelected),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(height: tokens.number('spacing.titleOffset', 12)),
        // Right/Selected Member Dossier Inspector Panel Container
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: tokens.color('colors.surface', EarthColors.cardSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
          ),
          padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 14)),
          child: _selectedMember != null
              ? _buildMemberInspectorContent(_selectedMember!)
              : Center(
                  child: Padding(
                    padding: EdgeInsets.all(tokens.number('spacing.topic', 16)),
                    child: Text(
                      'Select a family member above to inspect their story, responsibilities, and contribution.',
                      style: TextStyle(
                        color: mutedColor,
                        fontSize: tokens.number('typography.body.size', 10),
                        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFamilyToday() {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final living =
        _lineage.where((member) => member['death_game_day'] == null).toList();
    final incumbents =
        _lineage.where((member) => member['is_incumbent'] == true).toList();
    final incumbent = incumbents.isEmpty ? null : incumbents.first;
    final successor = widget.state?.life['successor'];
    final successorName = successor is Map
        ? (successor['successor_name'] ?? successor['name'])?.toString()
        : null;
    final familyStatus = living.isEmpty
        ? 'No living family members are recorded yet.'
        : '${living.length} living family member${living.length == 1 ? '' : 's'} in the recorded lineage.';
    final successionStatus = successorName == null || successorName.isEmpty
        ? 'No successor is recorded — review this in Life & Legacy.'
        : 'Successor: $successorName';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 14)),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
        border: Border.all(color: themeColor.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FAMILY TODAY',
              style: TextStyle(
                  color: themeColor,
                  fontSize: tokens.number('typography.widgetTitle.size', 10),
                  fontWeight: FontWeight.w700,
                  letterSpacing: tokens.number('typography.widgetTitle.letterSpacing', 1.4))),
          SizedBox(height: tokens.number('spacing.inline', 8)),
          Text(
            incumbent == null
                ? 'Your family has no recorded current head.'
                : '${incumbent['name'] ?? 'Current family head'} leads the family today.',
            style: TextStyle(
                color: inkColor,
                fontSize: tokens.number('typography.widgetValue.size', 12),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number('typography.widgetValue.letterSpacing', 1.4)),
          ),
          const SizedBox(height: 4),
          Text(familyStatus,
              style: TextStyle(
                  color: mutedColor,
                  fontSize: tokens.number('typography.widgetFooter.size', 10),
                  letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0))),
          const SizedBox(height: 4),
          Text(successionStatus,
              style: TextStyle(
                  color: successorName == null
                      ? tokens.color('colors.warning', Colors.orangeAccent)
                      : themeColor,
                  fontSize: tokens.number('typography.widgetFooter.size', 10),
                  fontWeight: FontWeight.w700,
                  letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0))),
        ],
      ),
    );
  }

  Widget _buildFamilyIdentity(String direction) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final unlocked = _perks
        .map((perk) => perk['perk_name']?.toString())
        .whereType<String>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('FAMILY IDENTITY',
                style: TextStyle(
                    color: mutedColor,
                    fontSize: tokens.number('typography.topicTitle.size', 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number(
                        'typography.topicTitle.letterSpacing', 1.4))),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: tokens.number('controls.iconSize', 16),
                  color: themeColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'About family identity',
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
                    side: BorderSide(color: themeColor.withValues(alpha: .35)),
                  ),
                  title: Text('FAMILY IDENTITY',
                      style: TextStyle(
                          color: themeColor,
                          fontSize: tokens.number('typography.topicTitle.size', 12),
                          fontWeight: FontWeight.w700,
                          letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4))),
                  content: Text(
                      'Your family identity is shaped by the work, values, and choices you pass forward. It influences the practical advantages, heirlooms, and opportunities available to later generations.',
                      style: TextStyle(
                        color: inkColor.withValues(alpha: .8),
                        fontSize: tokens.number('typography.body.size', 10),
                        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
                      )),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('CLOSE',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: tokens.number('typography.control.size', 10),
                                fontWeight: FontWeight.w700,
                                letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))))
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.number('spacing.inline', 8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 14)),
          decoration: BoxDecoration(
              color: tokens.color('colors.surface', EarthColors.cardSurface),
              borderRadius:
                  BorderRadius.circular(tokens.number('radius.card', 10)),
              border: Border.all(color: Colors.white10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(direction,
                style: TextStyle(
                    color: themeColor,
                    fontSize:
                        tokens.number('typography.widgetValue.size', 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: tokens.number(
                        'typography.widgetValue.letterSpacing', 1.4))),
            const SizedBox(height: 6),
            Text(
                unlocked.isEmpty
                    ? 'No family traditions are active yet.'
                    : 'Active traditions: ${unlocked.join(' · ')}',
                style: TextStyle(
                    color: mutedColor,
                    fontSize:
                        tokens.number('typography.widgetFooter.size', 10),
                    fontWeight: FontWeight.w400,
                    letterSpacing: tokens.number(
                        'typography.widgetFooter.letterSpacing', 1.0))),
          ]),
        ),
      ],
    );
  }

  Widget _buildMemberNodeCard(Map<String, dynamic> member, bool isSelected) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = tokens.color('colors.secondary', violetColor);
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final gen = member['generation'] ?? 1;
    final name = member['name'] ?? 'Dynastic Heir';
    final title = member['title'] ?? 'Dynastic Member';
    final isIncumbent = member['is_incumbent'] == true;
    final birth = member['birth_game_day'] ?? 1;
    final death = member['death_game_day'];
    final wealth = _parseNum(member['lifetime_wealth']);
    final legacy = member['legacy_score'] ?? 0;

    final cardBorderColor = isSelected
        ? themeColor
        : (isIncumbent ? themeColor.withValues(alpha: .5) : Colors.white10);

    return Container(
      padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 10)),
      decoration: BoxDecoration(
        color: tokens.color('colors.surface', EarthColors.cardSurface),
        borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
        border:
            Border.all(color: cardBorderColor, width: isSelected ? 1.5 : 1.0),
        boxShadow: isSelected
            ? [
                BoxShadow(
                    color: themeColor.withValues(alpha: .25),
                    blurRadius: 10)
              ]
            : [],
      ),
      child: Row(
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
                color: isIncumbent
                    ? themeColor
                    : secondaryColor,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                'GEN\n$gen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isIncumbent
                      ? themeColor
                      : secondaryColor,
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
                    Text(
                      name,
                      style: TextStyle(
                          color: themeColor,
                          fontWeight: FontWeight.w700,
                          fontSize:
                              tokens.number('typography.widgetValue.size', 12),
                          letterSpacing: tokens.number(
                              'typography.widgetValue.letterSpacing', 1.4)),
                    ),
                    if (isIncumbent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                          border: Border.all(
                              color: themeColor.withValues(alpha: .35)),
                        ),
                        child: Text(
                          'ACTIVE HEAD',
                          style: TextStyle(
                              color: themeColor,
                              fontWeight: FontWeight.w700,
                              fontSize: tokens.number('typography.caption.size', 8),
                              letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4)),
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
                            letterSpacing: tokens.number(
                                'typography.widgetFooter.letterSpacing', 1.0)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title,
                    style: TextStyle(
                        color: mutedColor,
                        fontSize:
                            tokens.number('typography.widgetFooter.size', 10),
                        fontWeight: FontWeight.w400,
                        letterSpacing: tokens.number(
                            'typography.widgetFooter.letterSpacing', 1.0))),
                SizedBox(height: tokens.number('spacing.control', 6)),
                Wrap(
                  spacing: tokens.number('spacing.titleOffset', 12),
                  runSpacing: 4,
                  children: [
                    _nodeMiniStat('Wealth', '${wealth.toStringAsFixed(0)} CR'),
                    _nodeMiniStat('Legacy Score', '$legacy LP'),
                  ],
                ),
              ],
            ),
          ),
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

  Widget _buildMemberInspectorContent(Map<String, dynamic> member) {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final gen = member['generation'] ?? 1;
    final name = member['name'] ?? 'Dynastic Heir';
    final title = member['title'] ?? 'Dynastic Member';
    final isIncumbent = member['is_incumbent'] == true;
    final birth = member['birth_game_day'] ?? 1;
    final death = member['death_game_day'];
    final cause = member['cause_of_death'] ?? 'In Active Service';
    final epitaph = member['epitaph'] ?? 'Steering civilization forward.';
    final wealth = _parseNum(member['lifetime_wealth']);
    final businesses = member['businesses_founded'] ?? 0;
    final proposals = member['proposals_authored'] ?? 0;
    final legacy = member['legacy_score'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'GENERATION $gen DOSSIER',
              style: TextStyle(
                  color: themeColor,
                  fontSize: tokens.number('typography.widgetTitle.size', 10),
                  fontWeight: FontWeight.w700,
                  letterSpacing: tokens.number('typography.widgetTitle.letterSpacing', 1.4)),
            ),
            if (isIncumbent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                  border:
                      Border.all(color: themeColor.withValues(alpha: .35)),
                ),
                child: Text(
                  'INCUMBENT',
                  style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.w700,
                      fontSize: tokens.number('typography.caption.size', 8),
                      letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(name,
            style: TextStyle(
                color: inkColor,
                fontSize: tokens.number('typography.pageTitle.size', 16),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number('typography.pageTitle.letterSpacing', 1.4))),
        const SizedBox(height: 2),
        Text(title,
            style:
                TextStyle(
                  color: mutedColor,
                  fontSize: tokens.number('typography.widgetFooter.size', 10),
                  fontWeight: FontWeight.w400,
                  letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0),
                )),
        SizedBox(height: tokens.number('spacing.titleOffset', 12)),
        Container(
          padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 10)),
          decoration: BoxDecoration(
            color: tokens.color('colors.panel', EarthColors.panelSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _inspectorRow('Chronological Lifespan',
                  'Day $birth – ${death != null ? 'Day $death' : 'Living'}'),
              const SizedBox(height: 4),
              _inspectorRow('Status / Cause', cause),
            ],
          ),
        ),
        SizedBox(height: tokens.number('spacing.titleOffset', 12)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(tokens.number('pageTopics.cardPadding', 10)),
          decoration: BoxDecoration(
            color: themeColor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: themeColor.withValues(alpha: .25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ANCESTRAL EPITAPH & WILL',
                  style: TextStyle(
                      color: themeColor,
                      fontSize: tokens.number('typography.widgetTitle.size', 10),
                      fontWeight: FontWeight.w700,
                      letterSpacing: tokens.number('typography.widgetTitle.letterSpacing', 1.4))),
              const SizedBox(height: 4),
              Text(
                '"$epitaph"',
                style: TextStyle(
                    color: inkColor,
                    fontSize: tokens.number('typography.widgetFooter.size', 10),
                    fontStyle: FontStyle.italic,
                    letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0)),
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.number('spacing.titleOffset', 12)),
        Text('HISTORICAL MILESTONES',
            style: TextStyle(
                color: inkColor,
                fontSize: tokens.number('typography.topicTitle.size', 12),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4))),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: tokens.color('colors.panel', EarthColors.panelSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _milestoneTileRow('Lifetime Wealth Generated',
                  '${wealth.toStringAsFixed(0)} CR', Icons.account_balance,
                  isLast: false),
              _milestoneTileRow('Corporations & Enterprises Founded',
                  '$businesses Enterprises', Icons.business,
                  isLast: false),
              _milestoneTileRow('World Senate Proposals Passed',
                  '$proposals Enacted', Icons.gavel,
                  isLast: false),
              _milestoneTileRow('Generational Legacy Contribution',
                  '$legacy LP', Icons.auto_awesome,
                  isLast: true),
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
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    final userPoints = _parseInt(_dynasty['legacy_points'], fallback: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'FAMILY TRADITIONS',
              style: TextStyle(
                color: mutedColor,
                fontSize: tokens.number('typography.topicTitle.size', 12),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number(
                    'typography.topicTitle.letterSpacing', 1.4),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: tokens.number('controls.iconSize', 16),
                  color: themeColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
                      side: BorderSide(color: themeColor.withValues(alpha: .35)),
                    ),
                    title: Text(
                      'FAMILY TRADITIONS',
                      style: TextStyle(
                        fontSize: tokens.number('typography.topicTitle.size', 12),
                        fontWeight: FontWeight.w700,
                        letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4),
                        color: themeColor,
                      ),
                    ),
                    content: Text(
                      '• These traditions describe what your family is becoming known for.\n\n• Choose directions that shape future opportunities, relationships, and the abilities passed to later generations.\n\n• Legacy Points are a measure of influence, not money.',
                      style: TextStyle(
                        fontSize: tokens.number('typography.body.size', 10),
                        color: inkColor.withValues(alpha: .8),
                        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('CLOSE',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: tokens.number('typography.control.size', 10),
                                fontWeight: FontWeight.w700,
                                letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        SizedBox(height: tokens.number('spacing.inline', 8)),
        Container(
          decoration: BoxDecoration(
            color: tokens.color('colors.surface', EarthColors.cardSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
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
                padding: EdgeInsets.symmetric(
                    horizontal: tokens.number('pageTopics.cardPadding', 12),
                    vertical: tokens.number('spacing.control', 10)),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : const BorderSide(color: Colors.white10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isUnlocked
                            ? themeColor.withValues(alpha: .2)
                            : tokens.color('colors.panel', EarthColors.panelSurface),
                        border: Border.all(
                          color: isUnlocked
                              ? themeColor
                              : Colors.white10,
                        ),
                      ),
                      child: Icon(
                        isUnlocked ? Icons.check_circle : Icons.lock_outline,
                        color: isUnlocked
                            ? themeColor
                            : mutedColor,
                        size: 18,
                      ),
                    ),
                    SizedBox(width: tokens.number('spacing.titleOffset', 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(name,
                                  style: TextStyle(
                                      color: themeColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: tokens.number(
                                          'typography.widgetValue.size', 12),
                                      letterSpacing: tokens.number(
                                          'typography.widgetValue.letterSpacing',
                                          1.4))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: themeColor.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(tokens.number('radius.control', 4)),
                                ),
                                child: Text(
                                  category.toUpperCase(),
                                  style: TextStyle(
                                      color: themeColor,
                                      fontSize: tokens.number('typography.caption.size', 8),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(desc,
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: tokens.number(
                                      'typography.widgetFooter.size', 10),
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: tokens.number(
                                      'typography.widgetFooter.letterSpacing',
                                      1.0))),
                          Text('Unlock Requirement: $cost Legacy Points',
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: tokens.number(
                                      'typography.widgetFooter.size', 10),
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: tokens.number(
                                      'typography.widgetFooter.letterSpacing',
                                      1.0))),
                        ],
                      ),
                    ),
                    SizedBox(width: tokens.number('spacing.control', 10)),
                    if (isUnlocked)
                      Chip(
                        label: Text('ACTIVE TRAIT',
                            style: TextStyle(
                                fontSize: tokens.number('typography.caption.size', 8),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: tokens.color('colors.canvas', canvasColor))),
                        backgroundColor: themeColor,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                        ),
                      )
                    else
                      SizedBox(
                        height: tokens.number('controls.buttonHeight', 34),
                        child: ElevatedButton(
                          key: Key('btn-unlock-perk-$perkKey'),
                          onPressed: (_isActionInProgress || !canAfford)
                              ? null
                              : () => _unlockPerk(perkKey, name),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeColor,
                            foregroundColor: tokens.color('colors.canvas', canvasColor),
                            padding: EdgeInsets.symmetric(
                                horizontal: tokens.number('spacing.control', 10), vertical: 6),
                            textStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: tokens.number('typography.control.size', 10),
                                letterSpacing: tokens.number('typography.control.letterSpacing', 1.4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                            ),
                          ),
                          child: Text(_isActionInProgress
                              ? 'UNLOCKING...'
                              : 'UNLOCK ($cost LP)'),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeirloomsSection() {
    final tokens = UiStyleTokens.current;
    final themeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = tokens.color('colors.muted', EarthColors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'FAMILY HEIRLOOMS & SHARED ASSETS',
              style: TextStyle(
                color: mutedColor,
                fontSize: tokens.number('typography.topicTitle.size', 12),
                fontWeight: FontWeight.w700,
                letterSpacing: tokens.number(
                    'typography.topicTitle.letterSpacing', 1.4),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: tokens.number('controls.iconSize', 16),
                  color: themeColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: tokens.color('colors.panel', EarthColors.panelSurface),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.number('radius.panel', 14)),
                      side: BorderSide(color: themeColor.withValues(alpha: .35)),
                    ),
                    title: Text(
                      'FAMILY HEIRLOOMS & SHARED ASSETS',
                      style: TextStyle(
                        fontSize: tokens.number('typography.topicTitle.size', 12),
                        fontWeight: FontWeight.w700,
                        letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4),
                        color: themeColor,
                      ),
                    ),
                    content: Text(
                      '• Heirlooms are part of the family story, not ordinary equipment.\n\n• Each item records who created it, why it matters, and who currently carries its responsibility.\n\n• Equipped heirlooms transfer to the next generation through succession or Civic Rebirth and continue providing their gameplay benefit.',
                      style: TextStyle(
                        fontSize: tokens.number('typography.body.size', 10),
                        color: inkColor.withValues(alpha: .8),
                        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text('CLOSE',
                            style: TextStyle(
                                color: mutedColor,
                                fontSize: tokens.number('typography.control.size', 10),
                                fontWeight: FontWeight.w700,
                                letterSpacing: tokens.number('typography.control.letterSpacing', 1.4))),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        SizedBox(height: tokens.number('spacing.inline', 8)),
        Container(
          decoration: BoxDecoration(
            color: tokens.color('colors.surface', EarthColors.cardSurface),
            borderRadius: BorderRadius.circular(tokens.number('radius.card', 10)),
            border: Border.all(color: Colors.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: _heirlooms.indexed.map((indexed) {
              final heirloom = indexed.$2;
              final isLast = indexed.$1 == _heirlooms.length - 1;
              final id = heirloom['id']?.toString() ?? '';
              final name = heirloom['name']?.toString() ?? 'Ancestral Relic';
              final type =
                  heirloom['heirloom_type']?.toString() ?? 'founder_seal';
              final quality =
                  heirloom['quality_tier']?.toString() ?? 'Legendary';
              final statBuff =
                  heirloom['stat_buff']?.toString() ?? '+10% Prestige';
              final inscription =
                  heirloom['inscription']?.toString() ?? 'An ancient seal.';
              final rawEquipped = heirloom['equipped_by_human_id'];
              final isEquipped = rawEquipped != null &&
                  rawEquipped != 'null' &&
                  rawEquipped.toString().trim().isNotEmpty;

              return Container(
                padding: EdgeInsets.symmetric(
                    horizontal: tokens.number('pageTopics.cardPadding', 12),
                    vertical: tokens.number('spacing.control', 10)),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : const BorderSide(color: Colors.white10),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                        color: tokens.color('colors.canvas', canvasColor).withValues(alpha: .7),
                        border: Border.all(color: themeColor.withValues(alpha: .5)),
                      ),
                      child: Center(
                        child: Icon(
                          type == 'senate_gavel'
                              ? Icons.gavel
                              : (type == 'pioneer_chronometer'
                                  ? Icons.access_time
                                  : Icons.verified),
                          color: themeColor,
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.number('spacing.titleOffset', 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                    color: themeColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: tokens.number(
                                        'typography.widgetValue.size', 12),
                                    letterSpacing: tokens.number(
                                        'typography.widgetValue.letterSpacing',
                                        1.4)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: tokens.color('colors.warning', Colors.amberAccent).withValues(alpha: .2),
                                  borderRadius: BorderRadius.circular(tokens.number('radius.control', 4)),
                                  border: Border.all(
                                      color: tokens.color('colors.warning', Colors.amberAccent).withValues(alpha: .5)),
                                ),
                                child: Text(
                                  quality.toUpperCase(),
                                  style: TextStyle(
                                      color: tokens.color('colors.warning', Colors.amberAccent),
                                      fontSize: tokens.number('typography.caption.size', 8),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('Buff: $statBuff',
                              style: TextStyle(
                                  color: themeColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: tokens.number(
                                      'typography.widgetValue.size', 12),
                                  letterSpacing: tokens.number(
                                      'typography.widgetValue.letterSpacing',
                                      1.4))),
                          Text('"$inscription"',
                              style: TextStyle(
                                  color: mutedColor,
                                  fontSize: tokens.number(
                                      'typography.widgetFooter.size', 10),
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: tokens.number(
                                      'typography.widgetFooter.letterSpacing',
                                      1.0),
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    SizedBox(width: tokens.number('spacing.control', 10)),
                    SizedBox(
                      height: tokens.number('controls.buttonHeight', 34),
                      child: ElevatedButton(
                        key: Key('btn-equip-heirloom-$id'),
                        onPressed: _isActionInProgress
                            ? null
                            : () => _equipHeirloom(id, name),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isEquipped
                              ? Colors.grey[800]
                              : themeColor,
                          foregroundColor:
                              isEquipped ? Colors.white70 : tokens.color('colors.canvas', canvasColor),
                          padding: EdgeInsets.symmetric(
                              horizontal: tokens.number('spacing.control', 10), vertical: 6),
                          textStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: tokens.number('typography.control.size', 10),
                              letterSpacing: tokens.number('typography.control.letterSpacing', 1.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(tokens.number('radius.control', 6)),
                          ),
                        ),
                        child: Text(isEquipped ? 'UNEQUIP' : 'EQUIP TO HEAD'),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
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
