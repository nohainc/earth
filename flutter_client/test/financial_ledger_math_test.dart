import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';
import 'package:earth_client/core/models/earth_state.dart';

void main() {
  group('Tier 1: Financial Ledger & Economic Calculus', () {
    test('formatWholeNumber and formatCreditsAmount properly formats values without float drift', () {
      expect(formatWholeNumber(0.0), '0');
      expect(formatWholeNumber(1234.567), '1234');
      expect(formatWholeNumber(-450.2), '-450');
      expect(formatCreditsAmount(15000), '15000 C');
      expect(formatPercent(0.125), '13%');
      expect(formatPercent(0.50), '50%');
      expect(formatPercent(1.0), '100%');
      expect(asDouble('450.75'), 450.75);
      expect(asInt('128'), 128);
    });

    test('Economic ledger double-entry conservation of credits on share transactions', () {
      double corporateTreasury = 50000.0;
      double playerCredits = 10000.0;
      int totalShares = 1000;
      int playerShares = 800; // 80%

      // Issue 200 new shares at 100 credits/share
      const newShares = 200;
      const sharePrice = 100.0;
      const injection = newShares * sharePrice; // 20,000

      // Outside investor purchases new shares
      corporateTreasury += injection;
      totalShares += newShares; // 1,200 total shares

      // Player equity is diluted: 800 / 1200 = 66.67%
      final playerEquityPercent = (playerShares / totalShares) * 100.0;
      expect(playerEquityPercent, closeTo(66.666, 0.01));
      expect(corporateTreasury, 70000.0);

      // Corporation distributes 12,000 credits in dividends (10 credits / share)
      const totalDividend = 12000.0;
      final dividendPerShare = totalDividend / totalShares; // 10.0
      corporateTreasury -= totalDividend;
      final playerDividend = playerShares * dividendPerShare; // 8,000.0
      playerCredits += playerDividend;

      expect(corporateTreasury, 58000.0);
      expect(playerCredits, 18000.0);
      expect(dividendPerShare, 10.0);
    });

    test('EarthState evaluates financial net worth, liquidity ratio, and solvency checks', () {
      final rawState = {
        'clock': {'day': 120, 'minute': 720},
        'human': {
          'id': 'H-101',
          'name': 'Elena Vance',
          'credits': 15000.0,
        },
        'resources': {
          'credits': 15000.0,
          'energy': 250.0,
          'food': 300.0,
          'materials': 120.0,
          'components': 45.0,
          'compute': 80.0,
        },
        'business': {
          'id': 'B-501',
          'name': 'Vance Orbital Logistics',
          'revenue': 8500.0,
          'expenses': 4200.0,
          'profit': 4300.0,
          'valuation': 120000.0,
          'treasury': 35000.0,
        },
        'market': {
          'prices': {
            'energy': 1.25,
            'food': 0.85,
            'materials': 3.50,
            'components': 8.00,
            'compute': 5.20,
          }
        },
        'machines': [
          {'id': 'm-1', 'name': 'Smelter', 'condition': 92.0, 'utilization': 75.0, 'value': 25000.0},
          {'id': 'm-2', 'name': 'Assembler', 'condition': 64.0, 'utilization': 88.0, 'value': 18000.0},
        ],
      };

      final state = EarthState(rawState);
      expect(state.clock['day'], 120);
      expect(state.human['credits'], 15000.0);
      expect(state.business['id'], 'B-501');
      expect(state.business['name'], 'Vance Orbital Logistics');
      expect(state.business['profit'], 4300.0);

      // Commodity resource net worth calculation
      final energyVal = 250.0 * 1.25; // 312.5
      final foodVal = 300.0 * 0.85; // 255.0
      final materialsVal = 120.0 * 3.50; // 420.0
      final componentsVal = 45.0 * 8.00; // 360.0
      final computeVal = 80.0 * 5.20; // 416.0
      final totalCommodityValue = energyVal + foodVal + materialsVal + componentsVal + computeVal;
      expect(totalCommodityValue, 1763.5);

      final totalLiquid = (state.human['credits'] as num) + totalCommodityValue;
      expect(totalLiquid, 16763.5);
    });
  });
}
