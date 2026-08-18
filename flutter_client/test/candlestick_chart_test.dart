import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/features/market/candlestick_chart_widget.dart';

void main() {
  testWidgets('CandlestickChartWidget renders header, indicators and handles empty/populated states', (tester) async {
    // Empty state
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CandlestickChartWidget(
            ohlc: [],
            ma7: [],
            ma25: [],
            commodity: 'energy',
          ),
        ),
      ),
    );
    expect(find.text('No historical OHLC data available.'), findsOneWidget);

    // Populated state with OHLC data
    final ohlcData = [
      {
        'game_day': 180,
        'open_price': 28.0,
        'high_price': 31.0,
        'low_price': 27.5,
        'close_price': 30.5,
        'volume': 1200.0,
      },
      {
        'game_day': 181,
        'open_price': 30.5,
        'high_price': 33.0,
        'low_price': 30.0,
        'close_price': 32.5,
        'volume': 1500.0,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CandlestickChartWidget(
            ohlc: ohlcData,
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
    expect(find.text('DAY: '), findsOneWidget);
    expect(find.text('O: '), findsOneWidget);
    expect(find.text('H: '), findsOneWidget);
    expect(find.text('L: '), findsOneWidget);
    expect(find.text('C: '), findsOneWidget);
  });
}
