import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';

class WorldProgramsPanel extends StatefulWidget {
  final Map<String, dynamic> personalFinanceData;
  final bool busy;
  final Future<void> Function(Future<EarthState> Function())? action;

  const WorldProgramsPanel({
    super.key,
    this.personalFinanceData = const {},
    this.busy = false,
    this.action,
  });

  @override
  State<WorldProgramsPanel> createState() => _WorldProgramsPanelState();
}

class _WorldProgramsPanelState extends State<WorldProgramsPanel> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _programs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await const EarthApi().listEarthPrograms();
      if (!mounted) return;
      setState(() {
        _programs = _rows(result['programs']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _createProgram() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _CreateWorldProgramDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await const EarthApi().createGlobalProgram(
        programType: result['programType']!,
        name: result['name']!,
        description: result['description']!,
        targetUnits: result['targetUnits']!,
        authorizedUnits: result['authorizedUnits']!,
        matchingAuthorizedUnits: result['matchingAuthorizedUnits'],
        fundingDeadlineGameDay:
            int.tryParse(result['fundingDeadlineGameDay'] ?? ''),
        proposalId: result['proposalId']!,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _contribute(String programId) async {
    final wallet = _walletAccountId ?? '';
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _ProgramContributionDialog(
              walletAccountId: wallet,
              walletBalance: _walletBalance,
            ));
    if (result == null || !mounted) return;
    try {
      Future<EarthState> submit() => const EarthApi()
          .contributeToGlobalProgram(
            programId: programId,
            sourceAccountId: result['accountId']!,
            amountUnits: result['amount']!,
          )
          .then((_) => const EarthApi().world());
      if (widget.action != null) {
        await widget.action!(submit);
      } else {
        await submit();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'House contribution submitted; Earth matching was applied within the program cap.')));
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : [];

  String _progress(Map<String, dynamic> row) {
    final progress = num.tryParse(
        '${row['progress_units'] ?? row['progress_points'] ?? ''}');
    final target =
        num.tryParse('${row['target_units'] ?? row['required_points'] ?? ''}');
    if (progress == null || target == null || target <= 0) {
      return 'Progress unavailable';
    }
    return '${progress.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}';
  }

  String? get _walletAccountId {
    final accounts = widget.personalFinanceData['accounts'];
    if (accounts is! List) return null;
    for (final raw in accounts) {
      if (raw is! Map) continue;
      final code = '${raw['asset_code'] ?? raw['assetCode']}'.toUpperCase();
      final type = '${raw['account_type'] ?? raw['accountType']}'.toUpperCase();
      if (code == 'CREDIT' && type == 'WALLET') {
        return raw['account_id']?.toString();
      }
    }
    return null;
  }

  String? get _walletBalance {
    final accounts = widget.personalFinanceData['accounts'];
    if (accounts is! List) return null;
    for (final raw in accounts) {
      if (raw is! Map) continue;
      final code = '${raw['asset_code'] ?? raw['assetCode']}'.toUpperCase();
      final type = '${raw['account_type'] ?? raw['accountType']}'.toUpperCase();
      if (code == 'CREDIT' && type == 'WALLET') {
        return (raw['balance_units'] ?? raw['balanceUnits'])?.toString();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          EarthEmptyState(
              message: 'Program data is unavailable. Please retry.',
              icon: Icons.sync_problem_outlined,
              action: TextButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('RETRY')))
        else if (_loading)
          const Center(child: CircularProgressIndicator())
        else ...[
          EarthSection(
            title: 'PLANETARY PROGRAMS',
            showSurface: true,
            trailing: IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh programs',
            ),
            child: _programs.isEmpty
                ? const EarthEmptyState(
                    message: 'No planetary programs are currently published.',
                    icon: Icons.public_outlined)
                : EarthDataList(
                    children: _programs.map((row) {
                    final capabilities = row['capabilities'] is Map
                        ? Map<String, dynamic>.from(row['capabilities'] as Map)
                        : const <String, dynamic>{};
                    return EarthDataRow(
                      title: row['name']?.toString() ??
                          row['id']?.toString() ??
                          'EARTH Program',
                      subtitle:
                          '${row['program_type'] ?? 'PROGRAM'} · ${row['status'] ?? 'UNKNOWN'} · progress ${_progress(row)}',
                      leading: Icon(Icons.public_outlined,
                          color: context.primaryColor),
                      trailing: capabilities['canContribute'] == true
                          ? TextButton(
                              onPressed: widget.busy || _walletAccountId == null
                                  ? null
                                  : () => _contribute('${row['id']}'),
                              child: const Text('FUND'))
                          : null,
                      badges: [
                        EarthBadge(
                            label: (row['status'] ?? 'UNKNOWN')
                                .toString()
                                .toUpperCase(),
                            variant: EarthBadgeVariant.primary)
                      ],
                    );
                  }).toList()),
          ),
        ],
      ],
    );
  }
}

