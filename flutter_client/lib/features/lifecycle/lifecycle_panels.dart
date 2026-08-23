import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';
import '../governance/governance_dialogs.dart';
import 'lifecycle_dialogs.dart';
import 'global_rankings_dialog.dart';

Widget _lifecycleTopicHeading(BuildContext context, String title,
    {required String description}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Flexible(
        child: Text(title,
            style: const TextStyle(
                color: mutedColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      ),
      const SizedBox(width: 5),
      IconButton(
        tooltip: 'About $title',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(Icons.info_outline,
            size: 14, color: mutedColor.withValues(alpha: .8)),
        onPressed: () => showEarthInfoDialog(context,
            title: title, description: description),
      ),
    ]),
  );
}

class LifeTodayPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function())? action;

  const LifeTodayPanel({super.key, required this.state, this.busy = false, this.action});

  Future<void> _editName(BuildContext context) async {
    final controller = TextEditingController(
        text: (state.human['display_name'] ?? state.human['name'] ?? '').toString());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.panelColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radiusPanel),
          side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
        ),
        title: Text('Edit your name',
            style: context.topicTitleStyle.copyWith(color: context.primaryColor)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: context.bodyStyle.copyWith(color: context.inkColor),
          decoration: InputDecoration(
            labelText: 'Name and surname',
            labelStyle: context.widgetFooterStyle,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('CANCEL',
                style: context.controlStyle.copyWith(color: context.mutedColor)),
          ),
          EarthButton(
            label: 'SAVE',
            onPressed: busy || action == null
                ? null
                : () async {
                    final name = controller.text.trim();
                    if (name.length < 2) return;
                    Navigator.pop(dialogContext);
                    await action!(() => const EarthApi().updateDisplayName(name));
                  },
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final human = state.human;
    final life = state.life;
    final health = asDouble(human['health'] ?? human['vitality']);
    final energy = asDouble(human['energy'] ?? human['stamina']);
    final age = asInt(human['age_years'] ?? human['age'] ?? life['ageYears']);
    final legacy = asDouble(human['legacy'] ?? life['legacy']);
    final fullName =
        (human['display_name'] ?? human['name'] ?? 'YOUR LIFE').toString().trim();
    final lifeStatus =
        life['status']?.toString() ?? human['life_status']?.toString();

    final cityName = state.institutions['city'] is Map
        ? (state.institutions['city'] as Map)['name']?.toString().toUpperCase()
        : null;

    final healthColor =
        health != null && health < 40 ? context.warningColor : context.successColor;

    return EarthSection(
      title: 'MY LIFE TODAY',
      showSurface: false,
      infoBulletPoints: const [
        'Your current personal situation: health, energy, residence, work, and legacy.',
        'Values marked unavailable require current personal data; they are not estimates.',
        'Detailed financial and asset records remain in Finance and Business.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fullName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: context.pageTitleStyle,
                ),
                if (action != null) ...[
                  SizedBox(width: context.spacingInline),
                  IconButton(
                    tooltip: 'Edit name',
                    icon: Icon(
                      Icons.edit_outlined,
                      size: context.iconSize,
                      color: context.primaryColor,
                    ),
                    onPressed: busy ? null : () => _editName(context),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: context.spacingTitleOffset),
          EarthMetricGrid(
            metrics: [
              if (cityName != null)
                EarthMetricTile(
                  label: 'RESIDENCE',
                  value: cityName,
                  subtitle: 'Current municipal location',
                  icon: Icons.location_city_outlined,
                  accentColor: context.secondaryColor,
                ),
              EarthMetricTile(
                label: 'AGE',
                value: age == null ? 'UNAVAILABLE' : 'Age $age',
                subtitle: (lifeStatus ?? 'ACTIVE').toUpperCase(),
                icon: Icons.person_outline,
                accentColor: context.primaryColor,
              ),
              EarthMetricTile(
                label: 'HEALTH',
                value: health == null ? 'UNAVAILABLE' : '${health.toStringAsFixed(0)}%',
                subtitle: 'Personal wellbeing',
                icon: Icons.favorite_outline,
                accentColor: healthColor,
              ),
              EarthMetricTile(
                label: 'LIFE ENERGY',
                value: energy == null ? 'UNAVAILABLE' : '${energy.toStringAsFixed(0)}%',
                subtitle: 'Daily capacity',
                icon: Icons.bolt_outlined,
                accentColor: context.warningColor,
              ),
              if (cityName == null)
                EarthMetricTile(
                  label: 'LEGACY',
                  value: legacy == null ? 'UNAVAILABLE' : formatWholeNumber(legacy),
                  subtitle: 'Lifetime contribution',
                  icon: Icons.auto_awesome_outlined,
                  accentColor: context.secondaryColor,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class SuccessionPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const SuccessionPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final life = state.life;
    final human = state.human;
    final lifeStatus = (life['status']?.toString() ??
            human['life_status']?.toString() ??
            'active')
        .toLowerCase();
    final age = asIntOr(
        life['ageYears'] ?? human['age_years'] ?? human['ageYears'], 31);
    final dynastyName = (life['dynastyName'] ?? life['dynasty_name'])?.toString();
    final dynastyGeneration = asIntOr(
        life['generation'] ?? human['generation'], 1);
    final rawSuccessor = life['successor'];
    final successor =
        rawSuccessor is Map<String, dynamic> ? rawSuccessor : null;
    final successorName = successor?['successor_name']?.toString() ??
        successor?['name']?.toString();
    final successorHumanId = successor?['successor_human_id']?.toString() ??
        successor?['successorHumanId']?.toString();
    final registeredDay =
        successor?['registered_game_day'] ?? successor?['registeredOnDay'];
    final estatePeriodDays = asIntOr(
        successor?['estate_period_days'] ?? life['estatePeriodDays'], 30);

    final heirPct = asIntOr(successor?['heir_pct'], 70);
    final trustPct = asIntOr(successor?['trust_pct'], 20);
    final reservePct = asIntOr(successor?['reserve_pct'], 10);

    final isEstatePeriod = lifeStatus == 'estate';
    final isDeceased = lifeStatus == 'deceased';

    Color statusColor = context.primaryColor;
    if (isEstatePeriod) statusColor = context.warningColor;
    if (isDeceased) statusColor = context.errorColor;

    String generationalStage = 'PRIME OPERATIVE (100% LABOR EFFICIENCY)';
    Color stageColor = context.primaryColor;
    if (age >= 65) {
      generationalStage =
          'DYNASTIC PATRIARCH/MATRIARCH (+25% GOVERNANCE WISDOM)';
      stageColor = context.secondaryColor;
    } else if (age >= 45) {
      generationalStage = 'SENIOR EXECUTIVE (BALANCED PRODUCTIVITY)';
      stageColor = context.successColor;
    }

    final credits = asDouble(human['credits']) ?? 0.0;
    final estimatedTax = isEstatePeriod ? credits * 0.20 : credits * 0.10;
    final estimatedNet = (credits - estimatedTax).clamp(0.0, double.infinity);

    return EarthSection(
      title: 'LIFE & LEGACY / SUCCESSION PLAN',
      showSurface: false,
      infoBulletPoints: const [
        'Your succession plan keeps your work, assets, and responsibilities moving forward.',
        'At the end of this life, you can continue as a registered heir who receives the estate, or begin a new adult character and carry forward part of the dynasty legacy.',
        'A new character starts in a city and follows that city’s corporation affiliation; leaving that corporation means returning to independent life.',
        'Detailed ownership and financial records belong in Business and Finance; this page focuses on the person and their legacy.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BIOLOGICAL AGE & GENERATIONAL STAGE
          Container(
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('BIOLOGICAL AGE: ', style: context.widgetTitleStyle),
                        Text('$age YEARS', style: context.widgetValueStyle),
                      ],
                    ),
                    EarthBadge(
                      label: lifeStatus.toUpperCase(),
                      customColor: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                EarthBadge(
                  label: generationalStage,
                  customColor: stageColor,
                ),
                if (dynastyName != null && dynastyName.trim().isNotEmpty) ...[
                  SizedBox(height: context.spacingTopic),
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: context.iconSize,
                          color: context.primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'HOUSE ${dynastyName.toUpperCase()} · GENERATION $dynastyGeneration',
                          style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: (age / 90.0).clamp(0.0, 1.0),
                    minHeight: 5,
                    color: stageColor,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Life stage and succession readiness are based on your current profile',
                  style: context.widgetFooterStyle,
                ),
              ],
            ),
          ),

          SizedBox(height: context.spacingTitleOffset),

          // 2. TESTAMENTARY WILL & SUCCESSOR PLAN
          if (successorName != null) ...[
            Container(
              padding: EdgeInsets.all(context.cardPadding),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(context.radiusCard),
                border: Border.all(color: context.subtleBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history_edu_outlined,
                          size: context.iconSize, color: context.primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'SUCCESSOR: $successorName ${successorHumanId != null ? '($successorHumanId)' : ''}',
                          style: context.widgetValueStyle.copyWith(color: context.inkColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Registered on Day $registeredDay · Estate buffer: $estatePeriodDays days',
                    style: context.widgetFooterStyle,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      EarthStatusPill(
                          label: 'PRIMARY HEIR', value: '$heirPct%', color: context.primaryColor),
                      EarthStatusPill(
                          label: 'MUNICIPAL TRUST', value: '$trustPct%', color: context.successColor),
                      EarthStatusPill(
                          label: 'DYNASTIC RESERVE', value: '$reservePct%', color: context.secondaryColor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Est. Net Transfer: ~${formatCreditsAmount(estimatedNet)} (after ~${formatCreditsAmount(estimatedTax)} estate tax)',
                    style: context.widgetFooterStyle.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEstatePeriod
                        ? 'Estate state: ACTIVE ESTATE PERIOD (Awaiting settlement or liquidation)'
                        : 'Estate state: PENDING (Protected transition ready upon mortality)',
                    style: context.widgetFooterStyle.copyWith(
                      color: isEstatePeriod ? context.warningColor : context.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'No succession plan registered. In the event of mortality, unclaimed assets will be liquidated to the municipal treasury after the estate period.',
              style: context.bodyStyle,
            ),
          ],
          SizedBox(height: context.spacingTitleOffset),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EarthButton(
                label: successorName == null
                    ? 'PLAN SUCCESSION & WILL'
                    : 'UPDATE WILL & SUCCESSOR',
                icon: Icons.edit_note_outlined,
                variant: EarthButtonVariant.secondary,
                onPressed: busy
                    ? null
                    : () => showSuccessorComposerDialog(context, action),
              ),
              if (isEstatePeriod && successorName != null)
                EarthButton(
                  label: 'SETTLE ESTATE INHERITANCE',
                  variant: EarthButtonVariant.primary,
                  onPressed: busy
                      ? null
                      : () => showSettleInheritanceDialog(
                            context,
                            action,
                            predecessorId: human['id']?.toString() ?? 'H-0044',
                            defaultSuccessorName: successorName,
                          ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class LegacyPersonalFinancePanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const LegacyPersonalFinancePanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'PERSONAL FINANCE / PROTECTED MINIMUM',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status: ${state.personalFinance['status'] ?? 'active'}  ·  protected minimum ${state.personalFinance['protected_credits'] ?? 100} C',
            style: const TextStyle(color: mutedColor, fontSize: 11),
          ),
          const SizedBox(height: 6),
          const Text(
            'A restructuring preserves one basic service robot and the protected Credit minimum; non-protected productive assets are liquidated.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
          const SizedBox(height: 8),
          if (state.personalFinance['status'] != 'bankrupt')
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => action(
                      () => const EarthApi().declarePersonalInsolvency()),
              child: const Text('DECLARE INSOLVENCY RESTRUCTURING'),
            ),
        ],
      ),
    );
  }
}

class InstitutionSolvencyPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const InstitutionSolvencyPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'INSTITUTION SOLVENCY / RECOVERY',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Institutional Solvency & Recapitalization: Statutory economic health monitoring for municipal cities and corporate enterprises.\n\n• Solvency Tiers:\n  - SOLVENT: Normal operations; reserves satisfy all statutory coverage buffers.\n  - DISTRESSED: Reserves below operating minimums; public services rationed.\n  - INSOLVENT: Treasury exhausted; automatic liquidation begins unless recapitalized.\n\n• Recapitalization Recovery: Citizens may contribute equity credits to restore insolvent or distressed institutions back to active legal status.',
      child: state.financeStatus.isEmpty
          ? const Text(
              'Financial states will appear after the next world-day assessment.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: state.financeStatus.map((raw) {
                final item = raw as Map<String, dynamic>;
                final kind =
                    (item['institution_kind']?.toString() ?? 'INSTITUTION')
                        .toUpperCase();
                final id = item['institution_id']?.toString() ?? '';
                final status =
                    (item['status']?.toString() ?? 'SOLVENT').toUpperCase();
                final sinceDay = item['since_game_day']?.toString() ?? '—';

                final crisis = status == 'DISTRESSED' || status == 'INSOLVENT';
                final recoverable = kind == 'CITY' || kind == 'CORPORATION';

                Color statusColor = cyanAccentColor;
                if (status == 'DISTRESSED') statusColor = Colors.orangeAccent;
                if (status == 'INSOLVENT') statusColor = Colors.redAccent;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: crisis
                          ? statusColor.withValues(alpha: .4)
                          : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          kind == 'CITY'
                              ? Icons.location_city_outlined
                              : Icons.domain_outlined,
                          size: 16,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$kind $id',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: inkColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: .15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color:
                                            statusColor.withValues(alpha: .3)),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$kind $id  ·  ${item['status']}  ·  since day $sinceDay',
                              style: const TextStyle(
                                  fontSize: 10.5, color: mutedColor),
                            ),
                          ],
                        ),
                      ),
                      if (crisis && recoverable) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                          ),
                          onPressed: busy
                              ? null
                              : () => showRecoveryDialog(
                                    context,
                                    action,
                                    item['institution_id'] as String,
                                    item['institution_kind'] as String,
                                  ),
                          icon: const Icon(Icons.healing_outlined, size: 14),
                          label: const Text('RECOVER',
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class NegotiatedContractsPanel extends StatelessWidget {
  final EarthState state;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;

  const NegotiatedContractsPanel({
    super.key,
    required this.state,
    required this.busy,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final canArbitrate = state.roles.any((raw) {
      final role = raw as Map<String, dynamic>;
      return role['id'] == 'ROLE-OUC-DELEGATE' &&
          (role['human_id'] == state.human['id'] ||
              role['delegate_id'] == state.human['id']);
    });

    return EarthPanel(
      title: 'NEGOTIATED CONTRACTS / DIRECT AGREEMENTS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.contracts.isEmpty)
            const Text('No direct agreements yet.',
                style: TextStyle(color: mutedColor, fontSize: 11))
          else
            ...state.contracts.take(8).map((raw) {
              final contract = raw as Map<String, dynamic>;
              final mine = contract['proposer_id'] == state.human['id'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${contract['title']}  ·  ${contract['kind']}  ·  ${contract['status']}  ·  ${contract['amount']} C',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    if (contract['status'] == 'proposed' && !mine)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => action(() => const EarthApi()
                                .acceptContract(contract['id'] as String)),
                        child: const Text('ACCEPT'),
                      ),
                    if (contract['status'] == 'proposed')
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => action(() => const EarthApi()
                                .cancelContract(contract['id'] as String)),
                        child: const Text('CANCEL'),
                      ),
                    if ((contract['status'] == 'accepted' ||
                            contract['status'] == 'completed') &&
                        contract['dispute_id'] == null)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => showDisputeDialog(
                                context, action, contract['id'] as String),
                        child: const Text('DISPUTE'),
                      ),
                    if (contract['dispute_id'] != null)
                      const Text(
                        'DISPUTE OPEN',
                        style: TextStyle(color: Colors.orange, fontSize: 10),
                      ),
                    if (canArbitrate && contract['dispute_id'] != null)
                      OutlinedButton(
                        onPressed: busy
                            ? null
                            : () => showResolveDialog(
                                context, action, contract['id'] as String),
                        child: const Text('ARBITRATE'),
                      ),
                  ],
                ),
              );
            }),
          OutlinedButton(
            onPressed:
                busy ? null : () => showContractComposerDialog(context, action),
            child: const Text('PROPOSE AGREEMENT'),
          ),
        ],
      ),
    );
  }
}

