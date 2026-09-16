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
    final net = r.financial.netProfit;

    return EarthMetricGrid(
      metrics: [
        EarthMetricTile(
          label: 'NET CREDIT FLOW',
          value: '${net >= 0 ? '+' : ''}${formatWholeNumber(net)} CR',
          subtitle:
              net >= 0 ? 'Positive completed day' : 'Negative completed day',
          icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
          accentColor: context.primaryColor,
        ),
        EarthMetricTile(
          label: 'INCOME',
          value: '+${formatWholeNumber(r.financial.totalIncome)} CR',
          subtitle: 'Recorded House receipts',
          icon: Icons.south_west_outlined,
          accentColor: context.successColor,
        ),
        EarthMetricTile(
          label: 'EXPENSES',
          value: '-${formatWholeNumber(r.financial.totalExpenses)} CR',
          subtitle: 'Recorded House outflows',
          icon: Icons.north_east_outlined,
          accentColor: context.warningColor,
        ),
      ],
    );
  }

  Widget _buildAllBriefingContent(DailySummaryReport r) {
    final financial = r.financial;

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
          label: 'Net Flow',
          value:
              '${financial.netProfit >= 0 ? '+' : ''}${formatWholeNumber(financial.netProfit)} CR',
          icon: financial.netProfit >= 0
              ? Icons.trending_up
              : Icons.trending_down,
          color: financial.netProfit >= 0
              ? context.successColor
              : context.warningColor,
        ),
        CockpitMetric(
          label: 'Income',
          value: '+${formatWholeNumber(financial.totalIncome)} CR',
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
            'High-priority operational, civic, and commercial directives recommended for your immediate review.',
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
          title: 'TERRITORY & GOVERNANCE CHANGES',
          showSurface: false,
          infoBulletPoints: const [
            'Public territory and governance events recorded during this day.',
          ],
          child: _buildCivicContent(r),
        ),
      ],
    );
  }

  Widget _buildCreditFlow(DailySummaryReport r) {
    final f = r.financial;
    final rows = [
      (
        'Income',
        '+${formatWholeNumber(f.totalIncome)} CR',
        context.successColor
      ),
      (
        'Expenses',
        '-${formatWholeNumber(f.totalExpenses)} CR',
        context.warningColor
      ),
      (
        'Taxes paid',
        '-${formatWholeNumber(f.civicTaxes)} CR',
        context.mutedColor
      ),
      (
        'Market sales',
        '+${formatWholeNumber(f.marketSales)} CR',
        context.successColor
      ),
      (
        'Market purchases',
        '-${formatWholeNumber(f.marketPurchases)} CR',
        context.mutedColor
      ),
    ];
    return EarthSection(
      title: 'CREDIT FLOW',
      showSurface: true,
      child: Column(
        children: rows
            .map((row) => EarthDataRow(
                  title: row.$1,
                  trailing: Text(row.$2,
                      style: context.widgetTitleStyle.copyWith(color: row.$3)),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildRecentChangesContent(DailySummaryReport r) {
    final events = [
      ...r.buildings.completed,
      ...r.buildings.upgraded,
      ...r.buildings.inactive,
      ...r.researchEvents,
      ...r.governanceEvents,
      ...r.houseEvents,
    ];
    if (events.isEmpty) {
      return const EarthEmptyState(
        message:
            'Everything operated normally. No material changes were recorded.',
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
                'Produced ${formatWholeNumber(resource.produced)} · Consumed ${formatWholeNumber(resource.consumed)}',
            leading: Icon(
                resource.net < 0 ? Icons.trending_down : Icons.trending_up,
                size: context.iconSize,
                color: resource.net < 0
                    ? context.warningColor
                    : context.successColor),
            trailing: Text(
                '${resource.net >= 0 ? '+' : ''}${formatWholeNumber(resource.net)}',
                style: context.widgetTitleStyle),
          )));
    }
    rows.addAll(r.marketMovements.map((movement) => EarthDataRow(
          title: movement.commodity,
          subtitle:
              'Bought ${formatWholeNumber(movement.purchases)} · Sold ${formatWholeNumber(movement.sales)} · Volume ${movement.volume24h}',
          leading: Icon(Icons.storefront_outlined,
              size: context.iconSize, color: context.primaryColor),
        )));
    return rows.isEmpty
        ? const EarthEmptyState(
            message: 'No resource or market activity was recorded.',
            icon: Icons.inventory_2_outlined)
        : EarthDataList(children: rows);
  }

  Widget _buildCivicContent(DailySummaryReport r) {
    if (r.governanceEvents.isEmpty) {
      return const EarthEmptyState(
          message: 'No territory or governance changes were recorded.',
          icon: Icons.account_balance_outlined);
    }
    return EarthDataList(
        children: r.governanceEvents
            .map((event) => EarthDataRow(
                  title: event.title,
                  subtitle: event.details.isEmpty ? event.type : event.details,
                  leading: Icon(Icons.account_balance_outlined,
                      size: context.iconSize, color: context.secondaryColor),
                ))
            .toList());
  }
}