class _CreateWorldProgramDialog extends StatefulWidget {
  const _CreateWorldProgramDialog();

  @override
  State<_CreateWorldProgramDialog> createState() =>
      _CreateWorldProgramDialogState();
}

class _ProgramContributionDialog extends StatefulWidget {
  final String walletAccountId;
  final String? walletBalance;
  const _ProgramContributionDialog({
    required this.walletAccountId,
    this.walletBalance,
  });
  @override
  State<_ProgramContributionDialog> createState() =>
      _ProgramContributionDialogState();
}

class _ProgramContributionDialogState
    extends State<_ProgramContributionDialog> {
  final amount = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('FUND EARTH PROGRAM'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Wallet balance: ${widget.walletBalance ?? 'unavailable'} C'),
          TextField(
              controller: amount,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Contribution (CREDIT)')),
          const SizedBox(height: 8),
          const Text(
              'Your House pays the contribution. Earth may add a capped matching amount; both legs are recorded in the ledger.',
              style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: widget.walletAccountId.isNotEmpty &&
                      RegExp(r'^\d+$').hasMatch(amount.text.trim())
                  ? () => Navigator.pop(context, {
                        'accountId': widget.walletAccountId,
                        'amount': amount.text.trim()
                      })
                  : null,
              child: const Text('CONTRIBUTE'))
        ],
      );
}

class _CreateWorldProgramDialogState extends State<_CreateWorldProgramDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();
  final _authorized = TextEditingController();
  final _matching = TextEditingController();
  final _deadline = TextEditingController();
  final _proposal = TextEditingController();
  String _type = 'TECHNOLOGY';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _target.dispose();
    _authorized.dispose();
    _matching.dispose();
    _deadline.dispose();
    _proposal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _name.text.trim().isNotEmpty &&
        _description.text.trim().isNotEmpty &&
        RegExp(r'^\d+$').hasMatch(_target.text.trim()) &&
        RegExp(r'^\d+$').hasMatch(_authorized.text.trim()) &&
        _proposal.text.trim().isNotEmpty;
    Widget field(TextEditingController controller, String label) => TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label));
    return AlertDialog(
      title: const Text('PROPOSE EARTH PROGRAM'),
      content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(_name, 'Program name'),
            field(_description, 'Description'),
            DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Program type'),
                items: const [
                  DropdownMenuItem(
                      value: 'TECHNOLOGY', child: Text('Technology')),
                  DropdownMenuItem(value: 'COMMONS', child: Text('Commons')),
                  DropdownMenuItem(
                      value: 'EMERGENCY', child: Text('Emergency')),
                ],
                onChanged: (value) => setState(() => _type = value ?? _type)),
            field(_target, 'Target CREDIT units'),
            field(_authorized, 'Authorized CREDIT units'),
            field(_matching, 'Earth matching cap (CREDIT units)'),
            field(_deadline, 'Funding deadline game day (optional)'),
            field(_proposal, 'Passed or active EARTH proposal ID'),
          ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: valid
                ? () => Navigator.pop(context, {
                      'programType': _type,
                      'name': _name.text.trim(),
                      'description': _description.text.trim(),
                      'targetUnits': _target.text.trim(),
                      'authorizedUnits': _authorized.text.trim(),
                      'matchingAuthorizedUnits': _matching.text.trim().isEmpty
                          ? '0'
                          : _matching.text.trim(),
                      'fundingDeadlineGameDay': _deadline.text.trim(),
                      'proposalId': _proposal.text.trim(),
                    })
                : null,
            child: const Text('SUBMIT'))
      ],
    );
  }
}
