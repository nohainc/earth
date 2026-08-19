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

  const DynastyTreeDialog({
    super.key,
    required this.api,
    this.state,
    this.initialMemberId,
    this.isPageMode = false,
    this.onNavigate,
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
    _tabController = TabController(length: 3, vsync: this);
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
      final dynastyData = Map<String, dynamic>.from(res['dynasty'] as Map? ?? {});
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
          _selectedMember = selected != null && selected.isNotEmpty ? selected : null;
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
          _successMessage = 'Hereditary Trait "$perkName" unlocked! ($remaining LP remaining)';
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
        final isEquipped = res['isEquipped'] == true || res['isEquipped'] == 'true';
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
    final mottoCtrl = TextEditingController(text: _dynasty['motto']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: _dynasty['dynasty_name']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: EarthColors.panelSurface,
        title: const Row(
          children: [
            Icon(Icons.edit, color: EarthColors.goldMetallic, size: 18),
            SizedBox(width: 8),
            Text('EDIT DYNASTY CREED', style: TextStyle(color: EarthColors.goldMetallic, fontSize: 13, fontWeight: FontWeight.bold)),
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
                labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 11),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mottoCtrl,
              decoration: const InputDecoration(
                labelText: 'House Motto / Creed',
                labelStyle: TextStyle(color: EarthColors.textMuted, fontSize: 11),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: EarthColors.textMuted, fontSize: 11)),
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
                  setState(() => _successMessage = 'Dynasty creed updated successfully.');
                  await _loadDynastyData();
                }
              } catch (e) {
                if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: EarthColors.goldMetallic, foregroundColor: Colors.black),
            child: const Text('SAVE CREED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
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

    final dynastyName = (_dynasty['dynasty_name'] ?? 'House Vance').toString();
    final motto = (_dynasty['motto'] ?? 'From the Red Dust We Build Eternity').toString();
    final legacyPoints = _dynasty['legacy_points'] ?? 0;
    final totalWealth = _parseNum(_dynasty['total_wealth_generated']);

    Widget content = Container(
      width: widget.isPageMode ? double.infinity : dialogWidth,
      height: widget.isPageMode ? 740 : dialogHeight,
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : canvasColor,
        borderRadius: widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
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
        borderRadius: widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(14),
        child: Column(
          children: [
            _buildTopHeader(dynastyName, motto, legacyPoints, totalWealth),
            if (_error != null) _buildAlertBanner(_error!, isError: true),
            if (_successMessage != null) _buildAlertBanner(_successMessage!, isError: false),
            Expanded(
              child: _loading && _lineage.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: EarthColors.goldMetallic))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLineageTreeTab(),
                        _buildPerksMatrixTab(),
                        _buildHeirloomsVaultTab(),
                      ],
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

  Widget _buildTopHeader(String dynastyName, String motto, dynamic legacyPoints, double totalWealth) {
    return Container(
      padding: widget.isPageMode
          ? const EdgeInsets.only(bottom: 10)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : EarthColors.cardSurface,
        border: widget.isPageMode
            ? null
            : const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: widget.isPageMode
                          ? EarthColors.textMuted
                          : EarthColors.goldMetallic,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
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
                              const SizedBox(width: 8),
                              InkWell(
                                key: const Key('btn-edit-motto-dialog'),
                                onTap: _showEditMottoDialog,
                                child: const Icon(Icons.edit, size: 13, color: EarthColors.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '"$motto"',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerStatPill('LEGACY POINTS', '$legacyPoints LP', Icons.auto_awesome, EarthColors.goldMetallic),
                  const SizedBox(width: 8),
                  _headerStatPill('TOTAL WEALTH', '${totalWealth.toStringAsFixed(0)} CR', Icons.account_balance_wallet, EarthColors.cyanAccent),
                  const SizedBox(width: 8),
                  if (widget.isPageMode)
                    InkWell(
                      onTap: () {
                        if (widget.onNavigate != null) {
                          widget.onNavigate!('command');
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: EarthColors.goldMetallic.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: EarthColors.goldMetallic.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back, size: 11, color: EarthColors.goldMetallic),
                            SizedBox(width: 4),
                            Text(
                              'RETURN TO COMMAND',
                              style: TextStyle(
                                color: EarthColors.goldMetallic,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: EarthColors.goldMetallic,
            labelColor: EarthColors.goldMetallic,
            unselectedLabelColor: EarthColors.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            tabs: const [
              Tab(icon: Icon(Icons.account_tree_outlined, size: 15), text: 'LINEAGE TREE & ANCESTRY'),
              Tab(icon: Icon(Icons.stars_outlined, size: 15), text: 'HEREDITARY TRAITS MATRIX'),
              Tab(icon: Icon(Icons.military_tech_outlined, size: 15), text: 'HEIRLOOMS & RELICS VAULT'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStatPill(String label, String value, IconData icon, Color color) {
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
          Text('$label: ', style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10.5)),
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
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: EarthColors.textMuted),
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

  Widget _buildLineageTreeTab() {
    return Row(
      children: [
        // Left Generational Tree Canvas & Cards
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFF0A0C16),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: _LineageTreePainter(members: _lineage),
                ),
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lineage.length,
                  itemBuilder: (context, index) {
                    final member = _lineage[index];
                    final isSelected = _selectedMember?['id'] == member['id'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => setState(() => _selectedMember = member),
                        borderRadius: BorderRadius.circular(8),
                        child: _buildMemberNodeCard(member, isSelected),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        // Right Ancestor Dossier / Inspector
        Container(
          width: 360,
          decoration: const BoxDecoration(
            color: EarthColors.cardSurface,
            border: Border(left: BorderSide(color: EarthColors.borderSubtle)),
          ),
          child: _selectedMember != null
              ? _buildMemberInspector(_selectedMember!)
              : const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Select a dynastic ancestor or heir from the tree to inspect their historical dossier.',
                      style: TextStyle(color: EarthColors.textMuted, fontSize: 11),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
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
        border: Border.all(color: cardBorderColor, width: isSelected ? 2.0 : 1.0),
        boxShadow: isSelected
            ? [BoxShadow(color: EarthColors.goldMetallic.withAlpha(60), blurRadius: 10)]
            : [],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isIncumbent ? EarthColors.cyanAccent.withAlpha(30) : EarthColors.goldMetallic.withAlpha(20),
              border: Border.all(
                color: isIncumbent ? EarthColors.cyanAccent : EarthColors.goldMetallic,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                'GEN\n$gen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isIncumbent ? EarthColors.cyanAccent : EarthColors.goldMetallic,
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
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    if (isIncumbent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: EarthColors.cyanAccent.withAlpha(25),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: EarthColors.cyanAccent.withAlpha(100)),
                        ),
                        child: const Text(
                          'ACTIVE HEAD',
                          style: TextStyle(color: EarthColors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 8.5),
                        ),
                      )
                    else
                      Text(
                        'Day $birth – Day ${death ?? 'Present'}',
                        style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(title, style: const TextStyle(color: EarthColors.textMuted, fontSize: 10)),
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
        Text('$label: ', style: const TextStyle(color: EarthColors.textMuted, fontSize: 9)),
        Text(value, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 9.5)),
      ],
    );
  }

  Widget _buildMemberInspector(Map<String, dynamic> member) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GENERATION $gen DOSSIER',
                style: const TextStyle(color: EarthColors.goldMetallic, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              if (isIncumbent)
                const Chip(
                  label: Text('INCUMBENT', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold)),
                  backgroundColor: EarthColors.cyanAccent,
                  labelPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5)),
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
                _inspectorRow('Chronological Lifespan', 'Day $birth – ${death != null ? 'Day $death' : 'Living'}'),
                const SizedBox(height: 4),
                _inspectorRow('Status / Cause', cause),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EarthColors.goldMetallic.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.goldMetallic.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ANCESTRAL EPITAPH & WILL', style: TextStyle(color: EarthColors.goldMetallic, fontSize: 9.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '"$epitaph"',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          const Text('HISTORICAL MILESTONES', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _milestoneTile('Lifetime Wealth Generated', '${wealth.toStringAsFixed(0)} CR', Icons.account_balance),
          _milestoneTile('Corporations & Enterprises Founded', '$businesses Enterprises', Icons.business),
          _milestoneTile('World Senate Proposals Passed', '$proposals Enacted', Icons.gavel),
          _milestoneTile('Generational Legacy Contribution', '$legacy LP', Icons.auto_awesome),
        ],
      ),
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
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _milestoneTile(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: EarthColors.panelSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: EarthColors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: EarthColors.textMuted, fontSize: 10)),
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _buildPerksMatrixTab() {
    final userPoints = _parseInt(_dynasty['legacy_points'], fallback: 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _catalogPerks.length,
      itemBuilder: (context, index) {
        final perk = _catalogPerks[index];
        final perkKey = perk['key']?.toString() ?? '';
        final name = perk['name']?.toString() ?? 'Trait';
        final category = perk['category']?.toString() ?? 'Operations';
        final cost = _parseInt(perk['cost'], fallback: 100);
        final desc = perk['description']?.toString() ?? '';

        final isUnlocked = _perks.any((p) => p['perk_key'] == perkKey);
        final canAfford = userPoints >= cost;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnlocked ? EarthColors.goldMetallic.withAlpha(15) : EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isUnlocked ? EarthColors.goldMetallic : EarthColors.borderSubtle,
              width: isUnlocked ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isUnlocked ? EarthColors.goldMetallic.withAlpha(30) : EarthColors.cardSurface,
                  border: Border.all(
                    color: isUnlocked ? EarthColors.goldMetallic : EarthColors.borderSubtle,
                  ),
                ),
                child: Icon(
                  isUnlocked ? Icons.check_circle : Icons.lock_outline,
                  color: isUnlocked ? EarthColors.goldMetallic : EarthColors.textMuted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EarthColors.cyanAccent.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            category.toUpperCase(),
                            style: const TextStyle(color: EarthColors.cyanAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text('Unlock Requirement: $cost Legacy Points', style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isUnlocked)
                const Chip(
                  label: Text('ACTIVE TRAIT', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black)),
                  backgroundColor: EarthColors.goldMetallic,
                )
              else
                ElevatedButton(
                  key: Key('btn-unlock-perk-$perkKey'),
                  onPressed: (_isActionInProgress || !canAfford) ? null : () => _unlockPerk(perkKey, name),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EarthColors.goldMetallic,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  child: Text(_isActionInProgress ? 'UNLOCKING...' : 'UNLOCK ($cost LP)'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeirloomsVaultTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _heirlooms.length,
      itemBuilder: (context, index) {
        final heirloom = _heirlooms[index];
        final id = heirloom['id']?.toString() ?? '';
        final name = heirloom['name']?.toString() ?? 'Ancestral Relic';
        final type = heirloom['heirloom_type']?.toString() ?? 'founder_seal';
        final quality = heirloom['quality_tier']?.toString() ?? 'Legendary';
        final statBuff = heirloom['stat_buff']?.toString() ?? '+10% Prestige';
        final inscription = heirloom['inscription']?.toString() ?? 'An ancient seal.';
        final rawEquipped = heirloom['equipped_by_human_id'];
        final isEquipped = rawEquipped != null && rawEquipped != 'null' && rawEquipped.toString().trim().isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isEquipped ? EarthColors.cyanAccent.withAlpha(15) : EarthColors.panelSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isEquipped ? EarthColors.cyanAccent : EarthColors.goldMetallic.withAlpha(100),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.black.withAlpha(180),
                  border: Border.all(color: EarthColors.goldMetallic),
                ),
                child: Center(
                  child: Icon(
                    type == 'senate_gavel'
                        ? Icons.gavel
                        : (type == 'pioneer_chronometer' ? Icons.access_time : Icons.verified),
                    color: EarthColors.goldMetallic,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amberAccent.withAlpha(120)),
                          ),
                          child: Text(
                            quality.toUpperCase(),
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text('Buff: $statBuff', style: const TextStyle(color: EarthColors.cyanAccent, fontWeight: FontWeight.w600, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text('"$inscription"', style: const TextStyle(color: EarthColors.textMuted, fontSize: 10, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                key: Key('btn-equip-heirloom-$id'),
                onPressed: _isActionInProgress ? null : () => _equipHeirloom(id, name),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isEquipped ? Colors.grey[800] : EarthColors.cyanAccent,
                  foregroundColor: isEquipped ? Colors.white70 : Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                child: Text(isEquipped ? 'UNEQUIP' : 'EQUIP TO HEAD'),
              ),
            ],
          ),
        );
      },
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  static int _parseInt(dynamic val, {int fallback = 0}) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? double.tryParse(val)?.toInt() ?? fallback;
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
    canvas.drawLine(const Offset(startX, 20), Offset(startX, size.height - 20), paint);
  }

  @override
  bool shouldRepaint(covariant _LineageTreePainter oldDelegate) {
    return oldDelegate.members.length != members.length;
  }
}
