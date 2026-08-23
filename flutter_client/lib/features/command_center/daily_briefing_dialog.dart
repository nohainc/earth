import 'package:flutter/material.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/format_helpers.dart';

void showDailyBriefingDialog(
  BuildContext context, {
  required EarthApi api,
  required void Function(String section) onNavigate,
}) {
  showDialog(
    context: context,
    builder: (context) => DailyBriefingDialog(api: api, onNavigate: onNavigate),
  );
}

class DailyBriefingDialog extends StatefulWidget {
  final EarthApi api;
  final void Function(String section) onNavigate;
  final bool isPageMode;

  const DailyBriefingDialog({
    super.key,
    required this.api,
    required this.onNavigate,
    this.isPageMode = false,
  });

  @override
  State<DailyBriefingDialog> createState() => _DailyBriefingDialogState();
}

class _DailyBriefingDialogState extends State<DailyBriefingDialog> {
  bool _loading = true;
  String? _error;
  DailyBriefingReport? _report;

  @override
  void initState() {
    super.initState();
    _loadBriefing();
  }

  Future<void> _loadBriefing() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.getDailyBriefing();
      final isOk = res['ok'] == true || res['ok'] == 'true';
      if (isOk) {
        if (mounted) {
          setState(() {
            _report = DailyBriefingReport.fromJson(Map<String, dynamic>.from(res));
            _loading = false;
          });
          EarthAudioEngine.instance.playChime();
        }
      } else {
        if (mounted) {
          setState(() {
            _error = res['error']?.toString() ?? 'Failed to load executive briefing';
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
          padding: EdgeInsets.all(context.tokens.number('pageTopics.cardPadding', 16)),
          child: _buildBriefingBody(),
        ),
      ),
    );
  }

  Widget _buildBriefingBody() {
    if (_loading) {
      return SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(color: context.primaryColor)),
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

  Widget _buildHeroDeltaBanner(DailyBriefingReport r) {
    final delta = r.netWealthDelta.delta;
    final isPos = delta >= 0;

    return EarthMetricGrid(
      metrics: [
        EarthMetricTile(
          label: 'NET WORTH',
          value: '${r.netWealthDelta.current.toStringAsFixed(2)} CR',
          subtitle: 'Current sovereign valuation',
          icon: Icons.insights_outlined,
          accentColor: context.primaryColor,
        ),
        EarthMetricTile(
          label: 'NET CHANGE',
          value: '${isPos ? '+' : ''}${delta.toStringAsFixed(2)} CR',
          subtitle: '${isPos ? '+' : ''}${r.netWealthDelta.deltaPct.toStringAsFixed(2)}% since previous day close',
          icon: isPos ? Icons.trending_up : Icons.trending_down,
          accentColor: isPos ? context.successColor : context.errorColor,
        ),
        EarthMetricTile(
          label: 'NET CASHFLOW',
          value: '${r.cashflow.netProfit >= 0 ? '+' : ''}${r.cashflow.netProfit.toStringAsFixed(2)} CR/day',
          subtitle: r.cashflow.netProfit >= 0 ? 'Operating surplus' : 'Operating deficit',
          icon: Icons.account_balance_wallet_outlined,
          accentColor: r.cashflow.netProfit >= 0 ? context.successColor : context.warningColor,
        ),
      ],
    );
  }

  Widget _buildAllBriefingContent(DailyBriefingReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EarthSection(
          title: 'SINCE YOUR LAST VISIT',
          showSurface: false,
          infoBulletPoints: const [
            'The financial result compares your current position with the previous game day.',
            'The change list highlights business, contract, civic, and household effects that may require a decision.',
            'Open Finance or Activity for the complete ledger and event history.',
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroDeltaBanner(r),
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
          title: 'CURRENT OPERATIONS',
          showSurface: false,
          infoBulletPoints: const [
            'Active enterprise summary, machine capacity, output volume, and pending commercial contracts.',
          ],
          child: _buildIndustryContent(r),
        ),
        SizedBox(height: context.spacingTopic),
        EarthSection(
          title: 'CITY & CIVIC EFFECTS',
          showSurface: false,
          infoBulletPoints: const [
            'Current residency jurisdiction, municipal taxation, and recent civic legislative resolutions.',
          ],
          child: _buildCivicContent(r),
        ),
      ],
    );
  }

