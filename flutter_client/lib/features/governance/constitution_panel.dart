import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/constitution_models.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';

class ConstitutionPanel extends StatefulWidget {
  final EarthState state;
  final Future<Map<String, dynamic>> Function()? canonicalLoader;
  final Future<Map<String, dynamic>> Function(
      List<Map<String, dynamic>> changes)? onPreviewAmendment;
  final Future<Map<String, dynamic>> Function(
      List<Map<String, dynamic>> changes)? onProposeAmendment;
  final ValueChanged<String>? onNavigate;

  const ConstitutionPanel(
      {super.key,
      required this.state,
      this.canonicalLoader,
      this.onPreviewAmendment,
      this.onProposeAmendment,
      this.onNavigate});

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

  List<ConstitutionRuleView> _resolveAllRules(Map<String, dynamic>? canonical) {
    final typedViews = canonical?['ruleViews'];
    if (typedViews is List && typedViews.isNotEmpty) {
      return typedViews
          .whereType<Map>()
          .map((row) =>
              ConstitutionRuleView.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
    }
    final canonicalDefinitions = canonical?['definitions'];
    if (canonicalDefinitions is List && canonicalDefinitions.isNotEmpty) {
      final resolvedRules = canonical?['rules'] is Map
          ? Map<String, dynamic>.from(canonical!['rules'] as Map)
          : const <String, dynamic>{};
      final versionIds = canonical?['versionIds'] is Map
          ? Map<String, dynamic>.from(canonical!['versionIds'] as Map)
          : const <String, dynamic>{};
      final provenance = canonical?['provenance'] is Map
          ? Map<String, dynamic>.from(canonical!['provenance'] as Map)
          : const <String, dynamic>{};
      return canonicalDefinitions.whereType<Map>().map((definition) {
        final row = Map<String, dynamic>.from(definition);
        final article = row['article_code']?.toString().toUpperCase() ?? '';
        final code = row['rule_code']?.toString() ?? 'UNKNOWN_RULE';
        return ConstitutionRuleView.fromJson({
          'code': code,
          'articleCode': article,
          'displayName': _displayRuleTitle(code),
          'description': _ruleDescription(code, article, row['value_type']),
          'valueType': row['value_type'],
          'authorityModel': row['authority_model'],
          'amendmentClass': row['amendment_class'],
          'policyGroup': row['policy_group'],
          'allowedValues': row['allowed_values'],
          'resolved': {
            'value': resolvedRules[code],
            'source': provenance[code],
            'versionId': versionIds[code],
          },
        });
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
    return serverRules.map((row) {
      final code = row['id']?.toString() ??
          row['rule_number']?.toString() ??
          'UNKNOWN_RULE';
      return ConstitutionRuleView.fromJson({
        'code': code,
        'articleCode': row['category']?.toString() ?? 'OTHER_POLICY',
        'displayName': row['title']?.toString() ?? 'Constitutional rule',
        'description': row['description']?.toString() ?? '',
        'valueType': 'LEGACY',
        'authorityModel': row['invariant'] == true ? 'EARTH_LOCKED' : 'UNKNOWN',
        'resolved': {'value': row['default_value']},
      });
    }).toList(growable: false);
  }

  String _categoryForArticle(String article) {
    switch (article.toUpperCase()) {
      case 'TAXATION':
        return 'TAXATION & FISCAL';
      case 'EARTH_GOVERNANCE':
        return 'EARTH GOVERNANCE';
      case 'CORPORATION_GOVERNANCE':
        return 'CORPORATION GOVERNANCE';
      case 'TERRITORY_CAPACITY':
        return 'CAPACITY & SCARCITY';
      case 'SUCCESSION':
        return 'SUCCESSION';
      default:
        return article.isEmpty ? 'OTHER POLICY' : article.replaceAll('_', ' ');
    }
  }

  String _categoryForRule(ConstitutionRuleView rule) {
    if (rule.articleLabel.isNotEmpty && rule.articleLabel != rule.articleCode) {
      return rule.articleLabel;
    }
    return _categoryForArticle(rule.articleCode);
  }

  String _displayRuleTitle(String code) {
    final parts = code.split('.');
    final name = parts.isEmpty ? code : parts.last;
    return name
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _ruleDescription(String code, String article, dynamic valueType) {
    final type =
        valueType?.toString().replaceAll('_', ' ').toLowerCase() ?? 'policy';
    return 'Canonical $type rule in the ${_categoryForArticle(article)} policy article ($code).';
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic>? canonical,
      {bool canonicalUnavailable = false}) {
    final allRules = _resolveAllRules(canonical);
    final serverRules = widget.state.json['constitutionalRules'];
    final canonicalDefinitions = canonical?['definitions'];
    final hasCanonicalRules =
        (canonicalDefinitions is List && canonicalDefinitions.isNotEmpty) ||
            (canonical?['ruleViews'] is List &&
                (canonical!['ruleViews'] as List).isNotEmpty);
    final hasServerRules = !canonicalUnavailable &&
        (hasCanonicalRules || (serverRules is List && serverRules.isNotEmpty));
    final query = _searchQuery.trim().toLowerCase();

    final filteredRules = allRules.where((rule) {
      final matchesCat = _selectedCategory == 'ALL' ||
          (_categoryForRule(rule).toUpperCase() == _selectedCategory);
      if (!matchesCat) return false;

      if (query.isEmpty) return true;
      final title = rule.displayName.toLowerCase();
      final desc = rule.description.toLowerCase();
      final code = rule.articleCode.toLowerCase();
      final id = rule.code.toLowerCase();
      final cat = _categoryForRule(rule).toLowerCase();
      return title.contains(query) ||
          desc.contains(query) ||
          code.contains(query) ||
          id.contains(query) ||
          cat.contains(query);
    }).toList();

    final changeSets = canonical?['changeSets'] is List
        ? (canonical!['changeSets'] as List)
            .whereType<Map>()
            .map((row) =>
                ConstitutionChangeSet.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false)
        : const <ConstitutionChangeSet>[];

    final categories =
        <String>{'ALL', ...allRules.map(_categoryForRule)}.toList();

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
          label: 'Policy scopes',
          value: '2 Scopes',
          icon: Icons.account_tree_outlined,
          color: context.secondaryColor,
        ),
        CockpitMetric(
          label: 'Amendments',
          value: '${changeSets.length}',
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
          _buildPolicyScopeFlow(context),
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
                    : _buildStatuteList(
                        context,
                        filteredRules,
                        corporationScope: canonical?['corporationId']
                                ?.toString()
                                .isNotEmpty ==
                            true,
                      ),
          ),

          SizedBox(height: context.spacingSection),

          EarthSection(
            title: 'CONSTITUTIONAL HISTORY & AMENDMENTS',
            showSurface: false,
            child: changeSets.isEmpty
                ? const EarthEmptyState(
                    message:
                        'No canonical Constitution change sets have been recorded yet.',
                    icon: Icons.history_outlined,
                  )
                : EarthDataList(
                    children: changeSets.map((changeSet) {
                      return EarthDataRow(
                        title: changeSet.policyGroup,
                        subtitle:
                            'DAY ${changeSet.effectiveFromGameDay ?? '—'} · ${changeSet.authorityType} · ${changeSet.changes.length} RULES',
                        leading: Icon(
                          Icons.history_outlined,
                          size: context.iconSize,
                          color: context.secondaryColor,
                        ),
                        trailing: changeSet.proposalId.isEmpty
                            ? null
                            : TextButton(
                                onPressed: widget.onNavigate == null
                                    ? null
                                    : () => widget.onNavigate!('governance'),
                                child: const Text('GOVERNANCE'),
                              ),
                        showDivider: changeSet != changeSets.last,
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
    final scheduledViews = canonical['scheduledChangeViews'] is List
        ? (canonical['scheduledChangeViews'] as List)
            .whereType<Map>()
            .map((row) => ScheduledConstitutionChange.fromJson(
                Map<String, dynamic>.from(row)))
            .toList(growable: false)
        : const <ScheduledConstitutionChange>[];
    final versionHistoryViews = canonical['versionHistory'] is List
        ? (canonical['versionHistory'] as List)
            .whereType<Map>()
            .map((row) => ConstitutionVersionHistory.fromJson(
                Map<String, dynamic>.from(row)))
            .toList(growable: false)
        : const <ConstitutionVersionHistory>[];
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
                    _formatRuleValue(canonical, entry.key, entry.value),
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
          title:
              'CURRENT CONSTITUTION POLICY · DAY ${canonical['gameDay'] ?? '—'}',
          showSurface: false,
          child: rules.isEmpty
              ? const EarthEmptyState(
                  message: 'No effective typed policy values are available.',
                  icon: Icons.rule_outlined,
                )
              : EarthDataList(
                  children: rules.map((entry) {
                    final value =
                        _formatRuleValue(canonical, entry.key, entry.value);
                    final version = versionIds[entry.key]?.toString();
                    final source = provenance[entry.key]?.toString();
                    final scheduleRows = canonical['scheduleBrackets'] is Map
                        ? (canonical['scheduleBrackets']
                            as Map)[entry.value.toString()]
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
                              size: context.iconSize,
                              color: context.primaryColor),
                          showDivider: scheduleRows is! List &&
                              entry.key != rules.last.key,
                        ),
                        if (scheduleRows is List && scheduleRows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 44, right: 12, bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PROGRESSIVE BRACKETS',
                                    style: context.captionStyle
                                        .copyWith(color: context.mutedColor)),
                                const SizedBox(height: 4),
                                for (final bracket
                                    in scheduleRows.whereType<Map>())
                                  Text(_formatBracket(bracket),
                                      style: context.captionStyle),
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
                onPressed: () =>
                    _openAmendmentComposer(context, canonical, definitions),
              ),
            ),
          ),
        if (scheduledViews.isNotEmpty || scheduled.isNotEmpty)
          EarthSection(
            title: 'SCHEDULED CONSTITUTION CHANGES',
            showSurface: false,
            child: EarthDataList(
              children: scheduledViews.isNotEmpty
                  ? scheduledViews.map((change) {
                      return EarthDataRow(
                        title: change.ruleCode,
                        subtitle:
                            'DAY ${change.effectiveFromGameDay} · ${_formatRuleValue(canonical, change.ruleCode, change.value)} · ${change.authorityType}',
                        leading: Icon(Icons.schedule_outlined,
                            size: context.iconSize,
                            color: context.primaryColor),
                        showDivider: change != scheduledViews.last,
                      );
                    }).toList()
                  : scheduled.map((change) {
                      final code = change['rule_code']?.toString() ?? 'UNKNOWN';
                      final rawValue = change['value_json'];
                      return EarthDataRow(
                        title: code,
                        subtitle:
                            'DAY ${change['effective_from_game_day'] ?? '—'} · ${_formatRuleValue(canonical, code, rawValue)}',
                        leading: Icon(Icons.schedule_outlined,
                            size: context.iconSize,
                            color: context.primaryColor),
                        showDivider: change != scheduled.last,
                      );
                    }).toList(),
            ),
          ),
        if (versionHistoryViews.isNotEmpty || history.isNotEmpty)
          EarthSection(
            title: 'CONSTITUTION RULE HISTORY',
            showSurface: false,
            child: EarthDataList(
              children: versionHistoryViews.isNotEmpty
                  ? versionHistoryViews.map((version) {
                      final technical = <String>[
                        'VERSION ${version.versionId}',
                        'AUTHORITY ${version.authorityId}',
                        if (version.proposalId != null)
                          'PROPOSAL ${version.proposalId}',
                      ].join(' · ');
                      return ExpansionTile(
                        title: Text(version.ruleCode),
                        subtitle: Text(
                            'DAY ${version.effectiveFromGameDay} · ${version.status} · ${_formatRuleValue(canonical, version.ruleCode, version.value)}'),
                        leading: Icon(Icons.history_edu_outlined,
                            size: context.iconSize,
                            color: context.primaryColor),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(technical,
                                      style: context.captionStyle),
                                ),
                                if (version.proposalId != null)
                                  TextButton(
                                    onPressed: widget.onNavigate == null
                                        ? null
                                        : () => widget.onNavigate!
                                            .call('governance'),
                                    child: const Text('GOVERNANCE'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList()
                  : history.map((version) {
                      final code =
                          version['rule_code']?.toString() ?? 'UNKNOWN';
                      return EarthDataRow(
                        title: code,
                        subtitle:
                            'DAY ${version['effective_from_game_day'] ?? '—'} · ${version['status'] ?? '—'} · ${_formatRuleValue(canonical, code, version['value_json'])}',
                        leading: Icon(Icons.history_edu_outlined,
                            size: context.iconSize,
                            color: context.primaryColor),
                        showDivider: version != history.last,
                      );
                    }).toList(),
            ),
          ),
      ],
    );
  }

  String _inputSpecHelperText(ConstitutionInputSpec spec) {
    final parts = <String>[];
    if (spec.min != null) parts.add('MIN ${spec.min}');
    if (spec.max != null) parts.add('MAX ${spec.max}');
    if (spec.step != null) parts.add('STEP ${spec.step}');
    if (spec.allowedValues.isNotEmpty) {
      parts.add('ALLOWED ${spec.allowedValues.join(', ')}');
    }
    if (spec.inputKind == 'DECIMAL_CREDIT') {
      parts.insert(0, 'Player amount; server converts to atomic units');
    } else if (spec.inputKind == 'PERCENTAGE') {
      parts.insert(0, 'Player percentage; server converts to BPS');
    } else if (spec.inputKind == 'SCHEDULE_ID') {
      parts.insert(0, 'Select an active server schedule');
    }
    return parts.join(' · ');
  }

  bool _scheduleMatchesRule(
      ConstitutionRuleView rule, ConstitutionProgressiveSchedule schedule) {
    if (rule.valueType != 'PROGRESSIVE_SCHEDULE_REF') return false;
    if (rule.code.contains('HOUSE_INCOME_TAX')) {
      return schedule.basisType == 'HOUSE_INCOME_TAX';
    }
    if (rule.code == 'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE') {
      return schedule.basisType == 'EARTH_CORPORATION_CAPACITY';
    }
    if (rule.code == 'EARTH.CAPACITY.HOUSE_PROGRESSIVE_SCHEDULE') {
      return schedule.basisType == 'CORPORATION_HOUSE_CAPACITY';
    }
    return true;
  }

  String _schedulePreview(ConstitutionProgressiveSchedule schedule) {
    return schedule.brackets
        .map((bracket) =>
            '${bracket.lowerBoundUnits}–${bracket.upperBoundUnits ?? '∞'} · ×${bracket.marginalMultiplierNumerator}/${bracket.marginalMultiplierDenominator}')
        .join('   ');
  }

  Future<void> _openAmendmentComposer(BuildContext context,
      Map<String, dynamic> canonical, List<Map> definitions) async {
    final corporationScope =
        canonical['corporationId']?.toString().isNotEmpty == true;
    final available = (canonical['ruleViews'] is List
            ? (canonical['ruleViews'] as List)
                .whereType<Map>()
                .map((row) => ConstitutionRuleView.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList()
            : definitions
                .map((row) => ConstitutionRuleView.fromJson(
                    Map<String, dynamic>.from(row)))
                .toList())
        .where((definition) {
      final authority = definition.authorityModel;
      return corporationScope
          ? authority != 'EARTH_LOCKED'
          : authority != 'CORPORATION_LOCAL';
    }).where((definition) {
      final type = definition.valueType;
      // Schedule references are selectable by their canonical server-owned
      // ID. The server validates that the referenced schedule is active and
      // uses the same brackets during settlement; the client must not edit or
      // recreate the schedule definition locally.
      return [
        'BOOLEAN',
        'INTEGER',
        'CREDIT_UNITS',
        'RATE_BPS',
        'ENUM',
        'GAME_DAYS',
        'RESOURCE_UNITS',
        'PROGRESSIVE_SCHEDULE_REF'
      ].contains(type);
    }).toList();
    final schedules = canonical['progressiveSchedules'] is List
        ? (canonical['progressiveSchedules'] as List)
            .whereType<Map>()
            .map((row) => ConstitutionProgressiveSchedule.fromJson(
                Map<String, dynamic>.from(row)))
            .where((schedule) => schedule.brackets.isNotEmpty)
            .toList(growable: false)
        : const <ConstitutionProgressiveSchedule>[];
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No scalar Constitution rules are available for amendment.')));
      return;
    }
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        String selected = available.first.code;
        String? error;
        final valueController = TextEditingController();
        final selectedChanges = <Map<String, dynamic>>[];
        return StatefulBuilder(builder: (context, setState) {
          final policyGroup = selectedChanges.isEmpty
              ? null
              : selectedChanges.first['policyGroup']?.toString();
          final candidates = available
              .where((item) =>
                  policyGroup == null || item.policyGroup == policyGroup)
              .toList(growable: false);
          if (!candidates.any((item) => item.code == selected)) {
            selected = candidates.first.code;
            valueController.clear();
          }
          final definition =
              candidates.firstWhere((item) => item.code == selected);
          final type = definition.valueType;
          final inputSpec = definition.inputSpec;
          final allowed = inputSpec.allowedValues;
          final scheduleOptions = schedules
              .where((schedule) => _scheduleMatchesRule(definition, schedule))
              .toList(growable: false);
          return AlertDialog(
            title: const Text('PROPOSE CONSTITUTION AMENDMENT'),
            content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: selected,
                  decoration: const InputDecoration(labelText: 'Rule'),
                  items: available
                      .where((item) =>
                          policyGroup == null ||
                          item.policyGroup == policyGroup)
                      .map((item) => DropdownMenuItem(
                          value: item.code, child: Text(item.displayName)))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selected = value ?? selected;
                    valueController.clear();
                    error = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (type == 'BOOLEAN')
                  DropdownButtonFormField<String>(
                    value: valueController.text.isEmpty
                        ? null
                        : valueController.text,
                    decoration: const InputDecoration(labelText: 'Value'),
                    items: const [
                      DropdownMenuItem(value: 'true', child: Text('TRUE')),
                      DropdownMenuItem(value: 'false', child: Text('FALSE'))
                    ],
                    onChanged: (value) =>
                        setState(() => valueController.text = value ?? ''),
                  )
                else if (type == 'ENUM' && allowed.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: allowed.contains(valueController.text)
                        ? valueController.text
                        : null,
                    decoration: const InputDecoration(labelText: 'Value'),
                    items: allowed
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => valueController.text = value ?? ''),
                  )
                else if (type == 'PROGRESSIVE_SCHEDULE_REF') ...[
                  DropdownButtonFormField<String>(
                    value: scheduleOptions.any(
                            (schedule) => schedule.id == valueController.text)
                        ? valueController.text
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Progressive schedule'),
                    items: scheduleOptions
                        .map((schedule) => DropdownMenuItem(
                              value: schedule.id,
                              child: SizedBox(
                                width: 410,
                                child: Text(
                                  '${schedule.code} · v${schedule.version}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => valueController.text = value ?? ''),
                  ),
                  if (scheduleOptions.isNotEmpty &&
                      valueController.text.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _schedulePreview(scheduleOptions.firstWhere(
                              (schedule) =>
                                  schedule.id == valueController.text)),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                ] else
                  TextField(
                    controller: valueController,
                    keyboardType: TextInputType.numberWithOptions(
                        decimal: type == 'CREDIT_UNITS' || type == 'RATE_BPS'),
                    decoration: InputDecoration(
                      labelText: inputSpec.inputKind == 'DECIMAL_CREDIT'
                          ? 'Amount in CREDIT'
                          : inputSpec.inputKind == 'PERCENTAGE'
                              ? 'Rate percentage'
                              : '$type value',
                      helperText: _inputSpecHelperText(inputSpec),
                    ),
                  ),
                if (selectedChanges.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ATOMIC CHANGE SET · ${definition.policyGroup}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  for (final change in selectedChanges)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(change['ruleCode'].toString()),
                      subtitle: Text(change['value'].toString()),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => setState(() {
                          selectedChanges.remove(change);
                        }),
                      ),
                    ),
                ],
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('CANCEL')),
              OutlinedButton(
                  onPressed: () {
                    dynamic value;
                    if (type == 'BOOLEAN') {
                      value = valueController.text == 'true'
                          ? true
                          : valueController.text == 'false'
                              ? false
                              : null;
                    } else if (type == 'ENUM') {
                      value = valueController.text.isEmpty
                          ? null
                          : valueController.text;
                    } else if (type == 'CREDIT_UNITS' || type == 'RATE_BPS') {
                      value = valueController.text.trim().isEmpty
                          ? null
                          : valueController.text.trim();
                    } else {
                      final parsed =
                          BigInt.tryParse(valueController.text.trim());
                      value =
                          parsed == null ? null : valueController.text.trim();
                    }
                    if (value == null) {
                      setState(() => error = 'Enter a valid $type value.');
                      return;
                    }
                    if (selectedChanges
                        .any((change) => change['ruleCode'] == selected)) {
                      setState(() =>
                          error = 'This rule is already in the change set.');
                      return;
                    }
                    setState(() {
                      selectedChanges.add({
                        'ruleCode': selected,
                        'value': value,
                        'policyGroup': definition.policyGroup,
                      });
                      valueController.clear();
                      error = null;
                    });
                  },
                  child: const Text('ADD RULE')),
              FilledButton(
                onPressed: () {
                  if (selectedChanges.isEmpty) {
                    setState(() => error = 'Add at least one rule.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    selectedChanges
                        .map((change) => Map<String, dynamic>.from(change)
                          ..remove('policyGroup'))
                        .toList(growable: false),
                  );
                },
                child: const Text('CONTINUE'),
              ),
            ],
          );
        });
      },
    );
    if (result == null ||
        !context.mounted ||
        widget.onProposeAmendment == null) {
      return;
    }
    try {
      if (widget.onPreviewAmendment != null) {
        final preview = await widget.onPreviewAmendment!(result);
        if (!context.mounted) return;
        if (preview['ok'] == false) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(preview['error']?.toString() ??
                  'Amendment preview failed.')));
          return;
        }
        final proceed = await _confirmPreview(context, preview, canonical);
        if (!proceed || !context.mounted) return;
      }
      final response = await widget.onProposeAmendment!(result);
      if (!context.mounted) return;
      final ok = response['ok'] != false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Constitution amendment proposal submitted.'
              : response['error']?.toString() ??
                  'Amendment proposal failed.')));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Amendment proposal failed: $error')));
      }
    }
  }

  Future<bool> _confirmPreview(BuildContext context,
      Map<String, dynamic> preview, Map<String, dynamic> canonical) async {
    final changes = preview['changes'] is List
        ? (preview['changes'] as List).whereType<Map>().toList()
        : const <Map>[];
    final effects = preview['progressiveEffects'] is List
        ? (preview['progressiveEffects'] as List).whereType<Map>().toList()
        : const <Map>[];
    final lines = <Widget>[
      Text('GAME DAY ${preview['gameDay'] ?? '—'} · SERVER-CALCULATED IMPACT',
          style: Theme.of(context).textTheme.labelSmall),
      const SizedBox(height: 12),
      Text(
        'VOTING: DAY ${preview['votingStartGameDay'] ?? '—'} → ${preview['votingEndGameDay'] ?? '—'} · IMPLEMENTATION DELAY: ${preview['implementationDelayDays'] ?? '—'} DAYS · EARLIEST EFFECTIVE: DAY ${preview['earliestValidEffectiveGameDay'] ?? '—'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      for (final change in changes)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(change['ruleCode']?.toString() ?? 'Rule'),
          subtitle: Text(
              '${_formatRuleValue(canonical, change['ruleCode'], change['currentValue'])}  →  ${_formatRuleValue(canonical, change['ruleCode'], change['proposedValue'])}'),
        ),
      for (final effect in effects) ...[
        const Divider(),
        Text('PROGRESSIVE EFFECT · ${effect['ruleCode'] ?? 'RULE'}',
            style: Theme.of(context).textTheme.labelSmall),
        for (final row in (effect['effects'] is List
                ? effect['effects'] as List
                : const [])
            .whereType<Map>())
          Text(
            'QTY ${row['current']?['quantity'] ?? '—'}: ${formatCreditUnits(row['current']?['totalCharge'])} → ${formatCreditUnits(row['proposed']?['totalCharge'])} (Δ ${formatCreditUnits(row['delta'])})',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ];
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('REVIEW CONSTITUTION AMENDMENT'),
            content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: lines))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('CANCEL')),
              FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('SUBMIT PROPOSAL')),
            ],
          ),
        ) ??
        false;
  }

  String _formatRuleValue(
      Map<String, dynamic>? canonical, dynamic code, dynamic value) {
    final ruleCode = code?.toString() ?? '';
    final views = canonical?['ruleViews'];
    if (views is List) {
      for (final raw in views.whereType<Map>()) {
        final view =
            ConstitutionRuleView.fromJson(Map<String, dynamic>.from(raw));
        if (view.code == ruleCode) {
          if (view.valueType == 'PROGRESSIVE_SCHEDULE_REF') {
            final schedules = canonical?['progressiveSchedules'] is List
                ? (canonical!['progressiveSchedules'] as List)
                    .whereType<Map>()
                    .map((row) => ConstitutionProgressiveSchedule.fromJson(
                        Map<String, dynamic>.from(row)))
                    .toList(growable: false)
                : const <ConstitutionProgressiveSchedule>[];
            ConstitutionProgressiveSchedule? schedule;
            for (final item in schedules) {
              if (item.id == value?.toString() ||
                  item.code == value?.toString()) {
                schedule = item;
                break;
              }
            }
            if (schedule != null) {
              return '${schedule.code} · ${_schedulePreview(schedule)}';
            }
          }
          return ConstitutionValueFormatter.format(value, view.valueType);
        }
      }
    }
    final definitions = canonical?['definitions'];
    if (definitions is List) {
      for (final raw in definitions.whereType<Map>()) {
        if (raw['rule_code']?.toString() == ruleCode) {
          return ConstitutionValueFormatter.format(value, raw['value_type']);
        }
      }
    }
    return _formatCanonicalValue(value);
  }

  String _formatCanonicalValue(dynamic value, [dynamic valueType]) {
    if (valueType != null) {
      return ConstitutionValueFormatter.format(value, valueType);
    }
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
    final numerator =
        bracket['marginal_multiplier_numerator']?.toString() ?? '—';
    final denominator =
        bracket['marginal_multiplier_denominator']?.toString() ?? '—';
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

  Widget _buildPolicyScopeFlow(BuildContext context) {
    Widget scope(IconData icon, String label, String detail, Color color) =>
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
            'Policy authorities: Earth Constitution → Corporation policy overrides',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              scope(Icons.public_outlined, 'EARTH',
                  'Universal rules and defaults', context.primaryColor),
              Icon(Icons.arrow_forward_rounded, color: context.mutedColor),
              scope(Icons.domain_outlined, 'CORPORATION',
                  'Permitted local policy overrides', context.secondaryColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatuteList(
    BuildContext context,
    List<ConstitutionRuleView> rules, {
    required bool corporationScope,
  }) {
    final grouped = <String, List<ConstitutionRuleView>>{};
    for (final rule in rules) {
      final article = rule.articleCode.toUpperCase();
      grouped.putIfAbsent(article, () => []).add(rule);
    }

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
                _categoryForRule(rows.first),
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
                    return _buildStatuteCard(
                      context,
                      rule,
                      corporationScope: corporationScope,
                      isLast: isLast,
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatuteCard(BuildContext context, ConstitutionRuleView rule,
      {required bool corporationScope, required bool isLast}) {
    final id = rule.code;
    final code = rule.articleCode;
    final title = rule.displayName;
    final desc = rule.description;
    final valueType = rule.valueType;
    final resolvedValue = rule.resolved.value;
    final source = rule.resolved.source;
    final authorityModel = rule.authorityModel;
    final permitted =
        rule.allowedValues.isNotEmpty ? rule.allowedValues.join(', ') : null;
    final inheritanceStatus = rule.inheritanceStatus;
    final status = inheritanceStatus == 'INHERITED'
        ? 'INHERITED'
        : inheritanceStatus == 'LOCAL_OVERRIDE'
            ? 'LOCAL OVERRIDE'
            : authorityModel == 'EARTH_LOCKED'
                ? 'EARTH LOCKED'
                : authorityModel == 'CORPORATION_LOCAL'
                    ? 'CORPORATION POLICY'
                    : 'OVERRIDE-ELIGIBLE';

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
                customColor: authorityModel == 'EARTH_LOCKED'
                    ? context.primaryColor
                    : context.secondaryColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(desc, style: context.bodyStyle),
          if (rule.inputHint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(rule.inputHint,
                style:
                    context.captionStyle.copyWith(color: context.mutedColor)),
          ],
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
                      Text(
                          inheritanceStatus == 'LOCAL_OVERRIDE'
                              ? 'LOCAL VALUE'
                              : 'CURRENT VALUE',
                          style: context.captionStyle
                              .copyWith(color: context.mutedColor)),
                      const SizedBox(height: 2),
                      Text(
                          ConstitutionValueFormatter.format(
                              resolvedValue, valueType),
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
                if (valueType.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VALUE TYPE',
                            style: context.captionStyle
                                .copyWith(color: context.mutedColor)),
                        const SizedBox(height: 2),
                        Text(rule.displayHint,
                            style: context.bodyStyle
                                .copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
                if (corporationScope && rule.earthDefault != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EARTH DEFAULT',
                            style: context.captionStyle
                                .copyWith(color: context.mutedColor)),
                        const SizedBox(height: 2),
                        Text(
                          ConstitutionValueFormatter.format(
                              rule.earthDefault!.value, valueType),
                          style: context.bodyStyle
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('SOURCE',
                        style: context.captionStyle
                            .copyWith(color: context.mutedColor)),
                    const SizedBox(height: 2),
                    Text(source ?? authorityModel,
                        style: context.bodyStyle.copyWith(
                          fontWeight: FontWeight.w700,
                          color: source == 'CORPORATION'
                              ? context.secondaryColor
                              : context.primaryColor,
                        )),
                  ],
                ),
              ],
            ),
          ),
          if (corporationScope &&
              inheritanceStatus == 'LOCAL_OVERRIDE' &&
              widget.onProposeAmendment != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: EarthButton(
                label: 'RETURN TO EARTH DEFAULT',
                variant: EarthButtonVariant.secondary,
                onPressed: () async {
                  final result = await widget.onProposeAmendment!([
                    {'ruleCode': rule.code, 'clearOverride': true},
                  ]);
                  if (!context.mounted) return;
                  final ok = result['ok'] != false;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Earth-default restoration proposed.'
                          : (result['error']?.toString() ??
                              'Unable to propose restoration.')),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
