import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

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

  Future<void> _contribute(String programId) async {
    final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => _ProgramContributionDialog(
              walletBalance: _walletBalance,
            ));
    if (result == null || !mounted) return;
    try {
      Future<EarthState> submit() => const EarthApi()
          .contributeToGlobalProgram(
            programId: programId,
            amountCredit: result['amount']!,
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
    final progress = row['progress_units'];
    final target = row['target_units'];
    if (progress == null || target == null) {
      return 'Progress unavailable';
    }
    return '${formatCreditUnits(progress)} / ${formatCreditUnits(target)}';
  }

  String? get _walletBalance {
    final wallet = widget.personalFinanceData['wallet'];
    return wallet is Map ? wallet['balanceUnits']?.toString() : null;
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
                              onPressed: widget.busy
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

class _ProgramContributionDialog extends StatefulWidget {
  final String? walletBalance;
  const _ProgramContributionDialog({
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
          Text('Wallet balance: ${formatCreditUnits(widget.walletBalance)}'),
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
              onPressed: RegExp(r'^\d+(?:\.\d{1,2})?$')
                      .hasMatch(amount.text.trim())
                  ? () => Navigator.pop(context, {'amount': amount.text.trim()})
                  : null,
              child: const Text('CONTRIBUTE'))
        ],
      );
}
