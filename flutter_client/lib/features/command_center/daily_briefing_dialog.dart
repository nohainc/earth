import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/widgets/earth_primitives.dart';

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
            _report =
                DailyBriefingReport.fromJson(Map<String, dynamic>.from(res));
            _loading = false;
          });
          EarthAudioEngine.instance.playChime();
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
    final panel = EarthPanel(
      height: widget.isPageMode ? null : 740,
      title: 'EXECUTIVE INTELLIGENCE BRIEFING',
      showSurface: false,
      showTitle: false,
      contentPadding: EdgeInsets.zero,
      infoDescription:
          '• Review the most important changes since the previous simulation cycle.\n\n• Compare cashflow, market movements, industry operations, and civic developments.\n\n• Use recommended directives to move directly to the relevant game system.',
      child: widget.isPageMode
          ? _buildBriefingBody()
          : SizedBox(
              height: 620,
              child: SingleChildScrollView(child: _buildBriefingBody()),
            ),
    );

    if (widget.isPageMode) return panel;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(width: 880, height: 740, child: panel),
    );
  }

  Widget _buildBriefingBody() {
    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Color(0xFFFF5252), size: 36),
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadBriefing,
                child: const Text('RETRY BRIEFING'),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: violetColor.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: violetColor.withValues(alpha: .4)),
              ),
              child: const Icon(Icons.insights_outlined,
                  size: 22, color: cyanAccentColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NET WORTH',
                      style: TextStyle(
                          color: mutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 3),
                  Text(
                    '${r.netWealthDelta.current.toStringAsFixed(2)} CR',
                    style: const TextStyle(
                        color: inkColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 42,
              margin: const EdgeInsets.symmetric(horizontal: 14),
              color: EarthColors.borderSubtle,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('NET CHANGE',
                      style: TextStyle(
                          color: mutedColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1)),
                  const SizedBox(height: 3),
                  Text('${isPos ? '+' : ''}${delta.toStringAsFixed(2)} CR',
                      style: TextStyle(
                          color: isPos
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF5252),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.4)),
                  Text(
                      '${isPos ? '+' : ''}${r.netWealthDelta.deltaPct.toStringAsFixed(2)}% since previous day close',
                      style: const TextStyle(color: mutedColor, fontSize: 9.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'PREVIOUS GAME-DAY',
          textAlign: TextAlign.left,
          style: TextStyle(
            color: mutedColor,
            fontSize: 8.5,
            fontWeight: FontWeight.w600,
            letterSpacing: .7,
          ),
        ),
        const SizedBox(height: 14),
        _cashflowResult(r.cashflow),
        const SizedBox(height: 14),
        _buildCashflowContent(r),
      ],
    );
  }

  Widget _cashflowResult(FinancialCashflowDelta cf) {
    final isPositive = cf.netProfit >= 0;
    final color = isPositive
        ? EarthThemeController.instance.primaryAccent
        : const Color(0xFFFF5252);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(isPositive ? Icons.trending_up : Icons.trending_down,
              color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NET CASHFLOW',
                    style: TextStyle(
                        color: mutedColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8)),
                const SizedBox(height: 3),
                Text(isPositive ? 'OPERATING SURPLUS' : 'OPERATING DEFICIT',
                    style: const TextStyle(color: inkColor, fontSize: 11)),
              ],
            ),
          ),
          Text('${isPositive ? '+' : ''}${cf.netProfit.toStringAsFixed(2)} CR',
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildAllBriefingContent(DailyBriefingReport r) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 1000;
        final left = <Widget>[
          _buildSectionLabel('STRATEGIC DIRECTIVES REQUIRING ATTENTION'),
          _buildDirectivesContent(r),
        ];
        final right = <Widget>[
          _buildSectionLabel(
            'COMMODITY SPOT AUCTION MOVEMENTS',
            topOffset: wide ? 0 : 34,
          ),
          _buildMarketsContent(r),
          _buildSectionLabel('INDUSTRY OPERATIONS'),
          _buildIndustryContent(r),
          _buildSectionLabel('CIVIC & INTELLIGENCE'),
          _buildCivicContent(r),
        ];
        final sections = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBriefingHeading(context),
                        _buildHeroDeltaBanner(r),
                        ...left,
                      ],
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: right,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...left, ...right],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              sections
            else ...[
              _buildBriefingHeading(context),
              _buildHeroDeltaBanner(r),
              ...left,
              ...right,
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildBriefingHeading(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const Flexible(
            child: Text(
              'EXECUTIVE POSITION & CASHFLOW',
              style: TextStyle(
                color: EarthColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'About executive briefing',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.info_outline,
                size: 14, color: mutedColor.withValues(alpha: .8)),
            onPressed: () => showEarthInfoDialog(
              context,
              title: 'EXECUTIVE POSITION & CASHFLOW',
              description:
                  '• NET WORTH is the current combined value of your liquid credits and tracked assets. NET CHANGE compares that value with the end of the previous game day.\n\n'
                  '• INCOME, EXPENSES, and NET CASHFLOW show the operating result for the previous game day. The breakdown identifies the main sources of income and costs.\n\n'
                  '• Alerts and messages are available from the global HUD, where they can be acted on directly.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, {double topOffset = 34}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, topOffset, 0, 10),
      child: Text(
        label,
        style: const TextStyle(
          color: EarthColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildDirectivesContent(DailyBriefingReport r) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: r.recommendedDirectives.isEmpty
            ? [
                const Text('No directives require attention.',
                    style: TextStyle(color: EarthColors.textMuted)),
              ]
            : r.recommendedDirectives.map(_buildDirectiveCard).toList(),
      ),
    );
  }

  Widget _buildDirectiveCard(RecommendedDirective d) {
    Color badgeColor;
    if (d.urgency == 'high') {
      badgeColor = const Color(0xFFFF5252);
    } else if (d.urgency == 'medium') {
      badgeColor = const Color(0xFFFFB300);
    } else {
      badgeColor = const Color(0xFF38BDF8);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: badgeColor),
            ),
            child: Text(
              d.urgency.toUpperCase(),
              style: TextStyle(
                  color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  d.reason,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            key: Key('btn-directive-${d.id}'),
            onPressed: () {
              EarthAudioEngine.instance.playClick();
              if (!widget.isPageMode) Navigator.of(context).pop();
              widget.onNavigate(d.targetSection);
            },
            icon: const Icon(Icons.launch, size: 13),
            label: Text(d.actionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: EarthThemeController.instance.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashflowContent(DailyBriefingReport r) {
    final cf = r.cashflow;
    return LayoutBuilder(
      builder: (context, constraints) {
        final income = _cashflowBreakdown(
          title: 'INCOME SOURCES',
          total: '+${cf.totalIncome.toStringAsFixed(2)} CR',
          color: const Color(0xFF00E676),
          rows: [
            (
              'Market commodity sales',
              '+${cf.marketSales.toStringAsFixed(2)} CR'
            ),
            (
              'Corporate equity dividends',
              '+${cf.businessDividends.toStringAsFixed(2)} CR'
            ),
          ],
        );
        final expenses = _cashflowBreakdown(
          title: 'EXPENSES',
          total: '-${cf.totalExpenses.toStringAsFixed(2)} CR',
          color: const Color(0xFFFF5252),
          rows: [
            (
              'Machine maintenance & fuel',
              '-${cf.machineMaintenance.toStringAsFixed(2)} CR'
            ),
            (
              'Municipal civic taxes',
              '-${cf.civicTaxes.toStringAsFixed(2)} CR'
            ),
          ],
        );
        if (constraints.maxWidth > 520) {
          return Row(children: [
            Expanded(child: income),
            const SizedBox(width: 16),
            Expanded(child: expenses)
          ]);
        }
        return Column(children: [income, const SizedBox(height: 10), expenses]);
      },
    );
  }

  Widget _cashflowBreakdown({
    required String title,
    required String total,
    required Color color,
    required List<(String, String)> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: EarthColors.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: .8)),
              Text(total,
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows) _flowRow(row.$1, row.$2, color),
        ],
      ),
    );
  }

  Widget _flowRow(String label, String val, Color color,
      {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: isBold ? 12 : 11,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          ),
          const SizedBox(width: 8),
          Text(val,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: color,
                  fontSize: isBold ? 13 : 10,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMarketsContent(DailyBriefingReport r) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: r.marketMovements.map((m) {
              final isUp = m.deltaPct >= 0;
              return Container(
                width: 190,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: EarthColors.cardSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: EarthColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.commodity,
                        style: TextStyle(
                            color: EarthThemeController.instance.primaryAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${m.currentPrice.toStringAsFixed(2)} CR',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '${isUp ? '+' : ''}${m.deltaPct.toStringAsFixed(2)}% (24h)',
                      style: TextStyle(
                          color: isUp
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF5252),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIndustryContent(DailyBriefingReport r) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _industryMetric(
            'ACTIVE BUSINESSES', '${r.businessSummary.activeBusinesses}'),
        _industryMetric(
            'DAILY OUTPUT', '${r.businessSummary.totalDailyOutput}'),
        _industryMetric(
            'ACTIVE MACHINES', '${r.businessSummary.activeMachines}'),
        _industryMetric(
            'DEGRADED MACHINES', '${r.businessSummary.degradedMachinesCount}'),
        _industryMetric(
            'PENDING CONTRACTS', '${r.businessSummary.pendingContractsCount}'),
      ],
    );
  }

  Widget _industryMetric(String label, String value) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: EarthColors.textMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6)),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildCivicContent(DailyBriefingReport r) {
    final c = r.civicSummary;
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EarthColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CIVIC RESIDENCY: ${c.cityResidency.toUpperCase()}',
                    style: TextStyle(
                        color: EarthThemeController.instance.primaryAccent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    'Municipal Tax Rate: ${c.cityTaxRatePct}% • Active Senate Bills: ${c.activeProposals}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 12),
                const Text('RECENT CIVIC RESOLUTIONS',
                    style: TextStyle(
                        color: EarthColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...c.recentCivicEvents.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $e',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
