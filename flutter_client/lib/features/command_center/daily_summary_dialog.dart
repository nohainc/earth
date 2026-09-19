import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_summary.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/earth_page_cockpit.dart';
import '../../shared/widgets/format_helpers.dart';

void showDailySummaryDialog(
  BuildContext context, {
  required EarthApi api,
  required void Function(String section) onNavigate,
}) {
  showDialog(
    context: context,
    builder: (context) => DailySummaryDialog(api: api, onNavigate: onNavigate),
  );
}

class DailySummaryDialog extends StatefulWidget {
  final EarthApi api;
  final void Function(String section) onNavigate;
  final bool isPageMode;

  const DailySummaryDialog({
    super.key,
    required this.api,
    required this.onNavigate,
    this.isPageMode = false,
  });

  @override
  State<DailySummaryDialog> createState() => _DailySummaryDialogState();
}

class _DailySummaryDialogState extends State<DailySummaryDialog> {
  static int? _lastChimedBriefingDay;
  bool _loading = true;
  String? _error;
  DailySummaryReport? _report;

  @override
  void initState() {
    super.initState();
    _loadBriefing();
  }

  Future<void> _loadBriefing([int? day]) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.getDailySummary(day: day);
      final isOk = res['ok'] == true || res['ok'] == 'true';
      if (isOk) {
        if (mounted) {
          setState(() {
            _report =
                DailySummaryReport.fromJson(Map<String, dynamic>.from(res));
            _loading = false;
          });
          if (_lastChimedBriefingDay == null ||
              _report!.gameDay > _lastChimedBriefingDay!) {
            _lastChimedBriefingDay = _report!.gameDay;
            EarthAudioEngine.instance.playChime();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _error =
                res['error']?.toString() ?? 'Failed to load executive briefing';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPageMode) {
      return _buildBriefingBody();
    }

    return Dialog(
      backgroundColor: context.panelColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radiusPanel),
        side: BorderSide(color: context.primaryColor.withValues(alpha: .35)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 740),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
              context.tokens.number('pageTopics.cardPadding', 16)),
          child: _buildBriefingBody(),
        ),
      ),
    );
  }

  Widget _buildBriefingBody() {
    if (_loading) {
      return SizedBox(
        height: 220,
        child: Center(
            child: CircularProgressIndicator(color: context.primaryColor)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: context.errorColor, size: 36),
              const SizedBox(height: 10),
              Text(_error!, style: context.widgetFooterStyle),
              SizedBox(height: context.spacingInline),
              EarthButton(
                label: 'RETRY BRIEFING',
                variant: EarthButtonVariant.primary,
                onPressed: _loadBriefing,
              ),
            ],
          ),
        ),
      );
    }
    return _report == null
        ? const SizedBox.shrink()
        : _buildAllBriefingContent(_report!);
  }

  Widget _buildHeroDeltaBanner(DailySummaryReport r) {
    final netUnits = r.financial.netCashflowUnits;
    final isNegative = netUnits.startsWith('-');

    return EarthMetricGrid(
      metrics: [
        EarthMetricTile(
          label: 'NET CASHFLOW',
          value: '${isNegative ? '' : '+'}${formatCreditUnits(netUnits)}',
          subtitle:
              !isNegative ? 'Positive completed day' : 'Negative completed day',
          icon: !isNegative ? Icons.trending_up : Icons.trending_down,
          accentColor: context.primaryColor,
        ),
        EarthMetricTile(
          label: 'INCOME',
          value: '+${formatCreditUnits(r.financial.incomeUnits)}',
          subtitle: 'Recorded House receipts',
          icon: Icons.south_west_outlined,
          accentColor: context.successColor,
        ),
        EarthMetricTile(
          label: 'EXPENSES',
          value: '-${formatCreditUnits(r.financial.expensesUnits)}',
          subtitle: 'Recorded House outflows',
          icon: Icons.north_east_outlined,
          accentColor: context.warningColor,
        ),
      ],
    );
  }

  Widget _buildAllBriefingContent(DailySummaryReport r) {
    final financial = r.financial;
    final isNegative = financial.netCashflowUnits.startsWith('-');

    final cockpit = EarthPageCockpit(
      status: 'DAY ${r.gameDay} COMPLETE',
      tag: 'DAILY BRIEFING',
      statusColor: context.primaryColor,
      infoTitle: 'ABOUT THIS BRIEFING',
      infoDescription:
          'This report covers the last completed game day for your House. It separates financial results, resource changes, important events, and actions that may need your attention.',
      title: 'DAILY BRIEFING',
      subtitle:
          'Your House results, changes, and priorities from the completed day',
      metrics: [
        CockpitMetric(
          label: 'Net Cashflow',
          value:
              '${isNegative ? '' : '+'}${formatCreditUnits(financial.netCashflowUnits)}',
          icon: !isNegative
              ? Icons.trending_up
              : Icons.trending_down,
          color: !isNegative
              ? context.successColor
              : context.warningColor,
        ),
        CockpitMetric(
          label: 'Income',
          value: '+${formatCreditUnits(financial.incomeUnits)}',
          icon: Icons.south_west_outlined,
          color: context.successColor,
        ),
        CockpitMetric(
          label: 'Priorities',
          value: '${r.highlights.length}',
          icon: Icons.bolt_outlined,
          color: r.highlights.isNotEmpty
              ? context.secondaryColor
              : context.mutedColor,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        cockpit,
        if (r.currentGameDay > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EarthButton(
                label: '‹ DAY ${r.gameDay - 1}',
                onPressed:
                    r.gameDay > 0 ? () => _loadBriefing(r.gameDay - 1) : null,
              ),
              const SizedBox(width: 12),
              Text('DAY ${r.gameDay}', style: context.widgetTitleStyle),
              const SizedBox(width: 12),
              EarthButton(
                label: 'DAY ${r.gameDay + 1} ›',
                onPressed: r.gameDay + 1 < r.currentGameDay
                    ? () => _loadBriefing(r.gameDay + 1)
                    : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        _buildStatementStatus(r.statementMetadata),
        SizedBox(height: context.spacingControl),
        EarthSection(
          title: 'DAY ${r.gameDay} RESULTS',
          showSurface: false,
          infoBulletPoints: const [
            'This report covers one completed game day, not time since your last visit.',
            'Routine facts are shown under What Changed; only actionable issues appear under Needs Attention.',
            'Open Finance or Market for transaction-level detail.',
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroDeltaBanner(r),
              SizedBox(height: context.spacingControl),
              _buildCreditFlow(r),
              SizedBox(height: context.spacingTopic),
              Text('WHAT CHANGED', style: context.widgetTitleStyle),
              SizedBox(height: context.spacingControl),
              _buildRecentChangesContent(r),
            ],
          ),
        ),
        SizedBox(height: context.spacingTopic),
        EarthSection(
          title: 'WHAT REQUIRES ATTENTION',
          showSurface: false,
          infoBulletPoints: const [
            'High-priority operational, governance, and commercial directives recommended for your immediate review.',
          ],
          child: _buildDirectivesContent(r),
        ),
        SizedBox(height: context.spacingTopic),
        EarthSection(
          title: 'RESOURCES & MARKET',
          showSurface: false,
          infoBulletPoints: const [
            'Production, consumption, and market activity recorded during this day.',
          ],
          child: _buildResourcesContent(r),
        ),
        SizedBox(height: context.spacingTopic),
        EarthSection(
          title: 'GOVERNANCE EVENTS',
          showSurface: false,
          infoBulletPoints: const [
            'V5 Earth and Corporation governance events recorded during this day.',
          ],
          child: _buildGovernanceContent(r),
        ),
      ],
    );
  }

  Widget _buildStatementStatus(DailyStatementMetadata metadata) {
    final finalized = metadata.immutable && metadata.finalizedAt != null;
    return EarthDataRow(
      title: finalized ? 'FINALIZED DAY ${metadata.gameDay}' : 'STATEMENT STATUS',
      subtitle: finalized
          ? 'Immutable settlement record · Rules ${metadata.rulesVersion ?? 'unversioned'}'
          : 'Settlement status: ${metadata.settlementStatus.toUpperCase()}',
      trailing: Icon(
        finalized ? Icons.lock_outline : Icons.sync_problem_outlined,
        color: finalized ? context.successColor : context.warningColor,
        size: context.iconSize,
      ),
    );
  }

  Widget _buildCreditFlow(DailySummaryReport r) {
    final f = r.financial;
    String labelFor(String category) => switch (category) {
          'BUILDING_OPERATIONS' => 'Building operations',
          'CONSTRUCTION' => 'Construction',
          'RESEARCH' => 'Research',
          'CAPACITY' => 'Capacity',
          'MARKET' => 'Market',
          'TAX' => 'Tax',
          _ => 'Other',
        };
    final rows = <Widget>[
      EarthDataRow(
        title: 'Income',
        trailing: Text('+${formatCreditUnits(f.incomeUnits)}',
            style: context.widgetTitleStyle
                .copyWith(color: context.successColor)),
      ),
      EarthDataRow(
        title: 'Expenses',
        trailing: Text('-${formatCreditUnits(f.expensesUnits)}',
            style: context.widgetTitleStyle
                .copyWith(color: context.warningColor)),
      ),
      EarthDataRow(
        title: 'Net',
        trailing: Text(
          '${f.netCashflowUnits.startsWith('-') ? '' : '+'}${formatCreditUnits(f.netCashflowUnits)}',
          style: context.widgetTitleStyle.copyWith(
              color: f.netCashflowUnits.startsWith('-')
                  ? context.warningColor
                  : context.primaryColor),
        ),
      ),
    ];
    for (final breakdown in f.cashflowBreakdown) {
      final inflow = formatCreditUnits(breakdown.inflowUnits);
      final outflow = formatCreditUnits(breakdown.outflowUnits);
      final hasInflow = breakdown.inflowUnits != '0';
      final hasOutflow = breakdown.outflowUnits != '0';
      final value = hasInflow && hasOutflow
          ? '+$inflow / -$outflow'
          : hasInflow
              ? '+$inflow'
              : '-$outflow';
      rows.add(EarthDataRow(
        title: labelFor(breakdown.category),
        subtitle: 'Included in Income / Expenses',
        trailing: Text(value, style: context.bodyStyle),
      ));
    }
    return EarthSection(
      title: 'CREDIT FLOW',
      showSurface: true,
      child: Column(children: rows),
    );
  }

  Widget _buildRecentChangesContent(DailySummaryReport r) {
    final events = r.timeline.isNotEmpty
        ? r.timeline
        : [
            ...r.buildings.completed,
            ...r.buildings.upgraded,
            ...r.buildings.inactive,
            ...r.researchEvents,
            ...r.governance.events,
            ...r.houseEvents,
          ];
    if (events.isEmpty) {
      return const EarthEmptyState(
        message: 'No material events were recorded.',
        icon: Icons.check_circle_outline,
      );
    }

    return EarthDataList(
      children: events.indexed.map((indexed) {
        final event = indexed.$2;
        final isLast = indexed.$1 == events.length - 1;
        final isProblem =
            event.type.contains('INACTIVE') || event.type.contains('FAILED');

        return EarthDataRow(
          title: event.title,
          subtitle: event.details.isEmpty ? event.type : event.details,
          leading: Icon(
            isProblem
                ? Icons.warning_amber_outlined
                : Icons.check_circle_outline,
            size: context.iconSize,
            color: isProblem ? context.warningColor : context.successColor,
          ),
          showDivider: !isLast,
        );
      }).toList(),
    );
  }

  Widget _buildDirectivesContent(DailySummaryReport r) {
    if (r.highlights.isEmpty) {
      return const EarthEmptyState(
        message: 'No directives require attention.',
        icon: Icons.check_circle_outline,
      );
    }

    return EarthDataList(
      children: r.highlights.indexed.map((indexed) {
        final d = indexed.$2;
        final isLast = indexed.$1 == r.highlights.length - 1;

        EarthBadgeVariant badgeVariant = EarthBadgeVariant.primary;
        if (d.urgency == 'high') {
          badgeVariant = EarthBadgeVariant.warning;
        } else if (d.urgency == 'medium') {
          badgeVariant = EarthBadgeVariant.warning;
        }

        return EarthDataRow(
          title: d.title,
          subtitle: d.reason,
          badges: [
            EarthBadge(label: d.urgency.toUpperCase(), variant: badgeVariant),
          ],
          trailing: EarthButton(
            key: Key('btn-directive-${d.id}'),
            label: d.actionLabel,
            icon: Icons.launch,
            variant: d.urgency == 'high'
                ? EarthButtonVariant.danger
                : EarthButtonVariant.primary,
            onPressed: () {
              EarthAudioEngine.instance.playClick();
              if (!widget.isPageMode) Navigator.of(context).pop();
              widget.onNavigate(d.targetSection);
            },
          ),
          showDivider: !isLast,
        );
      }).toList(),
    );
  }

  Widget _buildResourcesContent(DailySummaryReport r) {
    final rows = <Widget>[];
    if (r.resources.isNotEmpty) {
      rows.addAll(r.resources.map((resource) => EarthDataRow(
            title: resource.resource,
            subtitle:
                'Produced ${formatAssetQuantity(resource.resource, resource.producedUnits)} · Consumed ${formatAssetQuantity(resource.resource, resource.consumedUnits)}',
            leading: Icon(
                resource.isShortfall ? Icons.trending_down : Icons.trending_up,
                size: context.iconSize,
                color: resource.isShortfall
                    ? context.warningColor
                    : context.successColor),
            trailing: Text(
                '${resource.isShortfall ? '' : '+'}${formatAssetQuantity(resource.resource, resource.netUnits)}',
                style: context.widgetTitleStyle),
          )));
    }
    rows.addAll(r.marketActivity.map((activity) => EarthDataRow(
          title: activity.commodity,
          subtitle:
              'Bought ${formatAssetQuantity(activity.commodity, activity.boughtUnits)} · Sold ${formatAssetQuantity(activity.commodity, activity.soldUnits)} · Volume ${formatAssetQuantity(activity.commodity, activity.volumeUnits)} · Spent ${formatCreditUnits(activity.creditSpentUnits)} · Received ${formatCreditUnits(activity.creditReceivedUnits)}',
          leading: Icon(Icons.storefront_outlined,
              size: context.iconSize, color: context.primaryColor),
        )));
    return rows.isEmpty
        ? const EarthEmptyState(
            message: 'No resource or market activity was recorded.',
            icon: Icons.inventory_2_outlined)
        : EarthDataList(children: rows);
  }

  Widget _buildGovernanceContent(DailySummaryReport r) {
    if (r.governance.events.isEmpty) {
      return const EarthEmptyState(
        message: 'No governance events were recorded.',
          icon: Icons.account_balance_outlined);
    }
    return EarthDataList(
        children: r.governance.events
            .map((event) => EarthDataRow(
                  title: event.title,
                  subtitle: event.details.isEmpty ? event.type : event.details,
                  leading: Icon(Icons.account_balance_outlined,
                      size: context.iconSize, color: context.secondaryColor),
                ))
            .toList());
  }
}
