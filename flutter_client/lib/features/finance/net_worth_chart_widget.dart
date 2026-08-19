import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';

class NetWorthChartWidget extends StatefulWidget {
  final List<Map<String, dynamic>> snapshots;
  final double height;

  const NetWorthChartWidget({
    super.key,
    required this.snapshots,
    this.height = 280,
  });

  @override
  State<NetWorthChartWidget> createState() => _NetWorthChartWidgetState();
}

class _NetWorthChartWidgetState extends State<NetWorthChartWidget> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.snapshots.isEmpty) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EarthColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: EarthColors.borderSubtle),
        ),
        child: const Text(
          'No historical net-worth snapshots recorded yet.',
          style: TextStyle(color: EarthColors.textMuted, fontSize: 12),
        ),
      );
    }

    final latest = widget.snapshots.last;
    final inspected =
        (_hoveredIndex != null && _hoveredIndex! < widget.snapshots.length)
            ? widget.snapshots[_hoveredIndex!]
            : latest;

    final tot = _parseNum(inspected['total_net_worth']);
    final cash = _parseNum(inspected['liquid_credits']);
    final comm = _parseNum(inspected['commodity_valuation']);
    final eq = _parseNum(inspected['equity_valuation']);
    final re = _parseNum(inspected['real_estate_valuation']);
    final day = inspected['game_day']?.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080B12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EarthColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top HUD
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: EarthColors.cardSurface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border: const Border(
                  bottom: BorderSide(color: EarthColors.borderSubtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart,
                        color: EarthThemeController.instance.primaryAccent,
                        size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'TOTAL WEALTH',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${tot.toStringAsFixed(2)} CR',
                      style: TextStyle(
                        color: EarthThemeController.instance.primaryAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _statBadge('DAY', day, Colors.white),
                        const SizedBox(width: 8),
                        _statBadge('CASH', '${cash.toStringAsFixed(0)} CR',
                            EarthThemeController.instance.goldMetallic),
                        const SizedBox(width: 8),
                        _statBadge(
                            'COMMODITIES',
                            '${comm.toStringAsFixed(0)} CR',
                            EarthThemeController.instance.primaryAccent),
                        const SizedBox(width: 8),
                        _statBadge('EQUITY', '${eq.toStringAsFixed(0)} CR',
                            const Color(0xFFC084FC)),
                        const SizedBox(width: 8),
                        _statBadge(
                            'OTHER ASSETS',
                            '${re.toStringAsFixed(0)} CR',
                            const Color(0xFFFB923C)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chart Canvas
          SizedBox(
            height: widget.height - 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  onHover: (event) {
                    final width = constraints.maxWidth;
                    final n = widget.snapshots.length;
                    if (n > 1) {
                      final segWidth = width / (n - 1);
                      final idx = (event.localPosition.dx / segWidth)
                          .round()
                          .clamp(0, n - 1);
                      if (idx != _hoveredIndex) {
                        EarthAudioEngine.instance.playClick();
                        setState(() => _hoveredIndex = idx);
                      }
                    }
                  },
                  onExit: (_) {
                    if (_hoveredIndex != null) {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, widget.height - 48),
                    painter: _NetWorthChartPainter(
                      snapshots: widget.snapshots,
                      hoveredIndex: _hoveredIndex,
                      primaryAccent:
                          EarthThemeController.instance.primaryAccent,
                      goldAccent: EarthThemeController.instance.goldMetallic,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: EarthColors.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 9.5, fontWeight: FontWeight.bold)),
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

class _NetWorthChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> snapshots;
  final int? hoveredIndex;
  final Color primaryAccent;
  final Color goldAccent;

  _NetWorthChartPainter({
    required this.snapshots,
    required this.hoveredIndex,
    required this.primaryAccent,
    required this.goldAccent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (snapshots.isEmpty) return;

    final n = snapshots.length;
    double maxVal = 1000.0;

    for (final s in snapshots) {
      final t = _val(s['total_net_worth']);
      if (t > maxVal) maxVal = t;
    }
    maxVal *= 1.12;

    const padLeft = 48.0;
    const padRight = 16.0;
    const padTop = 16.0;
    const padBottom = 24.0;

    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padTop - padBottom;

    if (chartW <= 0 || chartH <= 0) return;

    // 1. Grid lines & Y-labels
    final gridPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0;

    const steps = 4;
    for (int i = 0; i <= steps; i++) {
      final y = padTop + chartH * (1.0 - (i / steps));
      canvas.drawLine(
          Offset(padLeft, y), Offset(size.width - padRight, y), gridPaint);

      final val = (maxVal * (i / steps));
      final tp = TextPainter(
        text: TextSpan(
          text: val >= 1000
              ? '${(val / 1000).toStringAsFixed(1)}k'
              : val.toStringAsFixed(0),
          style: const TextStyle(color: Colors.white30, fontSize: 8.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(padLeft - tp.width - 6, y - tp.height / 2));
    }

    // 2. Compute Points
    final totalPoints = <Offset>[];
    final cashPoints = <Offset>[];
    final commPoints = <Offset>[];
    final eqPoints = <Offset>[];
    final rePoints = <Offset>[];

    for (int i = 0; i < n; i++) {
      final s = snapshots[i];
      final x =
          n > 1 ? padLeft + (chartW * (i / (n - 1))) : padLeft + chartW / 2;

      final t = _val(s['total_net_worth']);
      final c = _val(s['liquid_credits']);
      final m = _val(s['commodity_valuation']);
      final e = _val(s['equity_valuation']);
      final r = _val(s['real_estate_valuation']);

      final yTot = padTop + chartH * (1.0 - (t / maxVal)).clamp(0.0, 1.0);
      final yCash = padTop + chartH * (1.0 - (c / maxVal)).clamp(0.0, 1.0);
      final yComm = padTop + chartH * (1.0 - (m / maxVal)).clamp(0.0, 1.0);
      final yEq = padTop + chartH * (1.0 - (e / maxVal)).clamp(0.0, 1.0);
      final yRe = padTop + chartH * (1.0 - (r / maxVal)).clamp(0.0, 1.0);

      totalPoints.add(Offset(x, yTot));
      cashPoints.add(Offset(x, yCash));
      commPoints.add(Offset(x, yComm));
      eqPoints.add(Offset(x, yEq));
      rePoints.add(Offset(x, yRe));
    }

    // 3. Fill Area under total wealth curve
    if (totalPoints.length > 1) {
      final areaPath = Path()..moveTo(totalPoints.first.dx, padTop + chartH);
      for (final p in totalPoints) {
        areaPath.lineTo(p.dx, p.dy);
      }
      areaPath.lineTo(totalPoints.last.dx, padTop + chartH);
      areaPath.close();

      final areaGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryAccent.withAlpha(50),
          primaryAccent.withAlpha(0),
        ],
      );
      final areaPaint = Paint()
        ..shader = areaGradient
            .createShader(Rect.fromLTWH(padLeft, padTop, chartW, chartH));
      canvas.drawPath(areaPath, areaPaint);
    }

    // 4. Draw asset category curves
    _drawCurve(canvas, cashPoints, goldAccent.withAlpha(160), 1.2);
    _drawCurve(canvas, commPoints, primaryAccent.withAlpha(160), 1.2);
    _drawCurve(canvas, eqPoints, const Color(0xFFC084FC).withAlpha(160), 1.2);
    _drawCurve(canvas, rePoints, const Color(0xFFFB923C).withAlpha(160), 1.2);

    // 5. Draw primary Total Wealth Curve
    _drawCurve(canvas, totalPoints, primaryAccent, 2.5);

    // 6. Draw Hover Scrubber line
    if (hoveredIndex != null && hoveredIndex! < totalPoints.length) {
      final hp = totalPoints[hoveredIndex!];
      final scrubPaint = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.0;
      canvas.drawLine(
          Offset(hp.dx, padTop), Offset(hp.dx, padTop + chartH), scrubPaint);

      final dotPaint = Paint()
        ..color = primaryAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(hp, 4.5, dotPaint);

      final dotRing = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(hp, 4.5, dotRing);
    }
  }

  void _drawCurve(
      Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);
  }

  double _val(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  bool shouldRepaint(covariant _NetWorthChartPainter oldDelegate) {
    return oldDelegate.snapshots != snapshots ||
        oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.primaryAccent != primaryAccent ||
        oldDelegate.goldAccent != goldAccent;
  }
}
