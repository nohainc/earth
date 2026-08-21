import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/widgets/earth_primitives.dart';
import '../market/market_panels.dart';

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

  Color get _groupSurface => EarthThemeController.instance.cardSurface;
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
          '• Review what changed since your last visit.\n\n• Handle the decisions that can affect your businesses, household, city, or long-term direction.\n\n• Detailed market, finance, business, and civic screens remain available through the action links.',
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
        color: _groupSurface,
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
          _buildSectionLabel('WHAT REQUIRES ATTENTION'),
          _buildDirectivesContent(r),
        ];
        final right = <Widget>[
          _buildSectionLabel('CURRENT OPERATIONS', topOffset: wide ? 0 : 34),
          _buildIndustryContent(r),
          _buildSectionLabel('CITY & CIVIC EFFECTS'),
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
                        _buildSectionLabel('WHAT CHANGED', topOffset: 28),
                        _buildRecentChangesContent(r),
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
              _buildSectionLabel('WHAT CHANGED', topOffset: 28),
              _buildRecentChangesContent(r),
              ...left,
              ...right,
            ],
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => widget.onNavigate('activity'),
                icon: const Icon(Icons.history_outlined, size: 14),
                label: const Text(
                  'OPEN COMPLETE EVENT HISTORY',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
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
              'SINCE YOUR LAST VISIT',
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
              title: 'SINCE YOUR LAST VISIT',
              description:
                  '• The financial result compares your current position with the previous game day.\n\n'
                  '• The change list highlights business, contract, civic, and household effects that may require a decision.\n\n'
                  '• Open Finance or Activity for the complete ledger and event history.',
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

  Widget _buildRecentChangesContent(DailyBriefingReport r) {
    final changes = <(String, String, IconData, Color)>[
      (
        'Financial result',
        '${r.cashflow.netProfit >= 0 ? '+' : ''}${r.cashflow.netProfit.toStringAsFixed(2)} CR net cashflow',
        r.cashflow.netProfit >= 0 ? Icons.trending_up : Icons.trending_down,
        r.cashflow.netProfit >= 0
            ? const Color(0xFF00E676)
            : const Color(0xFFFF5252),
      ),
      (
        'Operations',
        '${r.businessSummary.activeBusinesses} businesses · ${r.businessSummary.activeMachines} machines · ${r.businessSummary.pendingContractsCount} pending contracts',
        Icons.business_center_outlined,
        EarthThemeController.instance.primaryAccent,
      ),
      if (r.civicSummary.recentCivicEvents.isNotEmpty)
        (
          'City and civic life',
          r.civicSummary.recentCivicEvents.first,
          Icons.location_city_outlined,
          EarthColors.goldMetallic,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: changes.indexed.map((indexed) {
          final change = indexed.$2;
          final isLast = indexed.$1 == changes.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: EarthColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Icon(change.$3, size: 16, color: change.$4),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(change.$1,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(change.$2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 10)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDirectivesContent(DailyBriefingReport r) {
    if (r.recommendedDirectives.isEmpty) {
      return const Text('No directives require attention.',
          style: TextStyle(color: EarthColors.textMuted));
    }

    return Container(
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: r.recommendedDirectives.indexed.map((indexed) {
          final d = indexed.$2;
          final isLast = indexed.$1 == r.recommendedDirectives.length - 1;

          Color badgeColor;
          if (d.urgency == 'high') {
            badgeColor = const Color(0xFFFF5252);
          } else if (d.urgency == 'medium') {
            badgeColor = const Color(0xFFFFB300);
          } else {
            badgeColor = const Color(0xFF38BDF8);
          }

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: EarthColors.borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    d.urgency.toUpperCase(),
                    style: TextStyle(
                        color: badgeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold),
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
                    backgroundColor:
                        EarthThemeController.instance.primaryAccent,
                    foregroundColor: Colors.black,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
        color: _groupSurface,
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
    return Container(
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: r.marketMovements.indexed.map((indexed) {
          final m = indexed.$2;
          final isLast = indexed.$1 == r.marketMovements.length - 1;
          final meta = CommodityMeta.forProduct(m.commodity);
          final isUp = m.deltaPct >= 0;
          final deltaStr =
              '${isUp ? '+' : ''}${m.deltaPct.toStringAsFixed(2)}%';
          final deltaColor =
              isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: EarthColors.borderSubtle),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(meta.icon, size: 26, color: meta.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meta.name,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${m.currentPrice.toStringAsFixed(2)} C',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            '${m.volume24h} units vol',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: EarthColors.textMuted),
                          ),
                          const Spacer(),
                          Text(
                            deltaStr,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: deltaColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIndustryContent(DailyBriefingReport r) {
    final items = [
      (
        'ACTIVE BUSINESSES',
        '${r.businessSummary.activeBusinesses}',
        Icons.storefront_outlined,
        EarthThemeController.instance.primaryAccent,
      ),
      (
        'DAILY OUTPUT',
        '${r.businessSummary.totalDailyOutput}',
        Icons.precision_manufacturing_outlined,
        const Color(0xFF00E676),
      ),
      (
        'ACTIVE MACHINES',
        '${r.businessSummary.activeMachines}',
        Icons.settings_suggest_outlined,
        const Color(0xFF38BDF8),
      ),
      (
        'DEGRADED MACHINES',
        '${r.businessSummary.degradedMachinesCount}',
        Icons.warning_amber_outlined,
        const Color(0xFFFF5252),
      ),
      (
        'PENDING CONTRACTS',
        '${r.businessSummary.pendingContractsCount}',
        Icons.assignment_outlined,
        const Color(0xFFFFB300),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: _groupSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: items.indexed.map((indexed) {
          final item = indexed.$2;
          final isLast = indexed.$1 == items.length - 1;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : const BorderSide(color: EarthColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: item.$4.withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(item.$3, size: 16, color: item.$4),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.$1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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
              color: _groupSurface,
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
