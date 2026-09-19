import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/house_finance_models.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  test('loan values remain exact atomic units at the UI boundary', () {
    final finance = HouseFinanceOverview.fromJson({
      'houseId': 'HOUSE-1',
      'bank': {
        'loans': [
          {
            'id': 'LOAN-1',
            'status': 'ACTIVE',
            'outstanding_principal_units': '50000',
            'accrued_interest_units': '0',
          },
        ],
      },
    });

    expect(formatCreditUnits(finance.bank.loans.single.outstandingPrincipalUnits), '500.00 C');
    expect(formatCreditUnits('900719925474099300'), '9007199254740993.00 C');
  });

  test('House identity preserves finance history across Human succession', () {
    final firstHuman = HouseFinanceOverview.fromJson({'houseId': 'HOUSE-1'});
    final successor = HouseFinanceOverview.fromJson({'houseId': 'HOUSE-1'});
    expect(firstHuman.houseId, successor.houseId);
  });

  test('historical and projected cashflow stay distinct', () {
    final finance = HouseFinanceOverview.fromJson({
      'cashflow': {
        'historical': {'netCashflowUnits': '1200'},
        'nextSettlement': {'netCashflowUnits': '-350'},
      },
    });
    expect(finance.cashflow.historical['netCashflowUnits'], '1200');
    expect(finance.cashflow.nextSettlement['netCashflowUnits'], '-350');
  });

  test('resource shortfall is not represented as a CREDIT obligation', () {
    final finance = HouseFinanceOverview.fromJson({
      'obligations': {
        'dailyNeeds': {'food_shortfall_units': '25'},
        'taxes': {'totalRemainingUnits': '0'},
      },
    });
    expect(finance.obligations.dailyNeeds['food_shortfall_units'], '25');
    expect(finance.obligations.taxes.totalRemainingUnits, BigInt.zero);
  });
}
