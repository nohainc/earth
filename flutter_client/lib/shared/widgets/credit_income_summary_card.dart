import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../design_system/design_system.dart';
import 'format_helpers.dart';

class CreditIncomeLineItem {
  final String label;
  final double value;

  const CreditIncomeLineItem(this.label, this.value);
}

/// Shared two-column daily cashflow statement for personal and municipal finance.
class CreditIncomeSummaryCard extends StatelessWidget {
  final List<CreditIncomeLineItem> grossItems;
  final List<CreditIncomeLineItem> deductionItems;
  final String grossTitle;
  final String netTitle;

  const CreditIncomeSummaryCard({
    super.key,
    required this.grossItems,
    required this.deductionItems,
    this.grossTitle = 'GROSS CREDIT INCOME',
    this.netTitle = 'NET CREDIT INCOME',
  });

  double get _gross => grossItems.fold(0, (total, item) => total + item.value);
  double get _deductions =>
      deductionItems.fold(0, (total, item) => total + item.value);
  double get _net => _gross - _deductions;

  String _amount(double value, {bool subtract = false}) =>
      '${subtract ? '-' : value > 0 ? '+' : value < 0 ? '-' : ''}${formatWholeNumber(value.abs())} C';

  Widget _header(BuildContext context, String title, double amount) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: context.widgetTitleStyle.copyWith(letterSpacing: .8)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined,
                size: 16, color: EarthResourceColors.credits),
            const SizedBox(width: 5),
            Text(_amount(amount),
                style: TextStyle(
                    color: amount < 0
                        ? Colors.redAccent
                        : amount > 0
                            ? Colors.tealAccent
                            : context.mutedColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ]),
        ],
      );

  Widget _line(BuildContext context, CreditIncomeLineItem item,
          {bool subtract = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          Expanded(
              child: Text(item.label,
                  style: context.bodyStyle.copyWith(
                      color: context.mutedColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600))),
          Text(_amount(item.value, subtract: subtract),
              style: context.bodyStyle.copyWith(
                  color: subtract ? Colors.redAccent : context.successColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    Widget grossColumn() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(context, grossTitle, _gross),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.subtleBorderColor),
          const SizedBox(height: 12),
          ...grossItems.map((item) => _line(context, item)),
        ]);
    Widget netColumn() =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _header(context, netTitle, _net),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.subtleBorderColor),
          const SizedBox(height: 12),
          ...deductionItems.map((item) => _line(context, item, subtract: true)),
        ]);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                grossColumn(),
                const SizedBox(height: 20),
                Divider(height: 1, color: context.subtleBorderColor),
                const SizedBox(height: 20),
                netColumn(),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: grossColumn()),
          const SizedBox(width: 24),
          Container(width: 1, height: 110, color: context.subtleBorderColor),
          const SizedBox(width: 24),
          Expanded(child: netColumn()),
        ]);
      }),
    );
  }
}
