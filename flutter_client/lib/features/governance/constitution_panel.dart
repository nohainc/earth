import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class ConstitutionPanel extends StatefulWidget {
  final EarthState state;
  final Future<Map<String, dynamic>> Function()? canonicalLoader;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> changes)? onPreviewAmendment;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> changes)? onProposeAmendment;

  const ConstitutionPanel(
      {super.key,
      required this.state,
      this.canonicalLoader,
      this.onPreviewAmendment,
      this.onProposeAmendment});

  @override
  State<ConstitutionPanel> createState() => _ConstitutionPanelState();
}

class _ConstitutionPanelState extends State<ConstitutionPanel> {
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loader = widget.canonicalLoader;
    if (loader == null) return _buildContent(context, null);
    return FutureBuilder<Map<String, dynamic>>(
      future: loader(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data?['ok'] == false) {
          return _buildContent(context, null, canonicalUnavailable: true);
        }
        return _buildContent(context, snapshot.data);
      },
    );
  }

  List<Map<String, dynamic>> _resolveAllRules(
      Map<String, dynamic>? canonical) {
    final canonicalDefinitions = canonical?['definitions'];
    if (canonicalDefinitions is List && canonicalDefinitions.isNotEmpty) {
      return canonicalDefinitions.whereType<Map>().map((definition) {
        final row = Map<String, dynamic>.from(definition);
        final article = row['article_code']?.toString().toUpperCase() ?? '';
        return {
          'id': row['rule_code'] ?? 'UNKNOWN_RULE',
          'rule_number': article,
          'title': row['rule_code'] ?? 'Constitutional rule',
          'description':
              'Typed ${row['value_type'] ?? 'policy'} rule under the $article article.',
          'category': _categoryForArticle(article),
          'authority_model': row['authority_model'],
        };
      }).toList(growable: false);
    }

    final serverRules = widget.state.json['constitutionalRules'] is List
        ? (widget.state.json['constitutionalRules'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList()
        : const <Map<String, dynamic>>[];

    // Constitutional text is authoritative only when it comes from the
    // server. Never merge it with client-maintained baseline articles: that
    // can produce a Constitution version that was never adopted.
    return serverRules;
  }

  String _categoryForArticle(String article) {
    switch (article) {
      case 'TAXATION':
        return 'TAXATION & FISCAL';
      case 'CORPORATION_GOVERNANCE':
        return 'DEMOCRACY & GOVERNANCE';
      case 'TERRITORY_CAPACITY':
        return 'RESOURCES & PROPERTY';
      default:
        return 'AMENDMENTS & CONSTITUTION';
    }
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic>? canonical,
      {bool canonicalUnavailable = false}) {
    final allRules = _resolveAllRules(canonical);
    final serverRules = widget.state.json['constitutionalRules'];
    final canonicalDefinitions = canonical?['definitions'];
    final hasCanonicalRules = canonicalDefinitions is List &&
        canonicalDefinitions.isNotEmpty;
    final hasServerRules = !canonicalUnavailable &&
        (hasCanonicalRules || (serverRules is List && serverRules.isNotEmpty));
    final query = _searchQuery.trim().toLowerCase();

    final filteredRules = allRules.where((rule) {
      final matchesCat = _selectedCategory == 'ALL' ||
          (rule['category']?.toString().toUpperCase() == _selectedCategory);
      if (!matchesCat) return false;

      if (query.isEmpty) return true;
      final title = rule['title']?.toString().toLowerCase() ?? '';
      final desc = rule['description']?.toString().toLowerCase() ?? '';
      final code = rule['rule_number']?.toString().toLowerCase() ?? '';
      final id = rule['id']?.toString().toLowerCase() ?? '';
      final cat = rule['category']?.toString().toLowerCase() ?? '';
      return title.contains(query) ||
          desc.contains(query) ||
          code.contains(query) ||
          id.contains(query) ||
          cat.contains(query);
    }).toList();

    final constitutionalChanges = widget.state.history['events'] is List
        ? (widget.state.history['events'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .where((event) {
              final type = event['event_type']?.toString().toLowerCase() ?? '';
              return type == 'constitutional_amendment_enacted' ||
                  type == 'constitution_amended' ||
                  type == 'organization_charter_amended' ||
                  type == 'territory_charter_amended';
            })
            .take(12)
            .toList()
        : const <Map<String, dynamic>>[];

    final categories = [
      'ALL',
      'TIME & SETTLEMENT',
      'MONETARY & LEDGER',
      'RESOURCES & PROPERTY',
      'DYNASTY & SUCCESSION',
      'MARKET & COMMERCE',
      'TAXATION & FISCAL',
      'SUBSIDIARITY & INSTITUTIONS',
      'DEMOCRACY & GOVERNANCE',
      'RESEARCH & PATENTS',
      'AMENDMENTS & CONSTITUTION',
    ];

    final cockpit = EarthPageCockpit(
      status: 'SUPREME LAW',
      statusColor: context.primaryColor,
      infoTitle: 'PLANETARY CONSTITUTION & LEGAL ORDER',
      infoDescription:
          '• Supreme Law: The highest legal baseline across Earth. All Corporation policies must conform to constitutional invariants.\n\n• V5 Governance Scopes:\n  1. Earth Baseline (global statutes, fiscal policy, and unalienable citizen rights)\n  2. Corporation Policy (membership, pooled capacity, operations, and Corporation services)\n\n• Precedence: Corporation policy operates within the Earth baseline. Standalone Territory records are capacity containers, not a third government tier.',
      title: 'PLANETARY CONSTITUTION',
      subtitle:
          'Supreme legal architecture and governance override hierarchy across Earth',
      metrics: [
        CockpitMetric(
          label: 'Statutes',
          value: '${allRules.length}',
          icon: Icons.gavel_outlined,
          color: context.primaryColor,
        ),
        CockpitMetric(
          label: 'Hierarchy',
          value: '3 Tiers',
          icon: Icons.account_tree_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Amendments',
          value: '${constitutionalChanges.length}',
          icon: Icons.history_outlined,
          color: context.warningColor,
        ),
      ],
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cockpit,
          const SizedBox(height: 28),
          _buildTierFlow(context),
          const SizedBox(height: 24),

          if (canonical != null) ...[
            _buildCanonicalPolicyValues(context, canonical),
            const SizedBox(height: 24),
          ],

          if (canonicalUnavailable) ...[
            _buildCanonicalUnavailable(context),
            const SizedBox(height: 20),
          ],

          if (!hasServerRules)
            Container(
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.warningColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(
                    color: context.warningColor.withValues(alpha: .35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      color: context.warningColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CONSTITUTION UNAVAILABLE\n\nThe current canonical Constitution could not be verified from the server. No local or reconstructed articles are shown because they could be outdated or never adopted.',
                      style: context.bodyStyle,
                    ),
                  ),
                ],
              ),
            ),
          if (!hasServerRules) const SizedBox(height: 20),

          // Search & Filters
          _buildSearchAndFilters(context, categories),
          const SizedBox(height: 20),

          // Constitution Statutes Section
          EarthSection(
            title: 'CONSTITUTIONAL STATUTES (${filteredRules.length})',
            showHeader: true,
            showSurface: false,
            child: !hasServerRules
                ? const EarthEmptyState(
                    message:
                        'The constitutional rule registry is unavailable. Retry after the canonical feed is restored.',
                    icon: Icons.gavel_outlined,
                  )
                : filteredRules.isEmpty
                    ? const EarthEmptyState(
                        message:
                            'No constitutional statutes match your search query.',
                        icon: Icons.search_off_outlined,
                      )
                    : _buildStatuteList(context, filteredRules),
          ),

          SizedBox(height: context.spacingSection),

          EarthSection(
            title: 'CONSTITUTIONAL HISTORY & AMENDMENTS',
            showSurface: false,
            child: constitutionalChanges.isEmpty
                ? const EarthEmptyState(
                    message:
                        'No constitutional or charter amendments have been recorded yet in this epoch.',
                    icon: Icons.history_outlined,
                  )
                : EarthDataList(
                    children: constitutionalChanges.indexed.map((indexed) {
                      final event = indexed.$2;
                      return EarthDataRow(
                        title: event['title']?.toString() ?? 'Rule change',
                        subtitle:
                            'Game day ${event['game_day'] ?? '—'} · ${event['event_type'] ?? 'governance'}',
                        leading: Icon(
                          Icons.history_outlined,
                          size: context.iconSize,
                          color: context.secondaryColor,
                        ),
                        showDivider:
                            indexed.$1 != constitutionalChanges.length - 1,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanonicalUnavailable(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.warningColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.warningColor.withValues(alpha: .35)),
      ),
      child: Text(
        'CANONICAL CONSTITUTION UNAVAILABLE\n\nThe server could not verify the effective rule set for this game day. Current policy values are hidden until the canonical feed is restored.',
        style: context.bodyStyle,
      ),
    );
  }

  Widget _buildCanonicalPolicyValues(
      BuildContext context, Map<String, dynamic> canonical) {
    final rawRules = canonical['rules'];
    final rules = rawRules is Map
        ? rawRules.entries
            .map((entry) => MapEntry(entry.key.toString(), entry.value))
            .toList(growable: false)
        : const <MapEntry<String, dynamic>>[];
    final versionIds = canonical['versionIds'] is Map
        ? Map<String, dynamic>.from(canonical['versionIds'] as Map)
        : const <String, dynamic>{};
    final provenance = canonical['provenance'] is Map
        ? Map<String, dynamic>.from(canonical['provenance'] as Map)
        : const <String, dynamic>{};
    final scheduled = canonical['scheduledChanges'] is List
        ? (canonical['scheduledChanges'] as List).whereType<Map>().toList()
        : const <Map>[];
    final history = canonical['history'] is List
        ? (canonical['history'] as List).whereType<Map>().take(24).toList()
        : const <Map>[];
    final definitions = canonical['definitions'] is List
        ? (canonical['definitions'] as List).whereType<Map>().toList()
        : const <Map>[];
    final earthRules = canonical['earthRules'] is Map
        ? Map<String, dynamic>.from(canonical['earthRules'] as Map)
        : const <String, dynamic>{};
    final earthVersionIds = canonical['earthVersionIds'] is Map
        ? Map<String, dynamic>.from(canonical['earthVersionIds'] as Map)
        : const <String, dynamic>{};
    return Column(
      children: [
        if (earthRules.isNotEmpty)
          EarthSection(
            title: 'EARTH BASELINE POLICY · DAY ${canonical['gameDay'] ?? '—'}',
            showSurface: false,
            child: EarthDataList(
              children: earthRules.entries.map((entry) {
                final version = earthVersionIds[entry.key]?.toString();
                return EarthDataRow(
                  title: entry.key,
                  subtitle: [
                    _formatCanonicalValue(entry.value),
                    if (version != null) version,
                  ].join(' · '),
                  leading: Icon(Icons.public_outlined,
                      size: context.iconSize, color: context.secondaryColor),
                  showDivider: entry.key != earthRules.keys.last,
                );
              }).toList(),
            ),
          ),
        EarthSection(
          title: 'CURRENT CONSTITUTION POLICY · DAY ${canonical['gameDay'] ?? '—'}',
          showSurface: false,
          child: rules.isEmpty
              ? const EarthEmptyState(
                  message: 'No effective typed policy values are available.',
                  icon: Icons.rule_outlined,
                )
              : EarthDataList(
                  children: rules.map((entry) {
                    final value = _formatCanonicalValue(entry.value);
                    final version = versionIds[entry.key]?.toString();
                    final source = provenance[entry.key]?.toString();
                    final scheduleRows = canonical['scheduleBrackets'] is Map
                        ? (canonical['scheduleBrackets'] as Map)[entry.value.toString()]
                        : null;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        EarthDataRow(
                          title: entry.key,
                          subtitle: [
                            value,
                            if (source != null) 'SOURCE $source',
                            if (version != null) version,
                          ].join(' · '),
                          leading: Icon(Icons.rule_outlined,
                              size: context.iconSize, color: context.primaryColor),
                          showDivider: scheduleRows is! List && entry.key != rules.last.key,
                        ),
                        if (scheduleRows is List && scheduleRows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 44, right: 12, bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PROGRESSIVE BRACKETS', style: context.captionStyle.copyWith(color: context.mutedColor)),
                                const SizedBox(height: 4),
                                for (final bracket in scheduleRows.whereType<Map>())
                                  Text(_formatBracket(bracket), style: context.captionStyle),
                              ],
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
        ),
        if (widget.onProposeAmendment != null && definitions.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: EarthButton(
                label: 'PROPOSE AMENDMENT',
                variant: EarthButtonVariant.primary,
                onPressed: () => _openAmendmentComposer(context, canonical, definitions),
              ),
            ),
          ),
        if (scheduled.isNotEmpty)
          EarthSection(
            title: 'SCHEDULED CONSTITUTION CHANGES',
            showSurface: false,
            child: EarthDataList(
              children: scheduled.map((change) {
                final value = change['value_json'] is Map
                    ? _formatCanonicalValue(change['value_json'])
                    : '—';
                return EarthDataRow(
                  title: change['rule_code']?.toString() ?? 'Rule',
                  subtitle: 'DAY ${change['effective_from_game_day'] ?? '—'} · $value',
                  leading: Icon(Icons.schedule_outlined,
                      size: context.iconSize, color: context.primaryColor),
                  showDivider: change != scheduled.last,
                );
              }).toList(),
            ),
          ),
        if (history.isNotEmpty)
          EarthSection(
            title: 'CONSTITUTION RULE HISTORY',
            showSurface: false,
            child: EarthDataList(
              children: history.map((version) {
                final value = version['value_json'] is Map
                    ? _formatCanonicalValue(version['value_json'])
                    : '—';
                final status = version['status']?.toString() ?? '—';
                final proposal = version['proposal_id']?.toString();
                return EarthDataRow(
                  title: version['rule_code']?.toString() ?? 'Rule',
                  subtitle: 'DAY ${version['effective_from_game_day'] ?? '—'} · $status · $value${proposal == null ? '' : ' · $proposal'}',
                  leading: Icon(Icons.history_edu_outlined,
                      size: context.iconSize, color: context.primaryColor),
                  showDivider: version != history.last,
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<void> _openAmendmentComposer(BuildContext context,
      Map<String, dynamic> canonical, List<Map> definitions) async {
    final corporationScope = canonical['corporationId']?.toString().isNotEmpty == true;
    final available = definitions.where((definition) {
      final authority = definition['authority_model']?.toString();
      return corporationScope
          ? authority != 'EARTH_LOCKED'
          : authority != 'CORPORATION_LOCAL';
    }).where((definition) {
      final type = definition['value_type']?.toString();
      // Schedule references are selectable by their canonical server-owned
      // ID. The server validates that the referenced schedule is active and
      // uses the same brackets during settlement; the client must not edit or
      // recreate the schedule definition locally.
      return ['BOOLEAN', 'INTEGER', 'CREDIT_UNITS', 'RATE_BPS', 'ENUM', 'GAME_DAYS', 'RESOURCE_UNITS', 'PROGRESSIVE_SCHEDULE_REF'].contains(type);
    }).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No scalar Constitution rules are available for amendment.')));
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        String selected = available.first['rule_code'].toString();
        String? error;
        final valueController = TextEditingController();
        return StatefulBuilder(builder: (context, setState) {
          final definition = available.firstWhere((item) => item['rule_code'].toString() == selected);
          final type = definition['value_type']?.toString() ?? 'INTEGER';
          final allowed = definition['allowed_values'] is List
              ? (definition['allowed_values'] as List).map((item) => item.toString()).toList()
              : const <String>[];
          return AlertDialog(
            title: const Text('PROPOSE CONSTITUTION AMENDMENT'),
            content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Rule'),
                  items: available.map((item) => DropdownMenuItem(value: item['rule_code'].toString(), child: Text(item['rule_code'].toString()))).toList(),
                  onChanged: (value) => setState(() { selected = value ?? selected; error = null; }),
                ),
                const SizedBox(height: 12),
                if (type == 'BOOLEAN')
                  DropdownButtonFormField<String>(
                    value: valueController.text.isEmpty ? null : valueController.text,
                    decoration: const InputDecoration(labelText: 'Value'),
                    items: const [DropdownMenuItem(value: 'true', child: Text('TRUE')), DropdownMenuItem(value: 'false', child: Text('FALSE'))],
                    onChanged: (value) => setState(() => valueController.text = value ?? ''),
                  )
                else if (type == 'ENUM' && allowed.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: allowed.contains(valueController.text) ? valueController.text : null,
                    decoration: const InputDecoration(labelText: 'Value'),
                    items: allowed.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: (value) => setState(() => valueController.text = value ?? ''),
                  )
                else
                  TextField(
                    controller: valueController,
                    keyboardType: type == 'PROGRESSIVE_SCHEDULE_REF' ? TextInputType.text : TextInputType.number,
                    decoration: InputDecoration(
                      labelText: type == 'PROGRESSIVE_SCHEDULE_REF' ? 'Canonical schedule ID' : '$type value',
                      helperText: type == 'PROGRESSIVE_SCHEDULE_REF' ? 'Use an active schedule ID from the server.' : null,
                    ),
                  ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('CANCEL')),
              FilledButton(onPressed: () {
                dynamic value;
                if (type == 'BOOLEAN') {
                  value = valueController.text == 'true' ? true : valueController.text == 'false' ? false : null;
                } else if (type == 'ENUM') {
                  value = valueController.text.isEmpty ? null : valueController.text;
                } else {
                  final parsed = BigInt.tryParse(valueController.text.trim());
                  value = parsed == null ? null : valueController.text.trim();
                }
                if (value == null) { setState(() => error = 'Enter a valid $type value.'); return; }
                Navigator.of(dialogContext).pop({'ruleCode': selected, 'value': value});
              }, child: const Text('CONTINUE')),
            ],
          );
        });
      },
    );
    if (result == null || !context.mounted || widget.onProposeAmendment == null) return;
    try {
      if (widget.onPreviewAmendment != null) {
        final preview = await widget.onPreviewAmendment!([result]);
        if (!context.mounted) return;
        if (preview['ok'] == false) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(preview['error']?.toString() ?? 'Amendment preview failed.')));
          return;
        }
        final proceed = await _confirmPreview(context, preview);
        if (!proceed || !context.mounted) return;
      }
      final response = await widget.onProposeAmendment!([result]);
      if (!context.mounted) return;
      final ok = response['ok'] != false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Constitution amendment proposal submitted.' : response['error']?.toString() ?? 'Amendment proposal failed.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Amendment proposal failed: $error')));
    }
  }

  Future<bool> _confirmPreview(BuildContext context, Map<String, dynamic> preview) async {
    final changes = preview['changes'] is List
        ? (preview['changes'] as List).whereType<Map>().toList()
        : const <Map>[];
    final effects = preview['progressiveEffects'] is List
        ? (preview['progressiveEffects'] as List).whereType<Map>().toList()
        : const <Map>[];
    final lines = <Widget>[
      Text('GAME DAY ${preview['gameDay'] ?? '—'} · SERVER-CALCULATED IMPACT', style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 12),
      for (final change in changes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(change['ruleCode']?.toString() ?? 'Rule'),
          subtitle: Text('${_formatCanonicalValue(change['currentValue'])}  →  ${_formatCanonicalValue(change['proposedValue'])}'),
        ),
      for (final effect in effects) ...[
        const Divider(),
        Text('PROGRESSIVE EFFECT · ${effect['ruleCode'] ?? 'RULE'}', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        ...((effect['effects'] is List ? effect['effects'] as List : const [])
            .whereType<Map>()
            .map((row) => Text(
                  'QTY ${row['current']?['quantity'] ?? '—'}: ${row['current']?['totalCharge'] ?? '—'} → ${row['proposed']?['totalCharge'] ?? '—'} (Δ ${row['delta'] ?? '—'})',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
      ],
    ];
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('REVIEW CONSTITUTION AMENDMENT'),
            content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines))),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('CANCEL')),
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('SUBMIT PROPOSAL')),
            ],
          ),
        ) ??
        false;
  }

  String _formatCanonicalValue(dynamic value) {
    if (value is List) {
      return value.map((item) => _formatCanonicalValue(item)).join(' · ');
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_formatCanonicalValue(entry.value)}')
          .join(', ');
    }
    return value?.toString() ?? '—';
  }

  String _formatBracket(Map bracket) {
    final lower = bracket['lower_bound_units']?.toString() ?? '0';
    final upper = bracket['upper_bound_units']?.toString();
    final numerator = bracket['marginal_multiplier_numerator']?.toString() ?? '—';
    final denominator = bracket['marginal_multiplier_denominator']?.toString() ?? '—';
    return '$lower–${upper ?? '∞'} · ×$numerator/$denominator';
  }

  Widget _buildSearchAndFilters(BuildContext context, List<String> categories) {
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
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: context.bodyStyle,
            decoration: InputDecoration(
              hintText: 'Search statutes, articles, keywords, or codes...',
              hintStyle:
                  context.captionStyle.copyWith(color: context.mutedColor),
              prefixIcon:
                  Icon(Icons.search, color: context.primaryColor, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: context.panelColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.subtleBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.subtleBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color:
                            isSelected ? context.panelColor : context.inkColor,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: context.primaryColor,
                    backgroundColor: context.panelColor,
                    checkmarkColor: context.panelColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(
                        color: isSelected
                            ? context.primaryColor
                            : context.subtleBorderColor,
                      ),
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierFlow(BuildContext context) {
    Widget tier(IconData icon, String label, String detail, Color color) =>
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: context.iconSize + 4),
              const SizedBox(height: 6),
              Text(label,
                  textAlign: TextAlign.center, style: context.widgetValueStyle),
              const SizedBox(height: 2),
              Text(detail,
                  textAlign: TextAlign.center, style: context.captionStyle),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        children: [
          Text(
            'Rule Precedence: Earth Baseline → Corporation Policy → Community and capacity administration',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              tier(Icons.public_outlined, 'EARTH', 'Constitutional baseline',
                  context.primaryColor),
              Icon(Icons.arrow_forward_rounded, color: context.mutedColor),
              tier(Icons.domain_outlined, 'ORGANIZATION', 'Corporate policy',
                  context.secondaryColor),
              Icon(Icons.arrow_forward_rounded, color: context.mutedColor),
              tier(Icons.location_on_outlined, 'TERRITORY',
                  'Local commons charter', context.warningColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatuteList(
      BuildContext context, List<Map<String, dynamic>> rules) {
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final rule in rules) {
      final part = int.tryParse(rule['part_number']?.toString() ?? '') ?? 1;
      grouped.putIfAbsent(part, () => []).add(rule);
    }

    final partTitles = {
      1: 'PART 1 · TIME & SETTLEMENT',
      2: 'PART 2 · MONETARY SYSTEM',
      3: 'PART 3 · RESOURCES & PROPERTY',
      4: 'PART 4 · DYNASTY CONTINUITY',
      5: 'PART 5 · PRODUCTION & MARKETS',
      6: 'PART 6 · TAXATION & PUBLIC LEDGER',
      7: 'PART 7 · SUBSIDIARITY & INSTITUTIONS',
      8: 'PART 8 · DEMOCRATIC GOVERNANCE',
      9: 'PART 9 · TECHNOLOGY & PATENTS',
      10: 'PART 10 · CONSTITUTIONAL AMENDMENTS',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries.map((entry) {
        final rows = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: context.spacingTopic),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partTitles[entry.key] ?? 'PART ${entry.key}',
                style: context.topicTitleStyle,
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  border: Border.all(color: context.subtleBorderColor),
                ),
                child: Column(
                  children: rows.asMap().entries.map((indexed) {
                    final rule = indexed.value;
                    final isLast = indexed.key == rows.length - 1;
                    return _buildStatuteCard(context, rule, isLast: isLast);
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatuteCard(BuildContext context, Map<String, dynamic> rule,
      {required bool isLast}) {
    final invariant = rule['invariant'] == true ||
        rule['immutability']?.toString().toUpperCase() == 'INVARIANT';
    final overridePolicy = rule['override_policy']?.toString().toUpperCase();
    final status = invariant
        ? 'INVARIANT'
        : overridePolicy == 'LOCAL_ALLOWED'
            ? 'LOCAL OVERRIDE'
            : 'AMENDABLE';
    final id = rule['id']?.toString() ?? '';
    final code = rule['rule_number']?.toString() ?? '';
    final title = rule['title']?.toString() ?? 'Statute';
    final desc = rule['description']?.toString() ?? '';
    final defaultValue = rule['default_value']?.toString() ?? 'Baseline';
    final permitted = rule['permitted_values']?.toString();
    final authority = rule['authority']?.toString() ?? 'EARTH';

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: context.subtleBorderColor),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.primaryColor.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  code.isNotEmpty ? code : id,
                  style: context.captionStyle.copyWith(
                    color: context.primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.topicTitleStyle),
                    if (id.isNotEmpty && id != code) ...[
                      const SizedBox(height: 2),
                      Text(
                        id,
                        style: context.captionStyle.copyWith(
                          color: context.mutedColor,
                          fontSize: 10,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              EarthBadge(
                label: status,
                customColor:
                    invariant ? context.primaryColor : context.secondaryColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(desc, style: context.bodyStyle),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.panelColor.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('STATUTORY DEFAULT',
                          style: context.captionStyle
                              .copyWith(color: context.mutedColor)),
                      const SizedBox(height: 2),
                      Text(defaultValue,
                          style: context.bodyStyle
                              .copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (permitted != null && permitted.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PERMITTED RANGE / VALUES',
                            style: context.captionStyle
                                .copyWith(color: context.mutedColor)),
                        const SizedBox(height: 2),
                        Text(permitted,
                            style: context.bodyStyle
                                .copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('AUTHORITY',
                        style: context.captionStyle
                            .copyWith(color: context.mutedColor)),
                    const SizedBox(height: 2),
                    Text(authority,
                        style: context.bodyStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.primaryColor,
                        )),
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
