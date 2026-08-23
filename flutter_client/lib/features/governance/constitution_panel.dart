import 'package:flutter/material.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

class ConstitutionPanel extends StatelessWidget {
  final EarthState state;

  const ConstitutionPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Section & Core Invariants
          EarthSection(
            title: 'PLANETARY CONSTITUTION & GOVERNANCE',
            showSurface: false,
            infoBulletPoints: const [
              'The Planetary Constitution establishes immutable economic and civil invariants that bind all corporations, cities, and citizens.',
              'Tier 1 (Earth Universal Law) restricts and bounds Tier 2 (Corporate Charters) and Tier 3 (Municipal Ordinances).',
              'Subordinate entities may customize policies within constitutional parameters, but any rule exceeding parent limits is voided by High Court injunction.',
            ],
            child: EarthMetricGrid(
              metrics: [
                EarthMetricTile(
                  label: 'HIERARCHY TIERS',
                  value: '3 TIERS',
                  icon: Icons.account_tree_outlined,
                  accentColor: context.primaryColor,
                ),
                EarthMetricTile(
                  label: 'IMMUTABLE INVARIANTS',
                  value: '5 LAWS',
                  icon: Icons.shield_outlined,
                  accentColor: context.primaryColor,
                ),
                EarthMetricTile(
                  label: 'JUDICIAL REVIEW',
                  value: 'ACTIVE',
                  icon: Icons.gavel_outlined,
                  accentColor: context.secondaryColor,
                ),
              ],
            ),
          ),

          SizedBox(height: context.spacingSection),