class LedgerPanel extends StatelessWidget {
  final EarthState state;

  const LedgerPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final entries = state.ledgerEntries;

    return EarthPanel(
      title: 'CENTRAL LEDGER / RECENT ACTIVITY',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Double-Entry Cryptographic Ledger: Immutable journal of all currency and asset flows across central clearing, dividend distributions, tax assessments, and peer transfers.\n\n• Invariant Protection: Every debit from a source account is strictly matched with an equal credit to a destination account, ensuring mathematical equilibrium and zero synthetic money leakage.\n\n• Audit Traceability: Transactions record immutable reason codes, amounts, and source-to-destination routing.',
      child: entries.isEmpty
          ? const Text(
              'No ledger activity recorded yet.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Container(
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: entries.take(10).indexed.map((indexed) {
                  final entry = indexed.$2 as Map<String, dynamic>;
                  final isLast = indexed.$1 == entries.take(10).length - 1;
                  final reason =
                      (entry['reason_type']?.toString() ?? 'TRANSFER')
                          .toUpperCase();
                  final amount = entry['amount'] ?? 0;
                  final currency =
                      (entry['currency']?.toString() ?? 'C').toUpperCase();
                  final debit =
                      entry['debit_account']?.toString() ?? 'SYSTEM_ESCROW';
                  final credit =
                      entry['credit_account']?.toString() ?? 'CITIZEN_WALLET';

                  Color reasonColor = cyanAccentColor;
                  IconData reasonIcon = Icons.swap_horiz_rounded;

                  if (reason.contains('TAX')) {
                    reasonColor = Colors.orangeAccent;
                    reasonIcon = Icons.receipt_long_outlined;
                  } else if (reason.contains('DIVIDEND') ||
                      reason.contains('INCOME')) {
                    reasonColor = violetColor;
                    reasonIcon = Icons.paid_outlined;
                  } else if (reason.contains('MARKET') ||
                      reason.contains('ORDER')) {
                    reasonColor = Colors.tealAccent;
                    reasonIcon = Icons.storefront_outlined;
                  } else if (reason.contains('FEE') ||
                      reason.contains('PENALTY')) {
                    reasonColor = Colors.redAccent;
                    reasonIcon = Icons.gavel_outlined;
                  }

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: reasonColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(reasonIcon, size: 14, color: reasonColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: reasonColor,
                                  letterSpacing: .6,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$debit → $credit',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: mutedColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text(
                            '$amount $currency',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: inkColor,
                              letterSpacing: -.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}

class WorldFeedPanel extends StatelessWidget {
  final List<dynamic> events;

  const WorldFeedPanel({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'WORLD FEED / RECENT EVENTS',
      child: events.isEmpty
          ? const Text('No public events recorded yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: events.take(8).map((raw) {
                final event = raw as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '${event['type']}  ·  ${event['actor']}  ·  ${event['occurred_at']}',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class NotificationsPanel extends StatelessWidget {
  final List<dynamic> notifications;
  final int unreadNotifications;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final EarthState state;

  const NotificationsPanel({
    super.key,
    required this.notifications,
    required this.unreadNotifications,
    required this.busy,
    required this.action,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'NOTIFICATIONS / $unreadNotifications UNREAD',
      child: notifications.isEmpty
          ? const Text('No personal alerts yet.',
              style: TextStyle(color: mutedColor, fontSize: 11))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: notifications.take(8).map((raw) {
                final notification = raw as Map<String, dynamic>;
                final unread = notification['read'] != true && notification['read_at'] == null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${unread ? '• ' : ''}${notification['title']}\n${notification['body']}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                unread ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread)
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => action(() async {
                                    await const EarthApi().markNotificationRead(
                                        notification['id'] as String);
                                    return state;
                                  }),
                          child: const Text('READ'),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class OwnershipTimelinePanel extends StatelessWidget {
  final List<dynamic> ownershipEvents;

  const OwnershipTimelinePanel({super.key, required this.ownershipEvents});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'OWNERSHIP / PROVENANCE TIMELINE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Asset Provenance & Lineage: Immutable historical record tracking legal titles, transfers, acquisitions, and ownership transitions.\n\n• Asset Classes: Tracks industrial machines, enterprise equity shares, technological patents, and civic facilities.\n\n• Audit Chain: Every transfer verifies historical custody, preventing counterparty dispute and counterfeit claims.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lifecycleTopicHeading(context, 'OWNERSHIP / PROVENANCE TIMELINE',
              description:
                  '• Immutable record of legal titles, transfers, acquisitions, and ownership transitions.'),
          if (ownershipEvents.isEmpty)
            const Text(
              'Your asset provenance history will appear here after your first acquisition or transfer.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: surfaceColor.withValues(alpha: .75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: ownershipEvents.take(10).indexed.map((indexed) {
                  final event = indexed.$2 as Map<String, dynamic>;
                  final isLast =
                      indexed.$1 == ownershipEvents.take(10).length - 1;
                  final direction = event['from_owner_id'] == null
                      ? 'ACQUIRED'
                      : 'TRANSFERRED';
                  final isAcquired = direction == 'ACQUIRED';
                  final assetType = (event['asset_type']?.toString() ?? 'ASSET')
                      .toUpperCase();
                  final assetId = event['asset_id']?.toString() ?? '—';
                  final qty = event['quantity'] ?? 1;
                  final gameDay = event['game_day'] ?? '—';
                  final fromOwner =
                      event['from_owner_id']?.toString() ?? 'ORIGIN_TREASURY';
                  final toOwner =
                      event['to_owner_id']?.toString() ?? 'CURRENT_HOLDER';

                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isAcquired
                                ? cyanAccentColor.withValues(alpha: .15)
                                : violetColor.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            isAcquired
                                ? Icons.add_circle_outline_rounded
                                : Icons.swap_horiz_rounded,
                            size: 14,
                            color: isAcquired ? cyanAccentColor : violetColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .06),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      'DAY $gameDay',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: mutedColor,
                                        letterSpacing: .5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$assetType · $assetId ($qty units)',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: inkColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$fromOwner → $toOwner',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: mutedColor,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: (isAcquired ? cyanAccentColor : violetColor)
                                .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color:
                                  (isAcquired ? cyanAccentColor : violetColor)
                                      .withValues(alpha: .3),
                            ),
                          ),
                          child: Text(
                            direction,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .6,
                              color: isAcquired ? cyanAccentColor : violetColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class CivicMembershipHistoryPanel extends StatelessWidget {
  final List<dynamic> membershipEvents;

  const CivicMembershipHistoryPanel(
      {super.key, required this.membershipEvents});

  @override
  Widget build(BuildContext context) {
    const infoText =
        '• Civic & Corporate Affiliation Journal: Chronological record of citizenship declarations, municipal registrations, and corporate charters.\n\n• Affiliation Records:\n  - JOIN_CITY / RESIDE: Residential affiliation establishing eligibility for municipal services and local voting.\n  - FOUND_ENTERPRISE / INCORPORATE: Corporate legal registration establishing commercial limited liability.\n  - JOIN_COMMUNITY: Collective civic association membership.';

    final eventsToDisplay =
        membershipEvents.take(8).whereType<Map<String, dynamic>>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'CIVIC STATUS / MEMBERSHIP HISTORY',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: mutedColor,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 14, color: mutedColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Info',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: EarthColors.cardSurface,
                    title: const Text(
                      'CIVIC STATUS / MEMBERSHIP HISTORY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: cyanAccentColor,
                      ),
                    ),
                    content: const Text(
                      infoText,
                      style: TextStyle(fontSize: 11, color: inkColor),
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
        eventsToDisplay.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Text(
                  'Your civic and corporate history will appear here after joining an institution.',
                  style: TextStyle(color: mutedColor, fontSize: 11),
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: eventsToDisplay.indexed.map((indexed) {
                    final event = indexed.$2;
                    final isLast = indexed.$1 == eventsToDisplay.length - 1;
                    final day = event['game_day']?.toString() ?? '-';
                    final type =
                        (event['institution_type']?.toString() ?? 'CIVIC')
                            .toUpperCase();
                    final id = event['institution_id']?.toString() ?? '';
                    final action =
                        (event['action']?.toString() ?? 'JOIN').toUpperCase();

                    Color typeColor = cyanAccentColor;
                    if (type.contains('CORP')) typeColor = violetColor;
                    if (type.contains('COMMUNITY')) {
                      typeColor = Colors.tealAccent;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .05),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'DAY $day',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: mutedColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: typeColor.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: typeColor.withValues(alpha: .3)),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: typeColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              id,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: inkColor,
                              ),
                            ),
                          ),
                          Text(
                            action,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: inkColor,
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
}

class AuthorityHistoryPanel extends StatelessWidget {
  final List<dynamic> authorityEvents;

  const AuthorityHistoryPanel({super.key, required this.authorityEvents});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'AUTHORITY / GOVERNANCE HISTORY',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Governance & Authority Journal: Canonical record of institutional role transitions, constitutional delegations, and executive responsibilities.\n\n• Authority Lifecycle:\n  - CLAIM_ROLE: Assumption of public office, ministerial oversight, or judicial delegacy.\n  - DELEGATE_ROLE: Formal delegation of voting or arbitral authority to a designated citizen surrogate.\n  - RESIGN_ROLE: Orderly devolution of office upon term completion or voluntary departure.',
      child: authorityEvents.isEmpty
          ? const Text(
              'Role claims and resignations will appear here as your institutional authority develops.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: authorityEvents.take(8).map((raw) {
                if (raw is! Map<String, dynamic>) {
                  return const SizedBox.shrink();
                }
                final event = raw;
                final day = event['game_day']?.toString() ?? '-';
                final action =
                    (event['action']?.toString() ?? 'CLAIM').toUpperCase();
                final roleId = event['role_id']?.toString() ?? 'ROLE';

                Color actionColor = cyanAccentColor;
                IconData actionIcon = Icons.verified_user_outlined;

                if (action.contains('RESIGN')) {
                  actionColor = Colors.orangeAccent;
                  actionIcon = Icons.logout_rounded;
                } else if (action.contains('DELEGATE')) {
                  actionColor = violetColor;
                  actionIcon = Icons.forward_to_inbox_outlined;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: surfaceColor.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(actionIcon, size: 14, color: actionColor),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DAY $day',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: mutedColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ROLE: $roleId',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: inkColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: actionColor.withValues(alpha: .3)),
                        ),
                        child: Text(
                          action,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: actionColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class RankingLine extends StatelessWidget {
  final String label;
  final dynamic rows;

  const RankingLine(this.label, this.rows, {super.key});

  IconData _getIconForLabel(String l) {
    if (l.contains('CIT')) return Icons.location_city_outlined;
    if (l.contains('CORP')) return Icons.domain_outlined;
    if (l.contains('HUMAN')) return Icons.person_outline;
    return Icons.biotech_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final list = rows is List ? rows : const [];
    final first = list.isEmpty ? null : list.first as Map<String, dynamic>;
    final value = first == null
        ? 'No entries yet'
        : label == 'CITIES'
            ? '${first['id']}  ·  ${first['residents']} residents'
            : '${first['id']}  ·  ${first['member_count']} members';

    Color accent = cyanAccentColor;
    if (label.contains('CORP')) accent = violetColor;
    if (label.contains('HUMAN')) accent = Colors.tealAccent;
    if (label.contains('TECH')) accent = Colors.amberAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(_getIconForLabel(label), size: 15, color: accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: inkColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WorldRankingsPanel extends StatelessWidget {
  final EarthState state;

  const WorldRankingsPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cities = state.rankings['cities'] is List
        ? state.rankings['cities'] as List
        : [];
    final corps = state.rankings['corporations'] is List
        ? state.rankings['corporations'] as List
        : [];
    final humans = state.rankings['humans'] is List
        ? state.rankings['humans'] as List
        : [];
    final tech = state.rankings['technologies'] is List
        ? state.rankings['technologies'] as List
        : [];

    return EarthPanel(
      title: 'WORLD RANKINGS / POSTGRES LIVE',
      showSurface: false,
      contentPadding: EdgeInsets.zero,
      helpAfterTitle: true,
      titleColor: mutedColor,
      infoDescription:
          '• Civilizational Leaderboards & Metrics: Live global rankings aggregated across all planetary municipalities, corporate conglomerates, citizen leaders, and technology portfolios.\n\n• Competitive Benchmarks:\n  - CITIES: Ranked by resident population, public service stability, and housing/energy capacity.\n  - CORPORATIONS: Ranked by member count, treasury reserves, and industrial output.\n  - CITIZENS: Ranked by civic standing, legacy points, and net wealth.\n  - TECHNOLOGIES: Ranked by active patent licenses and diffusion rate.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Leaderboards Action Header
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: EarthColors.goldMetallic.withAlpha(100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events,
                    color: EarthColors.goldMetallic, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GLOBAL CIVILIZATIONAL LEADERBOARDS',
                        style: TextStyle(
                          color: EarthColors.goldMetallic,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Explore full rankings, apex podiums, rank deltas, and citizen tiers.',
                        style: TextStyle(
                            color: EarthColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (ctx) => ElevatedButton.icon(
                    onPressed: () =>
                        showGlobalRankingsDialog(ctx, state: state),
                    icon: const Icon(Icons.leaderboard, size: 16),
                    label: const Text('EXPLORE LEADERBOARDS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EarthColors.goldMetallic,
                      foregroundColor: Colors.black,
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

          RankingLine('CITIES', cities),
          const SizedBox(height: 8),
          RankingLine('CORPORATIONS', corps),
          if (humans.isNotEmpty) ...[
            const SizedBox(height: 8),
            RankingLine('HUMANS', humans),
          ],
          if (tech.isNotEmpty) ...[
            const SizedBox(height: 8),
            RankingLine('TECHNOLOGY', tech),
          ],
        ],
      ),
    );
  }
}

class HistoryArchivePanel extends StatelessWidget {
  final EarthState state;

  const HistoryArchivePanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final events = (state.history['events'] as List<dynamic>?) ?? const [];

    return EarthPanel(
      title: 'HISTORY / ARCHIVE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• World Chronicle & Epoch Archive: Canonical historical archive recording civilizational milestones, macro crises, planetary ecological tipping points, and generational transitions.\n\n• Legacy Preservation: Permanent historical ledger ensuring human achievements and societal governance decisions are preserved across all eras.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lifecycleTopicHeading(context, 'HISTORY / ARCHIVE',
              description:
                  '• Canonical historical archive for world milestones, crises, and generational transitions.'),
          if (events.isEmpty)
            const Text(
              'The historical chronicle is waiting for the first recorded world day milestone.',
              style: TextStyle(color: mutedColor, fontSize: 11),
            )
          else
            ...events.take(8).map((raw) {
              final event = raw as Map<String, dynamic>;
              final gameDay = event['game_day'] ?? '—';
              final title = event['title'] ??
                  event['type'] ??
                  'Historical Epoch Milestone';
              final desc = event['description']?.toString() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: violetColor.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.history_edu_outlined,
                        size: 14,
                        color: violetColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DAY $gameDay  ·  $title',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: inkColor,
                            ),
                          ),
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: mutedColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 6),
          const Text(
            'Rankings and Human legacies are permanently archived as world epochs advance.',
            style: TextStyle(color: mutedColor, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class PantheonPanel extends StatelessWidget {
  final Map<String, dynamic> pantheon;

  const PantheonPanel({super.key, required this.pantheon});

  @override
  Widget build(BuildContext context) {
    final deceased =
        (pantheon['deceasedPantheon'] as List<dynamic>?) ?? const [];
    final living = (pantheon['livingLeaders'] as List<dynamic>?) ?? const [];
    final achievements =
        (pantheon['achievements'] as List<dynamic>?) ?? const [];

    return EarthSection(
      title: 'PANTHEON / DYNASTIC ARCHIVE & LEGACY',
      showSurface: false,
      infoBulletPoints: const [
        'Persistent Civilization Record: When a citizen passes away, their biographical, economic, and political record is permanently inscribed in the UC Historical Archive.',
        'Multi-Generational Dynastic Lineage: Tracks continuous succession chains from founding ancestors to living heirs.',
        'Composite Legacy Score: Calculated across lifetime economic production, public civic service, philanthropic endowments, and constitutional stability.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cemetery Action Header Card
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: context.spacingTopic),
            padding: EdgeInsets.all(context.cardPadding),
            decoration: BoxDecoration(
              color: context.surfaceColor.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(context.radiusCard),
              border: Border.all(color: context.primaryColor.withValues(alpha: .35)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance,
                  color: context.primaryColor,
                  size: context.iconSize + 4,
                ),
                SizedBox(width: context.spacingTitleOffset),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PLANETARY CEMETERY & MEMORIAL ARCHIVE',
                        style: context.topicTitleStyle.copyWith(color: context.primaryColor),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Search all inscribed citizen records, eulogies, and multi-generational lineages.',
                        style: context.widgetFooterStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 1. Dynastic Succession Lineage Tree
          Text(
            'DYNASTIC SUCCESSION LINEAGE TREE',
            style: context.widgetTitleStyle,
          ),
          SizedBox(height: context.spacingInline),

          Builder(builder: (context) {
            final recorded = <Map<String, dynamic>>[
              ...deceased.whereType<Map>().map((raw) => Map<String, dynamic>.from(raw)),
              ...living.whereType<Map>().map((raw) => Map<String, dynamic>.from(raw)),
            ];
            if (recorded.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: context.spacingInline),
                child: Text(
                  'No dynasty lineage records are available yet. Your first succession will establish the family archive.',
                  style: context.bodyStyle.copyWith(color: context.mutedColor),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: recorded.indexed.map((indexed) {
                final entry = indexed.$2;
                final generation = entry['generation'] ?? indexed.$1 + 1;
                final isLiving = entry['death_game_day'] == null &&
                    entry['deathGameDay'] == null;
                final name = entry['display_name'] ?? entry['name'] ?? 'Unknown Human';
                final score = entry['final_legacy'] ??
                    entry['composite_legacy_score'] ?? entry['legacy'] ?? 0;
                final node = _dynastyNode(
                  context: context,
                  generation: 'GEN $generation · ${isLiving ? 'CURRENT ACTIVE CITIZEN' : 'ANCESTOR'}',
                  name: name.toString(),
                  details: isLiving ? 'Active · Current dynasty member' : 'Archived · Historical dynasty member',
                  score: score.toString(),
                  color: isLiving ? context.primaryColor : context.secondaryColor,
                  isLast: indexed.$1 == recorded.length - 1,
                );
                return indexed.$1 == recorded.length - 1
                    ? node
                    : Column(children: [node, _treeConnector()]);
              }).toList(),
            );
          }),

          SizedBox(height: context.spacingTopic),

          // 2. Historical Cemetery Archive
          if (deceased.isNotEmpty) ...[
            Text(
              'HISTORICAL CEMETERY ARCHIVE',
              style: context.widgetTitleStyle,
            ),
            SizedBox(height: context.spacingInline),
            EarthDataList(
              children: deceased.take(3).indexed.map((indexed) {
                final entry = indexed.$2 as Map<String, dynamic>;
                final isLast = indexed.$1 == deceased.take(3).length - 1;
                final name = entry['display_name'] ?? 'Unknown';
                final legacy = entry['final_legacy'] ?? 0;
                final day = entry['death_game_day'] ?? 0;
                return EarthDataRow(
                  title: '$name',
                  subtitle: 'Deceased Day $day · Legacy: $legacy L',
                  leading: Icon(
                    Icons.archive_outlined,
                    size: context.iconSize - 2,
                    color: context.secondaryColor,
                  ),
                  showDivider: !isLast,
                );
              }).toList(),
            ),
          ],

          if (achievements.isNotEmpty) ...[
            SizedBox(height: context.spacingTitleOffset),
            Text(
              'PLANETARY ACHIEVEMENTS UNLOCKED',
              style: context.widgetTitleStyle,
            ),
            SizedBox(height: context.spacingInline),
            ...achievements.take(3).map((raw) {
              final entry = raw as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: EdgeInsets.symmetric(
                  horizontal: context.tokens.number('pageTopics.cardPadding', 10),
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: context.primaryColor.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(context.radiusCard),
                  border: Border.all(color: context.primaryColor.withValues(alpha: .2)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: context.iconSize,
                      color: context.primaryColor,
                    ),
                    SizedBox(width: context.spacingInline),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['name']?.toString() ?? 'Achievement',
                            style: context.widgetValueStyle.copyWith(color: context.inkColor),
                          ),
                          Text(
                            entry['description']?.toString() ?? 'Completed milestone',
                            style: context.widgetFooterStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _dynastyNode({
    required BuildContext context,
    required String generation,
    required String name,
    required String details,
    required String score,
    required Color color,
    required bool isLast,
  }) {
    return Container(
      padding: EdgeInsets.all(context.tokens.number('pageTopics.cardPadding', 10)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: color.withValues(alpha: .2),
            child: Icon(
              Icons.person_outline,
              size: context.iconSize - 3,
              color: color,
            ),
          ),
          SizedBox(width: context.spacingInline),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      generation,
                      style: context.captionStyle.copyWith(color: color),
                    ),
                    Text(
                      '$score L',
                      style: context.widgetTitleStyle.copyWith(color: color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: context.widgetValueStyle.copyWith(color: context.inkColor),
                ),
                Text(
                  details,
                  style: context.widgetFooterStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _treeConnector() => Container(
        margin: const EdgeInsets.only(left: 20),
        width: 2,
        height: 10,
        color: Colors.white24,
      );
}

class WorldIntegrityPanel extends StatelessWidget {
  final EarthState state;

  const WorldIntegrityPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return EarthPanel(
      title: 'WORLD INTEGRITY / AUDIT',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: state.audit.entries.map((entry) {
          final isBool = entry.value is bool;
          final isOk = isBool ? (entry.value as bool) : entry.value != null;
          final valStr = isBool
              ? ((entry.value as bool) ? 'OK' : 'CHECK')
              : entry.value.toString();
          return Chip(
            label: Text(
              '${entry.key}: $valStr',
              style: const TextStyle(fontSize: 10),
            ),
            avatar: Icon(
              isOk ? Icons.check_circle : Icons.warning,
              size: 14,
              color: isOk ? cyanAccentColor : Colors.orange,
            ),
            backgroundColor: Colors.white10,
          );
        }).toList(),
      ),
    );
  }
}

class MacroLiquidityPanel extends StatelessWidget {
  final EarthState state;

  const MacroLiquidityPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final liq = (state.finance['liquidity'] as Map<String, dynamic>?) ?? {};
    final supplyVal = asDouble(liq['moneySupply']);
    final targetVal = asDouble(liq['target']);
    final supplyStr =
        supplyVal != null ? formatCreditsAmount(supplyVal) : '142,500.00 C';
    final targetStr =
        targetVal != null ? formatCreditsAmount(targetVal) : '150,000.00 C';

    final cpiVal = asDouble(liq['cpi']) ?? 102.4;
    final cpiDelta = cpiVal - 100.0;
    final cpiDeltaStr = (cpiDelta >= 0
        ? '+${cpiDelta.toStringAsFixed(1)}%'
        : '${cpiDelta.toStringAsFixed(1)}%');

    final giniVal = asDouble(liq['gini']) ?? 0.28;
    final giniLabel = giniVal <= 0.35
        ? 'EQUITABLE'
        : (giniVal <= 0.50 ? 'MODERATE' : 'CONCENTRATED');

    final velocityVal = asDouble(liq['velocity']) ?? 1.84;

    return EarthPanel(
      title: 'UC MONETARY STABILITY BOARD / MACRO BASE',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• UC Monetary Stability Board Charter (Spec §1.7.2, §1.9):\n  - Oversees world money supply (M0), stabilizes consumer price indices, and guarantees the 100% Reserve Standard across all municipal jurisdictions.\n\n• Core Macroeconomic Indicators:\n  - M0 Circulating Money Supply: Total Credits in circulation across all citizen wallets, corporate treasuries, and municipal accounts. Strictly conserved with zero unbacked fractional printing.\n  - 30-Day Consumer Price Index (CPI-30): Weighted price basket across the 4 core commodities (Food, Energy, Materials, Compute) indexed against base 100.0.\n  - Planetary Wealth Gini Coefficient: Quantifies systemic wealth inequality (0.00 = perfect equality, 1.00 = maximum concentration). Guardrail corridor triggers progressive fiscal levies above 0.45.\n  - Currency Velocity (V): Daily transactional turn rate measuring economic vitality and liquidity circulation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lifecycleTopicHeading(
              context, 'UC MONETARY STABILITY BOARD / MACRO BASE',
              description:
                  '• Review monetary supply, CPI, liquidity corridor, and macroeconomic stability.'),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'CIRCULATING M0',
                      supplyStr,
                      '100% Reserve Conserved',
                      cyanAccentColor,
                      Icons.account_balance_wallet_outlined,
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      '30-DAY CPI',
                      cpiVal.toStringAsFixed(1),
                      '$cpiDeltaStr vs Base 100.0',
                      Colors.tealAccent,
                      Icons.show_chart_outlined,
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'PLANETARY GINI (G)',
                      giniVal.toStringAsFixed(2),
                      '$giniLabel (<0.45 target)',
                      violetColor,
                      Icons.pie_chart_outline,
                    ),
                  ),
                  SizedBox(
                    width: isWide
                        ? (constraints.maxWidth - 36) / 4
                        : (constraints.maxWidth - 12) / 2,
                    child: _metricCard(
                      'MONEY VELOCITY (V)',
                      '${velocityVal.toStringAsFixed(2)}x',
                      'Target M*: $targetStr',
                      Colors.orangeAccent,
                      Icons.speed_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          const Text(
            'The UC Monetary Stability Board maintains the 100% Reserve Standard. Macro money supply is strictly non-inflationary, offsetting demographic shifts via the Central Stability Reserve without currency debasement.',
            style: TextStyle(fontSize: 10, color: mutedColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, String subtext, Color color,
          IconData icon) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: mutedColor,
                      letterSpacing: .6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtext,
              style: const TextStyle(
                fontSize: 8.5,
                color: mutedColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
}

class HumanServicesPanel extends StatelessWidget {
  final EarthState state;
  final Key? panelKey;

  const HumanServicesPanel({super.key, this.panelKey, required this.state});

  IconData _getServiceIcon(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('health') || lower.contains('medical')) {
      return Icons.medical_services_outlined;
    }
    if (lower.contains('edu') || lower.contains('school')) {
      return Icons.school_outlined;
    }
    if (lower.contains('transit') || lower.contains('transport')) {
      return Icons.commute_outlined;
    }
    if (lower.contains('house') || lower.contains('housing')) {
      return Icons.apartment_outlined;
    }
    if (lower.contains('safe') || lower.contains('security')) {
      return Icons.shield_outlined;
    }
    if (lower.contains('power') || lower.contains('utility') || lower.contains('energy')) {
      return Icons.bolt_outlined;
    }
    if (lower.contains('water') || lower.contains('food')) {
      return Icons.water_drop_outlined;
    }
    return Icons.public_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final services = ((state.world['serviceStatus'] as Map<String, dynamic>?) ?? const {});

    return EarthSection(
      key: panelKey,
      title: 'HUMAN SERVICES / CURRENT ACCESS',
      showSurface: false,
      infoBulletPoints: const [
        'Essential Municipal Public Services: Healthcare, housing, energy, water, transit, safety, and education.',
        'Service tiers and availability impact workforce productivity, citizen health, and business operating expenses.',
      ],
      child: services.isEmpty
          ? const EarthEmptyState(
              message: 'Public service status data is currently synchronizing.',
              icon: Icons.public_outlined,
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: services.entries.map((entry) {
                final serviceName = entry.key.toUpperCase();
                final status = entry.value.toString().toLowerCase();

                Color statusColor = context.successColor;
                if (status == 'basic') statusColor = context.warningColor;
                if (status == 'degraded' || status == 'offline') {
                  statusColor = context.errorColor;
                }

                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.tokens.number('pageTopics.cardPadding', 12),
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(context.radiusCard),
                    border: Border.all(color: statusColor.withValues(alpha: .3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getServiceIcon(entry.key), size: context.iconSize, color: statusColor),
                      SizedBox(width: context.spacingInline),
                      Text(
                        serviceName,
                        style: context.widgetValueStyle,
                      ),
                      SizedBox(width: context.spacingInline),
                      EarthBadge(
                        label: status.toUpperCase(),
                        customColor: statusColor,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}
