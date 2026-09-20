import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../core/models/initiative.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';

class InitiativesPanel extends StatefulWidget {
  final EarthState state;
  final Map<String, dynamic> personalFinanceData;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function()) action;
  final EarthApi api;
  final int initialTabIndex;
  const InitiativesPanel({super.key, required this.state, required this.personalFinanceData, required this.busy, required this.action, this.api = const EarthApi(), this.initialTabIndex = 0});
  @override State<InitiativesPanel> createState() => _InitiativesPanelState();
}

class _InitiativesPanelState extends State<InitiativesPanel> {
  InitiativesReadModel? _model;
  String? _error;
  bool _loading = true;
  String _filter = 'ACTIVE';
  String _scope = 'ALL';

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final model = await widget.api.listInitiatives(status: _filter == 'ACTIVE' || _filter == 'MY SUPPORT' ? null : _filter, scope: _scope == 'ALL' ? null : _scope, mySupport: _filter == 'MY SUPPORT');
      if (mounted) setState(() { _model = model; _loading = false; });
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _loading = false; });
    }
  }

  Future<void> _contribute(InitiativeReadModel initiative) async {
    final amount = await showDialog<String>(context: context, builder: (_) => const _InitiativeContributionDialog());
    if (amount == null || !mounted) return;
    try {
      final quote = await widget.api.quoteInitiativeContribution(initiativeId: initiative.id, amountCredit: amount);
      final confirmed = await showDialog<bool>(context: context, builder: (_) => _ContributionReviewDialog(quote: quote));
      if (confirmed != true || !mounted) return;
      await widget.action(() async {
        await widget.api.contributeToInitiative(initiativeId: initiative.id, amountCredit: amount);
        return widget.api.world();
      });
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<InitiativeReadModel> get _visible {
    final rows = _model?.initiatives ?? const <InitiativeReadModel>[];
    if (_filter == 'ACTIVE') return rows.where((row) => row.status == 'FUNDING' || row.status == 'EXECUTING').toList();
    return rows;
  }

  String _scopeLabel(InitiativeScope scope) => scope.type == 'CORPORATION' ? 'MY CORPORATION' : 'EARTH';
  String _outcomeLabel(dynamic outcome) {
    if (outcome is! Map) return 'Outcome details unavailable';
    final type = outcome['type']?.toString().replaceAll('_', ' ') ?? 'OUTCOME';
    return type == 'PRESTIGE' ? (outcome['description']?.toString() ?? type) : type;
  }

  @override Widget build(BuildContext context) {
    final summary = _model?.summary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EarthPageCockpit(tag: 'V5 INITIATIVES', status: 'CANONICAL READ MODEL', statusColor: context.primaryColor, infoTitle: 'INITIATIVES', infoDescription: 'Governance-authorized collective funding and execution. Funding, matching, execution, and outcomes are separate authoritative states.', title: 'INITIATIVES', subtitle: 'Earth and Corporation initiatives', metrics: [
        CockpitMetric(label: 'Active', value: '${summary?.activeCount ?? 0}', icon: Icons.play_circle_outline, color: context.primaryColor),
        CockpitMetric(label: 'Funding now', value: '${summary?.fundingCount ?? 0}', icon: Icons.account_balance_wallet_outlined, color: context.secondaryColor),
        CockpitMetric(label: 'Community capital', value: formatCreditUnits(summary?.communityCapitalUnits), icon: Icons.groups_outlined, color: context.primaryColor),
        CockpitMetric(label: 'My support', value: '${summary?.supportingInitiativesCount ?? 0}', icon: Icons.volunteer_activism_outlined, color: context.secondaryColor),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _filterButton('ACTIVE'), _filterButton('FUNDING'), _filterButton('COMPLETED'), _filterButton('MY SUPPORT'),
        DropdownButton<String>(value: _scope, items: const [DropdownMenuItem(value: 'ALL', child: Text('ALL SCOPES')), DropdownMenuItem(value: 'EARTH', child: Text('EARTH')), DropdownMenuItem(value: 'CORPORATION', child: Text('MY CORPORATION'))], onChanged: (value) { if (value != null) { setState(() => _scope = value); _load(); } }),
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh initiatives'),
      ]),
      const SizedBox(height: 16),
      if (_error != null) EarthEmptyState(message: 'Initiative data is unavailable. Please retry.', icon: Icons.sync_problem_outlined, action: TextButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), label: const Text('RETRY')))
      else if (_loading) const Center(child: CircularProgressIndicator())
      else if (_visible.isEmpty) const EarthEmptyState(message: 'No initiatives match this filter.', icon: Icons.rocket_launch_outlined)
      else EarthDataList(children: _visible.map(_card).toList()),
    ]);
  }

  Widget _filterButton(String value) => OutlinedButton(onPressed: () { setState(() => _filter = value); _load(); }, style: OutlinedButton.styleFrom(backgroundColor: _filter == value ? context.primaryColor.withValues(alpha: .12) : null), child: Text(value));

  Widget _card(InitiativeReadModel initiative) {
    final fundingProgress = (initiative.fundingProgressBps / 10000).clamp(0.0, 1.0);
    final executionProgress = (initiative.execution.progressBps / 10000).clamp(0.0, 1.0);
    final status = initiative.status.toUpperCase();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EarthDataRow(
        title: initiative.name,
        subtitle: '${_scopeLabel(initiative.scope)} · ${initiative.type.replaceAll('_', ' ')} · $status',
        secondarySubtitle: '${formatCreditUnits(initiative.communityContributionUnits)} + ${formatCreditUnits(initiative.matchAppliedUnits)} match / ${formatCreditUnits(initiative.fundingTargetUnits)} · ${initiative.supporterCount} supporting Houses',
        tertiarySubtitle: 'OUTCOME · ${_outcomeLabel(initiative.outcomePreview)}${initiative.houseContributionUnits != '0' ? ' · YOUR HOUSE ${formatCreditUnits(initiative.houseContributionUnits)}' : ''}',
        leading: Icon(initiative.type == 'PROGRAM' ? Icons.public_outlined : Icons.construction_outlined, color: context.primaryColor),
        badges: [EarthBadge(label: status, variant: EarthBadgeVariant.primary)],
        trailing: initiative.capabilities.canContribute && !widget.busy ? TextButton(onPressed: () => _contribute(initiative), child: const Text('CONTRIBUTE')) : null,
      ),
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(initiative.description, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: fundingProgress),
        const SizedBox(height: 3),
        Text('FUNDING ${(initiative.fundingProgressBps / 100).toStringAsFixed(2)}% · closes Day ${initiative.deadlineGameDay ?? '—'}', style: context.captionStyle),
        if (initiative.execution.status != null) ...[
          const SizedBox(height: 5),
          LinearProgressIndicator(value: executionProgress, color: context.secondaryColor),
          Text('EXECUTION ${(initiative.execution.progressBps / 100).toStringAsFixed(2)}% · ${initiative.execution.status}', style: context.captionStyle),
        ],
      ])),
    ]);
  }
}