  Widget _buildRecentChangesContent(DailyBriefingReport r) {
    final changes = <(String, String, IconData, Color)>[
      (
        'Financial result',
        '${r.cashflow.netProfit >= 0 ? '+' : ''}${formatWholeNumber(r.cashflow.netProfit)} CR net cashflow',
        r.cashflow.netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
        r.cashflow.netProfit >= 0 ? context.successColor : context.errorColor,
      ),
      (
        'Operations',
        '${r.businessSummary.activeBusinesses} businesses · ${r.businessSummary.activeMachines} machines · ${r.businessSummary.pendingContractsCount} pending contracts',
        Icons.business_center_outlined,
        context.primaryColor,
      ),
      if (r.civicSummary.recentCivicEvents.isNotEmpty)
        (
          'City and civic life',
          r.civicSummary.recentCivicEvents.first,
          Icons.location_city_outlined,
          context.secondaryColor,
        ),
    ];

    return EarthDataList(
      children: changes.indexed.map((indexed) {
        final change = indexed.$2;
        final isLast = indexed.$1 == changes.length - 1;

        return EarthDataRow(
          title: change.$1,
          subtitle: change.$2,
          leading: Icon(change.$3, size: context.iconSize, color: change.$4),
          showDivider: !isLast,
        );
      }).toList(),
    );
  }

  Widget _buildDirectivesContent(DailyBriefingReport r) {
    if (r.recommendedDirectives.isEmpty) {
      return const EarthEmptyState(
        message: 'No directives require attention.',
        icon: Icons.check_circle_outline,
      );
    }

    return EarthDataList(
      children: r.recommendedDirectives.indexed.map((indexed) {
        final d = indexed.$2;
        final isLast = indexed.$1 == r.recommendedDirectives.length - 1;

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
            variant: d.urgency == 'high' ? EarthButtonVariant.danger : EarthButtonVariant.primary,
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

  Widget _buildIndustryContent(DailyBriefingReport r) {
    return EarthMetricGrid(
      metrics: [
        EarthMetricTile(
          label: 'ACTIVE BUSINESSES',
          value: '${r.businessSummary.activeBusinesses}',
          icon: Icons.storefront_outlined,
          accentColor: context.primaryColor,
        ),
        EarthMetricTile(
          label: 'DAILY OUTPUT',
          value: '${r.businessSummary.totalDailyOutput}',
          icon: Icons.precision_manufacturing_outlined,
          accentColor: context.successColor,
        ),
        EarthMetricTile(
          label: 'ACTIVE MACHINES',
          value: '${r.businessSummary.activeMachines}',
          icon: Icons.settings_suggest_outlined,
          accentColor: context.primaryColor,
        ),
        EarthMetricTile(
          label: 'DEGRADED MACHINES',
          value: '${r.businessSummary.degradedMachinesCount}',
          icon: Icons.warning_amber_outlined,
          accentColor: r.businessSummary.degradedMachinesCount > 0 ? context.errorColor : context.successColor,
        ),
        EarthMetricTile(
          label: 'PENDING CONTRACTS',
          value: '${r.businessSummary.pendingContractsCount}',
          icon: Icons.assignment_outlined,
          accentColor: r.businessSummary.pendingContractsCount > 0 ? context.warningColor : context.mutedColor,
        ),
      ],
    );
  }

  Widget _buildCivicContent(DailyBriefingReport r) {
    final c = r.civicSummary;

    return Container(
      padding: EdgeInsets.all(context.cardPadding),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusCard),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CIVIC RESIDENCY: ${c.cityResidency.toUpperCase()}',
            style: context.widgetTitleStyle.copyWith(color: context.primaryColor),
          ),
          const SizedBox(height: 6),
          Text(
            'Municipal Tax Rate: ${c.cityTaxRatePct}% • Active Senate Bills: ${c.activeProposals}',
            style: context.widgetFooterStyle,
          ),
          if (c.recentCivicEvents.isNotEmpty) ...[
            SizedBox(height: context.spacingTitleOffset),
            Text('RECENT CIVIC RESOLUTIONS', style: context.captionStyle),
            const SizedBox(height: 6),
            ...c.recentCivicEvents.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $e', style: context.widgetFooterStyle),
                )),
          ],
        ],
      ),
    );
  }
}
