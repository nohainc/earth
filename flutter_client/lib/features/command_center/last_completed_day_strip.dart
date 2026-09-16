import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_summary.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../../shared/widgets/format_helpers.dart';

/// A deliberately compact link to the completed cycle. The full narrative
/// belongs to Daily Briefing; Overview only exposes verified headline facts.
class LastCompletedDayStrip extends StatefulWidget {
  final ValueChanged<String>? onNavigate;
  const LastCompletedDayStrip({super.key, this.onNavigate});

  @override
  State<LastCompletedDayStrip> createState() => _LastCompletedDayStripState();
}

class _LastCompletedDayStripState extends State<LastCompletedDayStrip> {
  DailySummaryReport? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await const EarthApi().getDailySummary();
      if (!mounted) return;
      setState(() {
        _summary = response['ok'] == true
            ? DailySummaryReport.fromJson(Map<String, dynamic>.from(response))
            : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return EarthPanel(
      title: 'LAST COMPLETED DAY',
      infoDescription:
          'A compact pointer to the completed cycle. Open Daily Briefing for the full statement and detail.',
      width: double.infinity,
      child: _loading
          ? const LinearProgressIndicator()
          : summary == null
              ? Row(
                  children: [
                    Icon(Icons.history, color: context.mutedColor),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Completed-day data is unavailable.')),
                    TextButton(onPressed: _load, child: const Text('RETRY')),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.history, color: context.primaryColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 6,
                        children: [
                          Text('DAY ${summary.gameDay}',
                              style: context.widgetTitleStyle),
                          Text(
                              'NET ${formatWholeNumber(summary.financial.netProfit)} C',
                              style: context.widgetTitleStyle.copyWith(
                                  color: summary.financial.netProfit >= 0
                                      ? context.successColor
                                      : context.warningColor)),
                          Text(
                              '${summary.buildings.activeBuildings} active buildings',
                              style: context.widgetFooterStyle),
                          Text(
                              '${summary.governance.recentCivicEvents.length} civic updates',
                              style: context.widgetFooterStyle),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onNavigate == null
                          ? null
                          : () => widget.onNavigate!('briefing'),
                      child: const Text('OPEN BRIEFING'),
                    ),
                  ],
                ),
    );
  }
}