class _ContributionReviewDialog extends StatelessWidget {
  final InitiativeContributionQuote quote;
  const _ContributionReviewDialog({required this.quote});
  @override Widget build(BuildContext context) => AlertDialog(title: Text('REVIEW CONTRIBUTION'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(quote.initiativeName, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 12), Text('Wallet before  ${formatCreditUnits(quote.walletBeforeUnits)}'), Text('Contribution    ${formatCreditUnits(quote.contributionUnits)}'), Text('Projected match ${formatCreditUnits(quote.projectedMatchingUnits)}'), Text('Wallet after   ${formatCreditUnits(quote.walletAfterUnits)}'), Text('Remaining need ${formatCreditUnits(quote.remainingFundingRequirementUnits)}'), Text('Funding closes Day ${quote.deadlineGameDay ?? '—'}')]), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('CONFIRM'))]);
}

class _InitiativeContributionDialog extends StatefulWidget {
  const _InitiativeContributionDialog();
  @override State<_InitiativeContributionDialog> createState() => _InitiativeContributionDialogState();
}

class _InitiativeContributionDialogState extends State<_InitiativeContributionDialog> {
  final controller = TextEditingController();
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('CONTRIBUTE TO INITIATIVE'), content: TextField(controller: controller, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (CREDIT)')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')), FilledButton(onPressed: RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(controller.text.trim()) && controller.text.trim() != '0' ? () => Navigator.pop(context, controller.text.trim()) : null, child: const Text('CONFIRM'))]);
}
