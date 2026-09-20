import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/market_models.dart';
import '../../shared/design_system/earth_theme_context.dart';

class CandlestickChartWidget extends StatefulWidget {
  final List<MarketCandle> candles;
  final List<double?> ma7;
  final List<double?> ma25;
  final String commodity;
  final double height;

  const CandlestickChartWidget({
    super.key,
    required this.candles,
    required this.ma7,
    required this.ma25,
    required this.commodity,
    this.height = 280,
  });

  @override
  State<CandlestickChartWidget> createState() => _CandlestickChartWidgetState();
}

class _CandlestickChartWidgetState extends State<CandlestickChartWidget> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) {
      return Container(
        height: widget.height,
        color: context.panelColor,
        alignment: Alignment.center,
        child: Text(
          'No instrument candle data available.',
          style: TextStyle(fontSize: 11, color: context.mutedColor),
        ),
      );
    }

    final latest = widget.candles.last;
    final first = widget.candles.first;
    final close = _parseNum(latest.close);
    final openInitial = _parseNum(first.open);
    final changePct =
        openInitial > 0 ? ((close - openInitial) / openInitial) * 100 : 0.0;
    final isBullish = changePct >= 0;

    final inspected =
        _hoveredIndex != null && _hoveredIndex! < widget.candles.length
            ? widget.candles[_hoveredIndex!]
            : latest;
    final inspectedMa7 =
        _hoveredIndex != null && _hoveredIndex! < widget.ma7.length
            ? widget.ma7[_hoveredIndex!]
            : (widget.ma7.isNotEmpty ? widget.ma7.last : null);
    final inspectedMa25 =
        _hoveredIndex != null && _hoveredIndex! < widget.ma25.length
            ? widget.ma25[_hoveredIndex!]
            : (widget.ma25.isNotEmpty ? widget.ma25.last : null);

    return Container(
      decoration: BoxDecoration(
        color: context.canvasColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Chart HUD Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              border:
                  Border(bottom: BorderSide(color: context.subtleBorderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.commodity.toUpperCase(),
                      style: TextStyle(
                        color: context.inkColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${close.toStringAsFixed(2)} CR',
                      style: TextStyle(
                        color: isBullish
                            ? context.successColor
                            : context.errorColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isBullish
                                ? context.successColor
                                : context.errorColor)
                            .withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${isBullish ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isBullish
                              ? context.successColor
                              : context.errorColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                // Tooltip / Scrubber Values
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _hudStat(context, 'PERIOD', inspected.periodId),
                        const SizedBox(width: 8),
                        _hudStat(context, 'O',
                            _parseNum(inspected.open).toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        _hudStat(context, 'H',
                            _parseNum(inspected.high).toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        _hudStat(context, 'L',
                            _parseNum(inspected.low).toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        _hudStat(context, 'C',
                            _parseNum(inspected.close).toStringAsFixed(2)),
                        const SizedBox(width: 8),
                        _hudStat(context, 'VOL',
                            _parseNum(inspected.volume).toStringAsFixed(0)),
                        if (inspectedMa7 != null) ...[
                          const SizedBox(width: 8),
                          _hudStat(
                              context, 'MA7', inspectedMa7.toStringAsFixed(2),
                              color: context.goldColor),
                        ],
                        if (inspectedMa25 != null) ...[
                          const SizedBox(width: 8),
                          _hudStat(
                              context, 'MA25', inspectedMa25.toStringAsFixed(2),
                              color: context.primaryColor),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Canvas Viewport
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return MouseRegion(
                  onHover: (event) {
                    final candleWidth =
                        constraints.maxWidth / widget.candles.length;
                    final index = (event.localPosition.dx / candleWidth)
                        .floor()
                        .clamp(0, widget.candles.length - 1);
                    setState(() => _hoveredIndex = index);
                  },
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: GestureDetector(
                    onTapDown: (details) {
                      final candleWidth =
                          constraints.maxWidth / widget.candles.length;
                      final index = (details.localPosition.dx / candleWidth)
                          .floor()
                          .clamp(0, widget.candles.length - 1);
                      setState(() => _hoveredIndex = index);
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, widget.height),
                      painter: _CandlestickPainter(
                        candles: widget.candles,
                        ma7: widget.ma7,
                        ma25: widget.ma25,
                        hoveredIndex: _hoveredIndex,
                        gridColor: context.subtleBorderColor,
                        bullishColor: context.successColor,
                        bearishColor: context.errorColor,
                        crosshairColor: context.inkColor,
                        ma7Color: context.goldColor,
                        ma25Color: context.primaryColor,
                      ),
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

  Widget _hudStat(BuildContext context, String label, String val,
      {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(color: context.mutedColor, fontSize: 9.5)),
        Text(val,
            style: TextStyle(
                color: color ?? context.inkColor.withValues(alpha: .7),
                fontWeight: FontWeight.bold,
                fontSize: 9.5)),
      ],
    );
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<MarketCandle> candles;
  final List<double?> ma7;
  final List<double?> ma25;
  final int? hoveredIndex;
  final Color gridColor;
  final Color bullishColor;
  final Color bearishColor;
  final Color crosshairColor;
  final Color ma7Color;
  final Color ma25Color;

  _CandlestickPainter({
    required this.candles,
    required this.ma7,
    required this.ma25,
    required this.gridColor,
    required this.bullishColor,
    required this.bearishColor,
    required this.crosshairColor,
    required this.ma7Color,
    required this.ma25Color,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty) return;

    final count = candles.length;
    final candleWidth = size.width / count;
    final barWidth = math.max(2.0, candleWidth * 0.7);

    // Calculate Min & Max Prices
    double minPrice = double.infinity;
    double maxPrice = -double.infinity;
    double maxVolume = 0.0;

    for (final candle in candles) {
      final l = _parseNum(candle.low);
      final h = _parseNum(candle.high);
      final v = _parseNum(candle.volume);
      if (l < minPrice) minPrice = l;
      if (h > maxPrice) maxPrice = h;
      if (v > maxVolume) maxVolume = v;
    }

    // Add padding
    final pricePadding = (maxPrice - minPrice) * 0.08;
    minPrice = math.max(0.1, minPrice - pricePadding);
    maxPrice += pricePadding;
    final priceRange = maxPrice - minPrice;

    final chartHeight = size.height * 0.75;
    final volumeHeight = size.height * 0.22;
    // 1. Draw Grid Lines
    final gridPaint = Paint()
      ..color = gridColor.withAlpha(15)
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      final y = chartHeight * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final bullishPaint = Paint()..color = bullishColor;
    final bearishPaint = Paint()..color = bearishColor;
    final wickPaintBull = Paint()
      ..color = bullishColor
      ..strokeWidth = 1.5;
    final wickPaintBear = Paint()
      ..color = bearishColor
      ..strokeWidth = 1.5;

    // 2. Draw Candlesticks & Volumes
    for (int i = 0; i < count; i++) {
      final candle = candles[i];
      final o = _parseNum(candle.open);
      final h = _parseNum(candle.high);
      final l = _parseNum(candle.low);
      final c = _parseNum(candle.close);
      final v = _parseNum(candle.volume);

      final isBull = c >= o;
      final xCenter = (i * candleWidth) + (candleWidth / 2.0);

      final yOpen = chartHeight - ((o - minPrice) / priceRange) * chartHeight;
      final yClose = chartHeight - ((c - minPrice) / priceRange) * chartHeight;
      final yHigh = chartHeight - ((h - minPrice) / priceRange) * chartHeight;
      final yLow = chartHeight - ((l - minPrice) / priceRange) * chartHeight;

      // Draw Wick Stem
      canvas.drawLine(
        Offset(xCenter, yHigh),
        Offset(xCenter, yLow),
        isBull ? wickPaintBull : wickPaintBear,
      );

      // Draw Candle Body
      final bodyTop = math.min(yOpen, yClose);
      final bodyHeight = math.max(2.0, (yOpen - yClose).abs());
      final bodyRect = Rect.fromCenter(
        center: Offset(xCenter, bodyTop + bodyHeight / 2.0),
        width: barWidth,
        height: bodyHeight,
      );
      canvas.drawRect(bodyRect, isBull ? bullishPaint : bearishPaint);

      // Draw Volume Bar
      if (maxVolume > 0) {
        final vHeight = (v / maxVolume) * volumeHeight;
        final vRect = Rect.fromLTWH(
          xCenter - barWidth / 2.0,
          size.height - vHeight,
          barWidth,
          vHeight,
        );
        final vPaint = Paint()
          ..color = (isBull ? bullishColor : bearishColor).withAlpha(50);
        canvas.drawRect(vRect, vPaint);
      }
    }

    // 3. Draw Moving Averages
    _drawMovingAverage(
        canvas, ma7, minPrice, priceRange, chartHeight, candleWidth, ma7Color);
    _drawMovingAverage(canvas, ma25, minPrice, priceRange, chartHeight,
        candleWidth, ma25Color);

    // 4. Draw Hover Crosshair
    if (hoveredIndex != null && hoveredIndex! < count) {
      final hX = (hoveredIndex! * candleWidth) + (candleWidth / 2.0);
      final crosshairPaint = Paint()
        ..color = crosshairColor.withAlpha(70)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(hX, 0), Offset(hX, size.height), crosshairPaint);
    }
  }

  void _drawMovingAverage(
    Canvas canvas,
    List<double?> maList,
    double minPrice,
    double priceRange,
    double chartHeight,
    double candleWidth,
    Color color,
  ) {
    if (maList.isEmpty) return;
    final maPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;

    for (int i = 0; i < maList.length; i++) {
      final val = maList[i];
      if (val == null) continue;
      final x = (i * candleWidth) + (candleWidth / 2.0);
      final y = chartHeight - ((val - minPrice) / priceRange) * chartHeight;
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (started) {
      canvas.drawPath(path, maPaint);
    }
  }

  static double _parseNum(dynamic val, {double fallback = 0.0}) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? fallback;
    return fallback;
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
