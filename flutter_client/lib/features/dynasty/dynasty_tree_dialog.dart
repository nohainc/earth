import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';

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
    final mottoCtrl =
        TextEditingController(text: _dynasty['motto']?.toString() ?? '');
    final nameCtrl =
        TextEditingController(text: _dynasty['dynasty_name']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EarthColors.panelSurface,
        title: const Row(
          children: [
            Icon(Icons.edit, color: EarthColors.goldMetallic, size: 18),
            SizedBox(width: 8),
            Text('EDIT DYNASTY CREED',
                style: TextStyle(
                    color: EarthColors.goldMetallic,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Dynasty Name',
                labelStyle:
                    TextStyle(color: EarthColors.textMuted, fontSize: 11),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mottoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Dynasty Motto / Creed',
                labelStyle:
                    TextStyle(color: EarthColors.textMuted, fontSize: 11),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL',
                style: TextStyle(color: EarthColors.textMuted, fontSize: 11)),
          ),
          ElevatedButton(
            key: const Key('btn-save-motto'),
            onPressed: () async {
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
                if (mounted)
                  setState(() =>
                      _error = e.toString().replaceFirst('Exception: ', ''));
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: EarthColors.goldMetallic,
                foregroundColor: Colors.black),
            child: const Text('SAVE CREED',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    if (!_loading && _catalogPerks.isNotEmpty) perks,
                    if (!_loading && _heirlooms.isNotEmpty) ...[
                      if (!_loading && _catalogPerks.isNotEmpty)
                        const SizedBox(height: 34),
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
              const SizedBox(height: 34),
              _buildFamilyIdentity(familyDirection),
            ],
            if (!_loading && _catalogPerks.isNotEmpty) ...[
              const SizedBox(height: 34),
              perks,
            ],
            if (!_loading && _heirlooms.isNotEmpty) ...[
              const SizedBox(height: 34),
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
        color: widget.isPageMode ? Colors.transparent : canvasColor,
        borderRadius:
            widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
        border: widget.isPageMode
            ? null
            : Border.all(color: EarthColors.goldMetallic.withAlpha(140)),
        boxShadow: widget.isPageMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(220),
                  blurRadius: 36,
                  spreadRadius: 8,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius:
            widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: widget.isPageMode ? MainAxisSize.min : MainAxisSize.max,
          children: [
            _buildTopHeader(dynastyName, motto, legacyPoints),
            if (_error != null) _buildAlertBanner(_error!, isError: true),
            if (_successMessage != null)
              _buildAlertBanner(_successMessage!, isError: false),
            if (_loading && _lineage.isEmpty)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                          color: EarthColors.goldMetallic)))
            else if (widget.isPageMode)
              topicsList
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
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

  Widget _buildTopHeader(
      String dynastyName, String motto, dynamic legacyPoints) {
    return Container(
      padding: widget.isPageMode
          ? const EdgeInsets.only(bottom: 12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : EarthColors.cardSurface,
        border: widget.isPageMode
            ? null
            : const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
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
                    color: widget.isPageMode
                        ? EarthColors.textMuted
                        : EarthColors.goldMetallic,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'DYNASTY',
                style: TextStyle(
                  color: EarthColors.textMuted,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                key: const Key('btn-edit-motto-dialog'),
                onTap: _showEditMottoDialog,
                child: const Icon(Icons.edit,
                    size: 13, color: EarthColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '"$motto"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _headerStatPill('LEGACY POINTS', '$legacyPoints LP',
                  Icons.auto_awesome, EarthColors.goldMetallic),
              const SizedBox(width: 8),
              _headerStatPill(
                  'GENERATIONS',
                  '${_lineage.isEmpty ? 0 : _lineage.map((m) => _parseInt(m['generation'])).reduce(math.max)}',
                  Icons.groups_outlined,
                  EarthColors.cyanAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStatPill(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text('$label: ',
              style:
                  const TextStyle(color: EarthColors.textMuted, fontSize: 9.5)),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _buildAlertBanner(String message, {required bool isError}) {
    final color = isError ? Colors.redAccent : EarthColors.cyanAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: color.withAlpha(25),
      child: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
              color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon:
                const Icon(Icons.close, size: 14, color: EarthColors.textMuted),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFamilyToday(),
        const SizedBox(height: 26),
        Row(
          children: [
            const Text(
              'PEOPLE & RELATIONSHIPS',
              style: TextStyle(
                color: EarthColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  size: 14, color: EarthColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: EarthColors.cardSurface,
                    title: const Text(
                      'PEOPLE & RELATIONSHIPS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: EarthColors.goldMetallic,
                      ),
                    ),
                    content: const Text(
                      '• Review the people who carry this family story forward.\n\n• Select a family member to understand their role, history, and readiness to carry responsibility.\n\n• Formal succession choices are managed from Life & Legacy.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Ancestor Cards List Container
        Container(
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
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
                        : const BorderSide(color: EarthColors.borderSubtle),
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
        const SizedBox(height: 12),
        // Right/Selected Member Dossier Inspector Panel Container
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
          ),
          padding: const EdgeInsets.all(16),
          child: _selectedMember != null
              ? _buildMemberInspectorContent(_selectedMember!)
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Select a family member above to inspect their story, responsibilities, and contribution.',
                      style:
                          TextStyle(color: EarthColors.textMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildFamilyToday() {
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.goldMetallic.withAlpha(12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EarthColors.goldMetallic.withAlpha(75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FAMILY TODAY',
              style: TextStyle(
                  color: EarthColors.goldMetallic,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1)),
          const SizedBox(height: 8),
          Text(
            incumbent == null
                ? 'Your family has no recorded current head.'
                : '${incumbent['name'] ?? 'Current family head'} leads the family today.',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(familyStatus,
              style: const TextStyle(
                  color: EarthColors.textMuted, fontSize: 10.5)),
          const SizedBox(height: 4),
          Text(successionStatus,
              style: TextStyle(
                  color: successorName == null
                      ? Colors.orangeAccent
                      : EarthColors.cyanAccent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildFamilyIdentity(String direction) {
    final unlocked = _perks
        .map((perk) => perk['perk_name']?.toString())
        .whereType<String>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('FAMILY IDENTITY',
                style: TextStyle(
                    color: EarthColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1)),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  size: 14, color: EarthColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'About family identity',
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: EarthColors.cardSurface,
                  title: const Text('FAMILY IDENTITY',
                      style: TextStyle(
                          color: EarthColors.goldMetallic,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  content: const Text(
                      'Your family identity is shaped by the work, values, and choices you pass forward. It influences the practical advantages, heirlooms, and opportunities available to later generations.',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('CLOSE'))
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(direction,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
                unlocked.isEmpty
                    ? 'No family traditions are active yet.'
                    : 'Active traditions: ${unlocked.join(' · ')}',
                style: const TextStyle(
                    color: EarthColors.textMuted, fontSize: 10.5)),
          ]),
        ),
      ],
    );
  }

  Widget _buildMemberNodeCard(Map<String, dynamic> member, bool isSelected) {
    final gen = member['generation'] ?? 1;
    final name = member['name'] ?? 'Dynastic Heir';
    final title = member['title'] ?? 'Dynastic Member';
    final isIncumbent = member['is_incumbent'] == true;
    final birth = member['birth_game_day'] ?? 1;
    final death = member['death_game_day'];
    final wealth = _parseNum(member['lifetime_wealth']);
    final legacy = member['legacy_score'] ?? 0;

    final cardBorderColor = isSelected
        ? EarthColors.goldMetallic
        : (isIncumbent ? EarthColors.cyanAccent : EarthColors.borderSubtle);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: cardBorderColor, width: isSelected ? 2.0 : 1.0),
        boxShadow: isSelected
            ? [
                BoxShadow(
                    color: EarthColors.goldMetallic.withAlpha(60),
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
                  ? EarthColors.cyanAccent.withAlpha(30)
                  : EarthColors.goldMetallic.withAlpha(20),
              border: Border.all(
                color: isIncumbent
                    ? EarthColors.cyanAccent
                    : EarthColors.goldMetallic,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                'GEN\n$gen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isIncumbent
                      ? EarthColors.cyanAccent
                      : EarthColors.goldMetallic,
                  fontWeight: FontWeight.bold,
                  fontSize: 8.5,
                  height: 1.1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5),
                    ),
                    if (isIncumbent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EarthColors.cyanAccent.withAlpha(25),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                              color: EarthColors.cyanAccent.withAlpha(100)),
                        ),
                        child: const Text(
                          'ACTIVE HEAD',
                          style: TextStyle(
                              color: EarthColors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 8.5),
                        ),
                      )
                    else
                      Text(
                        'Day $birth – Day ${death ?? 'Present'}',
                        style: const TextStyle(
                            color: EarthColors.textMuted, fontSize: 9.5),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title,
                    style: const TextStyle(
                        color: EarthColors.textMuted, fontSize: 10)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _nodeMiniStat('Wealth', '${wealth.toStringAsFixed(0)} CR'),
                    const SizedBox(width: 12),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: const TextStyle(color: EarthColors.textMuted, fontSize: 9)),
        Text(value,
            style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 9.5)),
      ],
    );
  }

  Widget _buildMemberInspectorContent(Map<String, dynamic> member) {
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
              style: const TextStyle(
                  color: EarthColors.goldMetallic,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8),
            ),
            if (isIncumbent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: EarthColors.cyanAccent.withAlpha(25),
                  borderRadius: BorderRadius.circular(3),
                  border:
                      Border.all(color: EarthColors.cyanAccent.withAlpha(100)),
                ),
                child: const Text(
                  'INCUMBENT',
                  style: TextStyle(
                      color: EarthColors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 8.5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(title,
            style:
                const TextStyle(color: EarthColors.textMuted, fontSize: 10.5)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
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
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: EarthColors.goldMetallic.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.goldMetallic.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ANCESTRAL EPITAPH & WILL',
                  style: TextStyle(
                      color: EarthColors.goldMetallic,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '"$epitaph"',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('HISTORICAL MILESTONES',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: EarthColors.textMuted, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          val,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _milestoneTileRow(String label, String value, IconData icon,
      {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: EarthColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: EarthColors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: EarthColors.textMuted, fontSize: 10)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _buildPerksSection() {
    final userPoints = _parseInt(_dynasty['legacy_points'], fallback: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'FAMILY TRADITIONS',
              style: TextStyle(
                color: EarthColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  size: 14, color: EarthColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: EarthColors.cardSurface,
                    title: const Text(
                      'FAMILY TRADITIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: EarthColors.goldMetallic,
                      ),
                    ),
                    content: const Text(
                      '• These traditions describe what your family is becoming known for.\n\n• Choose directions that shape future opportunities, relationships, and the abilities passed to later generations.\n\n• Legacy Points are a measure of influence, not money.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : const BorderSide(color: EarthColors.borderSubtle),
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
                            ? EarthColors.goldMetallic.withAlpha(30)
                            : EarthColors.cardSurface,
                        border: Border.all(
                          color: isUnlocked
                              ? EarthColors.goldMetallic
                              : EarthColors.borderSubtle,
                        ),
                      ),
                      child: Icon(
                        isUnlocked ? Icons.check_circle : Icons.lock_outline,
                        color: isUnlocked
                            ? EarthColors.goldMetallic
                            : EarthColors.textMuted,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: EarthColors.cyanAccent.withAlpha(25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  category.toUpperCase(),
                                  style: const TextStyle(
                                      color: EarthColors.cyanAccent,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(desc,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10.5)),
                          Text('Unlock Requirement: $cost Legacy Points',
                              style: const TextStyle(
                                  color: EarthColors.textMuted, fontSize: 9.5)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isUnlocked)
                      const Chip(
                        label: Text('ACTIVE TRAIT',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        backgroundColor: EarthColors.goldMetallic,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      ElevatedButton(
                        key: Key('btn-unlock-perk-$perkKey'),
                        onPressed: (_isActionInProgress || !canAfford)
                            ? null
                            : () => _unlockPerk(perkKey, name),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: EarthColors.goldMetallic,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                        child: Text(_isActionInProgress
                            ? 'UNLOCKING...'
                            : 'UNLOCK ($cost LP)'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'FAMILY HEIRLOOMS & SHARED ASSETS',
              style: TextStyle(
                color: EarthColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  size: 14, color: EarthColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: EarthColors.cardSurface,
                    title: const Text(
                      'FAMILY HEIRLOOMS & SHARED ASSETS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: EarthColors.goldMetallic,
                      ),
                    ),
                    content: const Text(
                      '• Heirlooms are part of the family story, not ordinary equipment.\n\n• Each item records who created it, why it matters, and who currently carries its responsibility.\n\n• Equipped heirlooms transfer to the next generation through succession or Civic Rebirth and continue providing their gameplay benefit.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('CLOSE'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EarthColors.borderSubtle),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: isLast
                        ? BorderSide.none
                        : const BorderSide(color: EarthColors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.black.withAlpha(180),
                        border: Border.all(color: EarthColors.goldMetallic),
                      ),
                      child: Center(
                        child: Icon(
                          type == 'senate_gavel'
                              ? Icons.gavel
                              : (type == 'pioneer_chronometer'
                                  ? Icons.access_time
                                  : Icons.verified),
                          color: EarthColors.goldMetallic,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.amberAccent.withAlpha(120)),
                                ),
                                child: Text(
                                  quality.toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('Buff: $statBuff',
                              style: const TextStyle(
                                  color: EarthColors.cyanAccent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10.5)),
                          Text('"$inscription"',
                              style: const TextStyle(
                                  color: EarthColors.textMuted,
                                  fontSize: 9.5,
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      key: Key('btn-equip-heirloom-$id'),
                      onPressed: _isActionInProgress
                          ? null
                          : () => _equipHeirloom(id, name),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEquipped
                            ? Colors.grey[800]
                            : EarthColors.cyanAccent,
                        foregroundColor:
                            isEquipped ? Colors.white70 : Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                      child: Text(isEquipped ? 'UNEQUIP' : 'EQUIP TO HEAD'),
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
    if (val is num) return val.toInt();
    if (val is String)
      return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
    return fallback;
  }
}

class _LineageTreePainter extends CustomPainter {
  final List<Map<String, dynamic>> members;

  _LineageTreePainter({required this.members});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = EarthColors.goldMetallic.withAlpha(40)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    const startX = 38.0;
    canvas.drawLine(
        const Offset(startX, 20), Offset(startX, size.height - 20), paint);
  }

  @override
  bool shouldRepaint(covariant _LineageTreePainter oldDelegate) {
    return oldDelegate.members.length != members.length;
  }
}