          // 2. Governance & Override Model
          EarthSection(
            title: 'GOVERNANCE HIERARCHY & OVERRIDE MODEL',
            showSurface: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHierarchyCard(
                  context,
                  tier: 'TIER 1 · TOP LEVEL',
                  title: 'EARTH (UNIVERSAL CITIZENSHIP)',
                  scope: 'PLANETARY INVARIANTS & STATUTORY LAW',
                  color: context.primaryColor,
                  icon: Icons.public_rounded,
                  rules: [
                    'Constitutional property rights & non-negative ledger invariants.',
                    'Central Market uniform clearing & non-discriminatory access.',
                    'Mandatory 3-day cooling-off period for democratic legislation.',
                    'High Court judicial injunction & constitutional appeal authority.',
                  ],
                  overridable: false,
                ),
                SizedBox(height: context.spacingControl),
                _buildHierarchyCard(
                  context,
                  tier: 'TIER 2 · ENTERPRISE LEVEL',
                  title: 'CORPORATIONS',
                  scope: 'CORPORATE CHARTERS & BYLAWS',
                  color: context.secondaryColor,
                  icon: Icons.apartment_rounded,
                  rules: [
                    'Internal tax charter & operational fee deductions.',
                    'Corporate dividend distribution formula & payout cadence.',
                    'Membership admission & shareholder supermajority protections (67%).',
                    'Executive officer appointments & operational delegation.',
                  ],
                  overridable: true,
                  parentConstraint: 'Restricted by Tier 1 Earth Constitutional Invariants.',
                ),
                SizedBox(height: context.spacingControl),
                _buildHierarchyCard(
                  context,
                  tier: 'TIER 3 · LOCAL LEVEL',
                  title: 'CITIES & MUNICIPALITIES',
                  scope: 'MUNICIPAL ORDINANCES & ESSENTIAL SERVICES',
                  color: context.warningColor,
                  icon: Icons.location_city_rounded,
                  rules: [
                    'Municipal utility tariffs (Energy, Food, Water, Materials).',
                    'Local residency eligibility, registration & housing allocation.',
                    'Public infrastructure budgets & community initiatives.',
                  ],
                  overridable: true,
                  parentConstraint: 'Restricted by Tier 1 Earth Law & Tier 2 Corporate Charters.',
                ),
              ],
            ),
          ),

          SizedBox(height: context.spacingSection),

          // 3. Active Constitutional Statutes
          EarthSection(
            title: 'ACTIVE PLANETARY STATUTES',
            showSurface: false,
            child: EarthDataList(
              children: [
                _buildStatuteRow(
                  context,
                  code: 'STATUTE-001',
                  title: 'Central Market Clearing & Fair Allocation',
                  category: 'MARKET & COMMERCE',
                  status: 'IMMUTABLE INVARIANT',
                  isImmutable: true,
                  summary:
                      'All secondary trade across Food, Materials, Energy, and Computing settles through uniform clearing price mechanisms without monopolistic routing.',
                  showDivider: true,
                ),
                _buildStatuteRow(
                  context,
                  code: 'STATUTE-002',
                  title: 'Macroeconomic Statutory Citizen Levy',
                  category: 'FINANCE & REVENUE',
                  status: 'DELEGATED VARIABLE',
                  isImmutable: false,
                  summary:
                      'Base planetary levy rate on commercial transaction volume. Corporations may levy additional fees up to a maximum constitutional ceiling of 15.0%.',
                  showDivider: true,
                ),
                _buildStatuteRow(
                  context,
                  code: 'STATUTE-003',
                  title: 'Democratic Ballot Quorum & Supermajority Thresholds',
                  category: 'GOVERNANCE',
                  status: 'IMMUTABLE INVARIANT',
                  isImmutable: true,
                  summary:
                      'Legislation requires minimum 25% citizen participation quorum and 50% majority approval. Minority shareholder motions require 67% supermajority.',
                  showDivider: true,
                ),
                _buildStatuteRow(
                  context,
                  code: 'STATUTE-004',
                  title: 'Mandatory Legislative Cooling-Off & Judicial Review',
                  category: 'JUSTICE & APPEALS',
                  status: 'IMMUTABLE INVARIANT',
                  isImmutable: true,
                  summary:
                      'Passed proposals enter a mandatory 3 game-day cooling-off window prior to ledger execution to allow affected parties to file High Court constitutional challenges.',
                  showDivider: true,
                ),
                _buildStatuteRow(
                  context,
                  code: 'STATUTE-005',
                  title: 'Dynastic Succession & Testamentary Integrity',
                  category: 'CIVIL RIGHTS',
                  status: 'IMMUTABLE INVARIANT',
                  isImmutable: true,
                  summary:
                      'Guarantees inheritance transfer of registered businesses, private assets, dynastic heirlooms, and accumulated legacy points to designated heirs upon end-of-life.',
                  showDivider: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHierarchyCard(
    BuildContext context, {
    required String tier,
    required String title,
    required String scope,
    required Color color,
    required IconData icon,
    required List<String> rules,
    required bool overridable,
    String? parentConstraint,
  }) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(context.radiusControl),
                ),
                child: Icon(icon, size: context.iconSize, color: color),
              ),
              SizedBox(width: context.spacingTitleOffset),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier, style: context.captionStyle.copyWith(color: color, fontWeight: FontWeight.w700)),
                    Text(title, style: context.widgetValueStyle),
                    Text(scope, style: context.widgetFooterStyle),
                  ],
                ),
              ),
              EarthBadge(
                label: overridable ? 'DELEGATED' : 'IMMUTABLE',
                customColor: overridable ? context.secondaryColor : context.primaryColor,
              ),
            ],
          ),
          SizedBox(height: context.spacingInline),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  Expanded(child: Text(r, style: context.bodyStyle)),
                ],
              ),
            ),
          ),
          if (parentConstraint != null) ...[
            const SizedBox(height: 4),
            Text(
              '⚠️ $parentConstraint',
              style: context.captionStyle.copyWith(color: context.warningColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatuteRow(
    BuildContext context, {
    required String code,
    required String title,
    required String category,
    required String status,
    required bool isImmutable,
    required String summary,
    required bool showDivider,
  }) {
    return EarthDataRow(
      title: title,
      subtitle: '$code · $category\n$summary',
      leading: Icon(
        isImmutable ? Icons.lock_outline_rounded : Icons.tune_rounded,
        size: context.iconSize,
        color: isImmutable ? context.primaryColor : context.secondaryColor,
      ),
      badges: [
        EarthBadge(
          label: isImmutable ? 'IMMUTABLE' : 'OVERRIDABLE',
          variant: isImmutable ? EarthBadgeVariant.primary : EarthBadgeVariant.neutral,
        ),
      ],
      showDivider: showDivider,
    );
  }
}
