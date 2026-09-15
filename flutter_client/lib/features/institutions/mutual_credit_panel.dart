import 'package:flutter/material.dart';
import '../../shared/design_system/design_system.dart';

class MutualCreditPanel extends StatelessWidget {
  final Map<String, dynamic> data;

  const MutualCreditPanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final networks = (data['networks'] as List<dynamic>?) ?? const [];
    return EarthSection(
      title: 'MUTUAL CREDIT NETWORKS',
      showSurface: false,
      infoBulletPoints: const [
        'Experimental Organization-scoped claims are separate from global CREDIT.',
        'Every member has a governed limit; transfers cannot create an unbounded position.',
        'Network health exposes reconciliation and default risk before you commit.',
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OPTIONAL CLEARING NETWORKS', style: context.topicTitleStyle),
          const SizedBox(height: 6),
          Text(
            'These instruments are disabled unless EARTH enables the experiment. They are not spendable CREDIT and never change your global wallet.',
            style: context.widgetFooterStyle,
          ),
          const SizedBox(height: 14),
          if (networks.isEmpty)
            Text('No active mutual-credit networks are available.',
                style: context.widgetFooterStyle)
          else
            ...networks.whereType<Map>().map((network) => Card(
                  child: ListTile(
                    title: Text('${network['name'] ?? 'Network'} · ${network['unit_code'] ?? ''}'),
                    subtitle: Text(
                        '${network['member_count'] ?? 0} members · ${network['status'] ?? 'ACTIVE'}\nYour position: ${network['my_position_units'] ?? '0'}'),
                    isThreeLine: true,
                    trailing: Text('LIMIT\n${network['my_credit_limit_units'] ?? '—'}',
                        textAlign: TextAlign.right),
                  ),
                )),
        ],
      ),
    );
  }
}
