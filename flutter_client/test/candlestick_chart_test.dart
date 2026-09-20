import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/market/candlestick_chart_widget.dart';
import 'package:earth_client/core/models/market_models.dart';

void main() {
  testWidgets('CandlestickChartWidget renders header, indicators and handles empty/populated states', (tester) async {
    // Empty state
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CandlestickChartWidget(
            candles: [],
            ma7: [],
            ma25: [],
            commodity: 'energy',
          ),
        ),
      ),
    );
    expect(find.text('No instrument candle data available.'), findsOneWidget);

    // Populated state with OHLC data
    final candles = [
      const MarketCandle(
        periodId: '180-01',
        open: '28.00',
        high: '31.00',
        low: '27.50',
        close: '30.50',
        volume: '1200',
        fillCount: 4,
      ),
      const MarketCandle(
        periodId: '181-01',
        open: '30.50',
        high: '33.00',
        low: '30.00',
        close: '32.50',
        volume: '1500',
        fillCount: 5,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CandlestickChartWidget(
            candles: candles,
            ma7: const [29.0, 31.0],
            ma25: const [28.0, 29.5],
            commodity: 'energy',
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('ENERGY'), findsOneWidget);
    expect(find.text('32.50 CR'), findsOneWidget);
    expect(find.text('PERIOD: '), findsOneWidget);
    expect(find.text('O: '), findsOneWidget);
    expect(find.text('H: '), findsOneWidget);
    expect(find.text('L: '), findsOneWidget);
    expect(find.text('C: '), findsOneWidget);
  });
}
