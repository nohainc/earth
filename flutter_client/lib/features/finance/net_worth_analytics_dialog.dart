import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/widgets/earth_primitives.dart';
import 'net_worth_chart_widget.dart';

void showNetWorthAnalyticsDialog(BuildContext context, {required EarthApi api}) {
  showDialog(
    context: context,
    builder: (context) => NetWorthAnalyticsDialog(api: api),
  );
}

class NetWorthAnalyticsDialog extends StatefulWidget {
  final EarthApi api;
  final bool isPageMode;
  final ValueChanged<String>? onNavigate;

  const NetWorthAnalyticsDialog({
    super.key,
    required this.api,
    this.isPageMode = false,
    this.onNavigate,
  });

  @override
  State<NetWorthAnalyticsDialog> createState() => _NetWorthAnalyticsDialogState();
}

class _NetWorthAnalyticsDialogState extends State<NetWorthAnalyticsDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _snapshots = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.api.getNetWorthHistory();
      final isOk = res['ok'] == true || res['ok'] == 'true';
      if (isOk) {
        final rawSnapshots = ((res['snapshots'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final rawSummary = res['summary'] is Map
            ? Map<String, dynamic>.from(res['summary'] as Map)
            : <String, dynamic>{};

        if (mounted) {
          setState(() {
            _snapshots = rawSnapshots;
            _summary = rawSummary;
            _loading = false;
          });
          EarthAudioEngine.instance.playCash();
        }
      } else {
        if (mounted) {
          setState(() {
            _error = res['error']?.toString() ?? 'Failed to load net-worth data';
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
    Widget content = Container(
      width: widget.isPageMode ? double.infinity : 1000,
      constraints: BoxConstraints(maxHeight: widget.isPageMode ? 740 : 780),
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : EarthColors.panelSurface,
        borderRadius: widget.isPageMode ? BorderRadius.zero : BorderRadius.circular(12),
        border: widget.isPageMode
            ? null
            : Border.all(
                color: EarthThemeController.instance.primaryAccent.withAlpha(120),
                width: 1.5,
              ),
        boxShadow: widget.isPageMode
            ? null
            : [
                BoxShadow(
                  color: EarthThemeController.instance.primaryAccent.withAlpha(40),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopHeader(),
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadHistory,
                                child: const Text('RETRY'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: widget.isPageMode
                            ? EdgeInsets.zero
                            : const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildKpiSummaryRow(),
                            const SizedBox(height: 16),
                            NetWorthChartWidget(snapshots: _snapshots, height: 280),
                            const SizedBox(height: 16),
                            _buildAssetAllocationSection(),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );

    if (widget.isPageMode) {
      return content;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: content,
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: widget.isPageMode
          ? const EdgeInsets.only(bottom: 10)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isPageMode ? Colors.transparent : EarthColors.cardSurface,
        borderRadius: widget.isPageMode
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(11)),
        border: widget.isPageMode
            ? null
            : const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'PERSONAL & MULTI-GENERATIONAL NET-WORTH ANALYTICS',
                    style: const TextStyle(
                      color: EarthColors.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                IconButton(
                  tooltip: 'About Net-Worth Analytics',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.info_outline,
                      size: 14, color: EarthColors.textMuted.withValues(alpha: .8)),
                  onPressed: () => showEarthInfoDialog(
                    context,
                    title: 'PERSONAL & MULTI-GENERATIONAL NET-WORTH ANALYTICS',
                    description:
                        '• 4-Pillar Portfolio Valuation: Real-time accounting across Liquid Cash, Commodities, Equity, and Capital Machinery.\n\n• Solvency & Wealth Index: Continuous valuation history tracking wealth trajectory across World eras.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: EarthColors.textMuted, size: 18),
                tooltip: 'Refresh Portfolio',
                onPressed: () {
                  EarthAudioEngine.instance.playClick();
                  _loadHistory();
                },
              ),
              if (!widget.isPageMode) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    EarthAudioEngine.instance.playClick();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSummaryRow() {
    final curTot = _parseNum(_summary['currentNetWorth']);
    final growth = _parseNum(_summary['growthRatePct']);
    final peak = _parseNum(_summary['peakNetWorth']);
    final peakDay = _summary['peakDay'] ?? 185;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final numCols = w > 600 ? 4 : 2;
        final cardW = (w - (numCols - 1) * 12) / numCols;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard(
              cardW,
              'TOTAL NET WORTH',
              '${curTot.toStringAsFixed(2)} CR',
              '${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(2)}% (30D)',
              growth >= 0 ? const Color(0xFF00E676) : const Color(0xFFFF5252),
              EarthThemeController.instance.primaryAccent,
              Icons.trending_up,
            ),
            _kpiCard(
              cardW,
              'ALL-TIME PEAK WEALTH',
              '${peak.toStringAsFixed(2)} CR',
              'Recorded on Day $peakDay',
              EarthColors.textMuted,
              EarthThemeController.instance.goldMetallic,
              Icons.emoji_events_outlined,
            ),
            _kpiCard(
              cardW,
              'LIQUID CASH RATIO',
              '${_parseNum(_summary['assetAllocation']?['cashPct']).toStringAsFixed(1)}%',
              '${_parseNum(_summary['liquidCredits']).toStringAsFixed(0)} CR Liquid',
              EarthColors.textMuted,
              const Color(0xFF38BDF8),
              Icons.savings_outlined,
            ),
            _kpiCard(
              cardW,
              'EQUITY & OTHER ASSETS',
              '${(_parseNum(_summary['assetAllocation']?['equityPct']) + _parseNum(_summary['assetAllocation']?['realEstatePct'])).toStringAsFixed(1)}%',
              'Productive Capital Assets',
              EarthColors.textMuted,
              const Color(0xFFC084FC),
              Icons.pie_chart_outline,
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard(
    double width,
    String label,
    String value,
    String subtext,
    Color subtextColor,
    Color accentColor,
    IconData icon,
  ) {
    return Container(
      width: width,
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
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: EarthColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: .6),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: accentColor),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: TextStyle(color: subtextColor, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetAllocationSection() {
    final alloc = _summary['assetAllocation'] as Map<String, dynamic>? ?? {};
    final cashPct = _parseNum(alloc['cashPct']);
    final commPct = _parseNum(alloc['commodityPct']);
    final eqPct = _parseNum(alloc['equityPct']);
    final rePct = _parseNum(alloc['realEstatePct']);

    final cashVal = _parseNum(_summary['liquidCredits']);
    final commVal = _parseNum(_summary['commodityValuation']);
    final eqVal = _parseNum(_summary['equityValuation']);
    final reVal = _parseNum(_summary['realEstateValuation']);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ASSET ALLOCATION BREAKDOWN',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              Text(
                '4 Pillars Diversification',
                style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Multi-Colored Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (cashPct > 0)
                    Expanded(
                      flex: (cashPct * 10).round().clamp(1, 1000),
                      child: Container(color: EarthThemeController.instance.goldMetallic),
                    ),
                  if (commPct > 0)
                    Expanded(
                      flex: (commPct * 10).round().clamp(1, 1000),
                      child: Container(color: EarthThemeController.instance.primaryAccent),
                    ),
                  if (eqPct > 0)
                    Expanded(
                      flex: (eqPct * 10).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFFC084FC)),
                    ),
                  if (rePct > 0)
                    Expanded(
                      flex: (rePct * 10).round().clamp(1, 1000),
                      child: Container(color: const Color(0xFFFB923C)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4 Breakdown Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cardW = (w - 36) / 4;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _assetPillarCard(cardW > 160 ? cardW : w / 2 - 8, 'LIQUID CREDITS', '${cashVal.toStringAsFixed(0)} CR', '$cashPct%', EarthThemeController.instance.goldMetallic),
                  _assetPillarCard(cardW > 160 ? cardW : w / 2 - 8, 'COMMODITIES', '${commVal.toStringAsFixed(0)} CR', '$commPct%', EarthThemeController.instance.primaryAccent),
                  _assetPillarCard(cardW > 160 ? cardW : w / 2 - 8, 'CORPORATE EQUITY', '${eqVal.toStringAsFixed(0)} CR', '$eqPct%', const Color(0xFFC084FC)),
                  _assetPillarCard(cardW > 160 ? cardW : w / 2 - 8, 'OTHER ASSETS', '${reVal.toStringAsFixed(0)} CR', '$rePct%', const Color(0xFFFB923C)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _assetPillarCard(double width, String title, String amount, String pct, Color color) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                pct,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
