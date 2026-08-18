import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/api/earth_api.dart';
import '../../core/models/daily_briefing.dart';
import '../../core/audio/earth_audio_engine.dart';

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

  const DailyBriefingDialog({
    super.key,
    required this.api,
    required this.onNavigate,
  });

  @override
  State<DailyBriefingDialog> createState() => _DailyBriefingDialogState();
}

class _DailyBriefingDialogState extends State<DailyBriefingDialog> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  DailyBriefingReport? _report;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadBriefing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 880,
        height: 740,
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(140), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: EarthThemeController.instance.primaryAccent.withAlpha(40),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopHeader(),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 36),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadBriefing,
                        child: const Text('RETRY BRIEFING'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_report != null) ...[
              _buildHeroDeltaBanner(_report!),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDirectivesTab(_report!),
                    _buildCashflowTab(_report!),
                    _buildMarketsTab(_report!),
                    _buildCivicTab(_report!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: EarthColors.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
        border: const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: EarthThemeController.instance.primaryAccent.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: EarthThemeController.instance.primaryAccent),
                  ),
                  child: Icon(Icons.analytics_outlined, color: EarthThemeController.instance.primaryAccent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EXECUTIVE INTELLIGENCE BRIEFING',
                        style: TextStyle(
                          color: EarthThemeController.instance.primaryAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Simulation Delta & Strategic Status Digest Since Last Login',
                        style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
      ),
    );
  }

  Widget _buildHeroDeltaBanner(DailyBriefingReport r) {
    final delta = r.netWealthDelta.delta;
    final isPos = delta >= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isPos ? const Color(0xFF00E676).withAlpha(15) : const Color(0xFFFF5252).withAlpha(15),
        border: const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLANETARY SIMULATION DAY ${r.gameDay} • OVERVIEW',
                  style: TextStyle(
                    color: EarthThemeController.instance.primaryAccent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${r.netWealthDelta.current.toStringAsFixed(2)} CR',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPos ? const Color(0xFF00E676).withAlpha(30) : const Color(0xFFFF5252).withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isPos ? const Color(0xFF00E676) : const Color(0xFFFF5252)),
                      ),
                      child: Text(
                        '${isPos ? '+' : ''}${delta.toStringAsFixed(2)} CR (${isPos ? '+' : ''}${r.netWealthDelta.deltaPct.toStringAsFixed(2)}%)',
                        style: TextStyle(
                          color: isPos ? const Color(0xFF00E676) : const Color(0xFFFF5252),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('STATUS DELTA', style: TextStyle(color: EarthColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '${r.unreadAlerts.unreadNotifications} Alerts • ${r.unreadAlerts.unreadComms} Messages',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: EarthColors.cardSurface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: EarthThemeController.instance.primaryAccent,
        indicatorWeight: 3,
        labelColor: EarthThemeController.instance.primaryAccent,
        unselectedLabelColor: EarthColors.textMuted,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6),
        tabs: const [
          Tab(text: 'RECOMMENDED DIRECTIVES'),
          Tab(text: 'CASHFLOW & LEDGER'),
          Tab(text: 'MARKETS & INDUSTRY'),
          Tab(text: 'CIVIC & INTELLIGENCE'),
        ],
      ),
    );
  }

  Widget _buildDirectivesTab(DailyBriefingReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'STRATEGIC DIRECTIVES REQUIRING ATTENTION',
          style: TextStyle(color: EarthColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .8),
        ),
        const SizedBox(height: 12),
        ...r.recommendedDirectives.map((d) => _buildDirectiveCard(d)),
      ],
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
              style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(
                  d.reason,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          FilledButton.icon(
            key: Key('btn-directive-${d.id}'),
            onPressed: () {
              EarthAudioEngine.instance.playClick();
              Navigator.of(context).pop();
              widget.onNavigate(d.targetSection);
            },
            icon: const Icon(Icons.launch, size: 13),
            label: Text(d.actionLabel),
            style: FilledButton.styleFrom(
              backgroundColor: EarthThemeController.instance.primaryAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashflowTab(DailyBriefingReport r) {
    final cf = r.cashflow;
    return ListView(
      padding: const EdgeInsets.all(16),
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
              const Text(
                '24-HOUR FINANCIAL WATERFALL',
                style: TextStyle(color: EarthColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .8),
              ),
              const SizedBox(height: 12),
              _flowRow('Market Commodity Sales', '+${cf.marketSales.toStringAsFixed(2)} CR', const Color(0xFF00E676)),
              _flowRow('Corporate Equity Dividends', '+${cf.businessDividends.toStringAsFixed(2)} CR', const Color(0xFF00E676)),
              const Divider(color: EarthColors.borderSubtle, height: 16),
              _flowRow('Machine Maintenance & Fuel', '-${cf.machineMaintenance.toStringAsFixed(2)} CR', const Color(0xFFFF5252)),
              _flowRow('Municipal Civic Taxes', '-${cf.civicTaxes.toStringAsFixed(2)} CR', const Color(0xFFFF5252)),
              const Divider(color: EarthColors.borderSubtle, height: 20),
              _flowRow('Net Cashflow Profit', '${cf.netProfit >= 0 ? '+' : ''}${cf.netProfit.toStringAsFixed(2)} CR', EarthThemeController.instance.primaryAccent, isBold: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _flowRow(String label, String val, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: isBold ? 12 : 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(val, style: TextStyle(color: color, fontSize: isBold ? 13 : 11.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMarketsTab(DailyBriefingReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'COMMODITY SPOT AUCTION MOVEMENTS',
          style: TextStyle(color: EarthColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .8),
        ),
        const SizedBox(height: 12),
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
                  Text(m.commodity, style: TextStyle(color: EarthThemeController.instance.primaryAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${m.currentPrice.toStringAsFixed(2)} CR', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '${isUp ? '+' : ''}${m.deltaPct.toStringAsFixed(2)}% (24h)',
                    style: TextStyle(color: isUp ? const Color(0xFF00E676) : const Color(0xFFFF5252), fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCivicTab(DailyBriefingReport r) {
    final c = r.civicSummary;
    return ListView(
      padding: const EdgeInsets.all(16),
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
              Text('CIVIC RESIDENCY: ${c.cityResidency.toUpperCase()}', style: TextStyle(color: EarthThemeController.instance.primaryAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Municipal Tax Rate: ${c.cityTaxRatePct}% • Active Senate Bills: ${c.activeProposals}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 12),
              const Text('RECENT CIVIC RESOLUTIONS', style: TextStyle(color: EarthColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...c.recentCivicEvents.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $e', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
