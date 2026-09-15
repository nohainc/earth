import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';

class ConstitutionPanel extends StatefulWidget {
  final EarthState state;

  const ConstitutionPanel({super.key, required this.state});

  @override
  State<ConstitutionPanel> createState() => _ConstitutionPanelState();
}

class _ConstitutionPanelState extends State<ConstitutionPanel> {
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  final _searchController = TextEditingController();

  static const List<Map<String, dynamic>> _canonicalArticles = [
    {
      'id': 'CONST-TIME-001',
      'part_number': 1,
      'rule_number': '1.1',
      'category': 'TIME & SETTLEMENT',
      'title': 'Authoritative World Time',
      'description':
          'EARTH is governed by authoritative PostgreSQL game time. Economic and daily gameplay settlement occurs by complete game day, independent of the number of Cron deliveries or Worker invocations.',
      'default_value': 'Authoritative PostgreSQL Engine',
      'permitted_values': 'Immutable World Clock',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-TIME-002',
      'part_number': 1,
      'rule_number': '1.2',
      'category': 'TIME & SETTLEMENT',
      'title': 'Daily Economic Accounting Period',
      'description':
          'The complete game day is EARTH\'s fundamental economic accounting period. Production, consumption, services, needs, taxes, interest, research, license fees, and institutional payments are calculated and settled per game day.',
      'default_value': 'Daily Settlement',
      'permitted_values': 'Daily only',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-MONEY-001',
      'part_number': 2,
      'rule_number': '2.1',
      'category': 'MONETARY & LEDGER',
      'title': 'Sole Monetary Authority',
      'description':
          'Economy V2 is the sole authority for CREDIT balances and monetary history. economic_accounts hold balances; economic_transactions and economic_entries record value movement.',
      'default_value': 'Economy V2 Dual-Entry Ledger',
      'permitted_values': 'Strict Conservation of Value',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-MONEY-002',
      'part_number': 2,
      'rule_number': '2.2',
      'category': 'MONETARY & LEDGER',
      'title': 'Explicit Credit Issuance',
      'description':
          'Only explicitly authorized monetary issuance may create CREDIT. Every issuance and retirement must identify its rule version, source, reason, game day, and correlation ID. Ordinary gameplay moves existing CREDIT without creating unbacked tokens.',
      'default_value': 'Authorized Issuance Only',
      'permitted_values': 'Zero Unbacked Minting',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-ASSET-001',
      'part_number': 3,
      'rule_number': '3.1',
      'category': 'RESOURCES & PROPERTY',
      'title': 'Canonical Physical Resources',
      'description':
          'EARTH has five canonical physical resources: Material, Components, Energy, Compute, and Food. Production and consumption use explicit source/sink or counterparty accounting reconciled with the ledger.',
      'default_value': 'Material, Components, Energy, Compute, Food',
      'permitted_values': '5 Resource Quotas',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-OWNER-001',
      'part_number': 3,
      'rule_number': '3.2',
      'category': 'RESOURCES & PROPERTY',
      'title': 'Property and Account Ownership',
      'description':
          'Houses, Territories, and Organizations may own economic assets only through the canonical owner/economic-account model. A read projection is never an independent balance authority.',
      'default_value': 'Owner / Account Linkage',
      'permitted_values': 'Explicit Account Identity',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-HOUSE-001',
      'part_number': 4,
      'rule_number': '4.1',
      'category': 'DYNASTY & SUCCESSION',
      'title': 'House Continuity Invariant',
      'description':
          'A House is the persistent player identity and economic principal. A Human is a mortal representative. House property, contracts, debts, affiliations, and economic history survive Human succession; personal offices and personal standing do not automatically survive.',
      'default_value': 'Persistent House Principal',
      'permitted_values': 'House Level Ownership',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-SUCCESSION-001',
      'part_number': 4,
      'rule_number': '4.2',
      'category': 'DYNASTY & SUCCESSION',
      'title': 'Succession and Representation',
      'description':
          'House property survives Human mortality. Succession transfers executive agency to the appointed heir or dynastic trust, protecting dynasty accumulated capital from arbitrary confiscation.',
      'default_value': 'Lineage Succession Protocol',
      'permitted_values': 'Direct Heir / Dynastic Commons',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-MARKET-001',
      'part_number': 5,
      'rule_number': '5.1',
      'category': 'MARKET & COMMERCE',
      'title': 'Central Spot Market Architecture',
      'description':
          'EARTH maintains one unified central Spot Market for physical resources. Orders, escrow, batches, matching, fills, and price discovery use the shared order book architecture without uncollateralized shorting.',
      'default_value': 'Unified Spot Order Book',
      'permitted_values': 'Escrow-backed Trades',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-BUILDING-001',
      'part_number': 5,
      'rule_number': '5.2',
      'category': 'MARKET & COMMERCE',
      'title': 'Physical Building Economics',
      'description':
          'Buildings consume defined physical inputs and explicit operating expenses, producing physical resources or service capacity. A building does not generate CREDIT purely from catalog presence.',
      'default_value': 'Physical Input/Output Conservation',
      'permitted_values': 'Catalog Operating Rules',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-TAX-001',
      'part_number': 6,
      'rule_number': '6.1',
      'category': 'TAXATION & FISCAL',
      'title': 'Lawful Non-Retroactive Taxation',
      'description':
          'Taxes require an authorized, immutable, versioned rule effective for the settlement game day. Tax rules cannot apply retroactively. Unpaid lawful taxes become explicit arrears obligations.',
      'default_value': 'Versioned Statute Authority',
      'permitted_values': 'Max 50% Rate BPS',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-BUDGET-001',
      'part_number': 6,
      'rule_number': '6.2',
      'category': 'TAXATION & FISCAL',
      'title': 'Fiscal Vocabulary and Spending Discipline',
      'description':
          'Budget is spending authority. Treasury is liquid cash. A commitment is an authorized reservation. Spending is an actual ledger transfer.',
      'default_value': 'Separated Budget & Treasury',
      'permitted_values': 'Double-Entry Reconciliation',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-TERRITORY-001',
      'part_number': 7,
      'rule_number': '7.1',
      'category': 'SUBSIDIARITY & INSTITUTIONS',
      'title': 'Territory Commons & Public Charter',
      'description':
          'Territories are public geographical commons. Financial distress is handled through defined stress, receivership, and recovery rules without arbitrary erasure of residents.',
      'default_value': 'Public Commons Trust',
      'permitted_values': 'Territory Self-Governance',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-CORP-001',
      'part_number': 7,
      'rule_number': '7.2',
      'category': 'SUBSIDIARITY & INSTITUTIONS',
      'title': 'Organizations & Enterprise Alliances',
      'description':
          'Organizations are collective economic institutions for shared capital, joint ventures, and technology pools. Distress, restructuring, and dividends follow explicit statutory rules.',
      'default_value': 'Shared Equity & Patent Pools',
      'permitted_values': 'Charter Democracy',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-GOV-001',
      'part_number': 8,
      'rule_number': '8.1',
      'category': 'DEMOCRACY & GOVERNANCE',
      'title': 'Authorized Democratic Procedures',
      'description':
          'Rules and institutional authorities change only through authorized governance procedures. Historical decisions, ballots, and rule versions are immutable permanent records.',
      'default_value': 'Cryptographic & Quorum Ballots',
      'permitted_values': 'Democracy / Supermajority',
      'authority': 'EARTH',
      'immutable': true,
    },
    {
      'id': 'CONST-RESEARCH-001',
      'part_number': 9,
      'rule_number': '9.1',
      'category': 'RESEARCH & PATENTS',
      'title': 'Technology and Blueprint Progression',
      'description':
          'Organization research unlocks predefined building blueprints and technologies. Research is funded through the ledger and progresses from compute and funding capacity.',
      'default_value': 'Ledger-Funded Research Trees',
      'permitted_values': 'Open / Patented',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-IP-001',
      'part_number': 9,
      'rule_number': '9.2',
      'category': 'RESEARCH & PATENTS',
      'title': 'Patent Exclusivity and Licensing',
      'description':
          'Only explicitly configured technologies may receive patents. Patent rights are time-limited, versioned, and organization-owned, enabling lawful commercial licensing contracts.',
      'default_value': 'Time-Limited Patent Pool',
      'permitted_values': 'Cross-Licensing Agreements',
      'authority': 'EARTH',
      'immutable': false,
    },
    {
      'id': 'CONST-AMEND-001',
      'part_number': 10,
      'rule_number': '10.1',
      'category': 'AMENDMENTS & CONSTITUTION',
      'title': 'Constitutional Amendment Supermajority',
      'description':
          'This Constitution may change only through a special constitutional amendment process requiring supermajority planetary consensus. Normal balance changes cannot bypass invariants.',
      'default_value': '67% Supermajority Invariant',
      'permitted_values': 'Planetary Referendum',
      'authority': 'EARTH',
      'immutable': true,
    },
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _resolveAllRules() {
    final serverRules = widget.state.json['constitutionalRules'] is List
        ? (widget.state.json['constitutionalRules'] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList()
        : const <Map<String, dynamic>>[];

    if (serverRules.isEmpty) {
      return _canonicalArticles;
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final art in _canonicalArticles) {
      merged[art['id']?.toString() ?? ''] = Map<String, dynamic>.from(art);
    }
    for (final sRule in serverRules) {
      final id = sRule['id']?.toString() ?? '';
      if (id.isNotEmpty && merged.containsKey(id)) {
        merged[id] = {...merged[id]!, ...sRule};
      } else if (id.isNotEmpty) {
        merged[id] = sRule;
      }
    }
    return merged.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final allRules = _resolveAllRules();
    final serverRules = widget.state.json['constitutionalRules'];
    final hasServerRules = serverRules is List && serverRules.isNotEmpty;
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
              return type.contains('rule') ||
                  type.contains('charter') ||
                  type.contains('tax') ||
                  type.contains('constitution');
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
          '• Supreme Law: The highest legal baseline across Earth. All municipal charters and organization policies must conform to constitutional invariants.\n\n• 3-Tier Governance Hierarchy:\n  1. Earth Baseline (Supreme global statutes & unalienable citizen rights)\n  2. Organization Policy (Intermediate organizational rules & dividends)\n  3. Territory Commons (Final permitted local overrides, municipal taxation, & zoning)\n\n• Precedence: A permitted local override modifies the tier before it, provided it conforms to global constitutional invariants.',
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
                      'Reference view: the authoritative constitutional rule feed is not available in this snapshot. These baseline articles are informational and cannot change gameplay until confirmed by the server.',
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
            child: filteredRules.isEmpty
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
            'Rule Precedence: Earth Baseline → Organization Policy → Territory Commons',
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
    final isImmutable = rule['immutable'] == true;
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
                label: isImmutable ? 'INVARIANT' : 'OVERRIDABLE',
                customColor:
                    isImmutable ? context.primaryColor : context.secondaryColor,
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
