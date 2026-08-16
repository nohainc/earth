import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/earth_state.dart';
import '../../shared/widgets/earth_primitives.dart';

class PersonalFinancePanel extends StatefulWidget {
  final EarthState state;
  final bool busy;
  final Map<String, dynamic> personalFinanceData;
  final Future<void> Function(Future<EarthState> Function()) action;
  final Key? panelKey;

  const PersonalFinancePanel({
    super.key,
    this.panelKey,
    required this.state,
    required this.busy,
    this.personalFinanceData = const {},
    required this.action,
  });

  @override
  State<PersonalFinancePanel> createState() => _PersonalFinancePanelState();
}

class _PersonalFinancePanelState extends State<PersonalFinancePanel> {
  String? _localStatusMessage;
  bool _localBusy = false;

  Future<void> _settleTax(BuildContext context) async {
    final controller = TextEditingController(text: '1000');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settle Tax Obligations'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tax calculations are performed by the canonical authority. Settle assessed obligations now:',
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Taxable Assessment Base (C)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CONFIRM SETTLEMENT'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final val = double.tryParse(controller.text.trim()) ?? 1000.0;
      setState(() => _localBusy = true);
      try {
        await widget.action(() => const EarthApi().settlePersonalTax(val));
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Tax settled successfully through central authority.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Settlement failed: $e';
          });
        }
      }
    }
  }

  Future<void> _declareInsolvency(BuildContext context) async {
    final reasonController = TextEditingController(text: 'Liquidity deficit restructuring');
    final otpController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Declare Personal Insolvency'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restructuring liquidates non-protected assets. 100 Credit minimum reserve and your basic service robot are permanently protected.',
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Restructuring Reason',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: otpController,
              decoration: const InputDecoration(
                labelText: 'MFA Code (if enabled)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('EXECUTE RESTRUCTURING'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _localBusy = true);
      try {
        await widget.action(() => const EarthApi().declareInsolvencyRestructuring(
          reason: reasonController.text,
          otp: otpController.text.isEmpty ? null : otpController.text,
        ));
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Insolvency restructuring processed and confirmed.';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _localBusy = false;
            _localStatusMessage = 'Restructuring request failed: $e';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.personalFinanceData;
    final account = data['account'] as Map<String, dynamic>?;
    final finState = data['state'] as Map<String, dynamic>?;
    final protected = data['protectedMinimum'] as Map<String, dynamic>?;

    final balance = widget.state.human['credits'] ?? account?['balance'] ?? 0;
    final income = finState?['income'] ?? 760;
    final expenses = finState?['expenses'] ?? 240;
    final taxObligations = finState?['tax_obligations'] ?? 48;
    final liquidityStatus = (finState?['liquidity_status'] ?? (balance is num && balance > 500 ? 'healthy' : 'tight')).toString().toUpperCase();
    final insolvencyStatus = (finState?['insolvency_status'] ?? finState?['status'] ?? 'SOLVENT').toString().toUpperCase();
    final protectedCredits = protected?['credits'] ?? 100;

    final isBusy = widget.busy || _localBusy;

    return EarthPanel(
      key: widget.panelKey,
      title: 'PERSONAL FINANCE & TAXATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CREDIT BALANCE', style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text('$balance C', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cyanAccentColor)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('LIQUIDITY STATUS', style: TextStyle(color: mutedColor, fontSize: 10, letterSpacing: 1)),
                    const SizedBox(height: 2),
                    Text(liquidityStatus, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: liquidityStatus == 'HEALTHY' ? cyanAccentColor : Colors.orangeAccent)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white10),
          const SizedBox(height: 12),
          Text('Income stream: $income C / day · Estimated baseline expenses: $expenses C / day', style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text('Assessed tax obligations: $taxObligations C · Solvency status: $insolvencyStatus', style: const TextStyle(fontSize: 11, color: mutedColor)),
          const SizedBox(height: 4),
          Text('Protected minimum reserve: $protectedCredits C (Basic Service Robot protected)', style: const TextStyle(fontSize: 10, color: mutedColor)),
          if (_localStatusMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _localStatusMessage!,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: isBusy ? null : () => _settleTax(context),
                child: const Text('SETTLE TAXES'),
              ),
              OutlinedButton(
                onPressed: isBusy ? null : () => _declareInsolvency(context),
                child: const Text('INSOLVENCY RESTRUCTURING'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
