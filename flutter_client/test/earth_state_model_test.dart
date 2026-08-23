import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';

void main() {
  test('EarthState getters return non-null typed fields and default fallbacks', () {
    const raw = {
      'clock': {'day': 10, 'minute': 20},
      'human': {'id': 'H-1', 'credits': 100},
      'world': {'health': 100},
      'resources': {'food': 50},
      'business': {'id': 'B-1'},
      'technology': {
        'research': {'eff': 1},
      },
      'governance': {'active': []},
      'institutions': {'city': {}},
      'life': {'vitality': 90},
      'machines': [{'id': 'M-1'}],
      'productionEvents': [{'type': 'produced'}],
      'aiAssistants': [{'type': 'maintenance'}],
      'aiRecommendations': [{'text': 'Optimize'}],
      'market': {
        'products': {'food': 10.0},
        'book': [{'price': 10}],
        'trades': [{'price': 10}],
        'orders': [{'orderId': 'O-1'}],
        'feeRate': 0.01,
      },
      'communities': [{'name': 'Solaris'}],
      'audit': {'ok': true},
      'finance': {'m0': 1000},
      'ledgerEntries': [{'id': 'L-1'}],
      'publicActivity': [{'title': 'Event'}],
      'opportunities': [{'id': 'OP-1'}],
      'rankings': {'cities': []},
      'history': {'events': []},
      'financeStatus': [{'id': 'FS-1'}],
      'personalFinance': {'tax': 10},
      'contracts': [{'id': 'C-1'}],
      'roles': ['founder'],
      'membership': {'city_id': 'CITY-1'},
    };

    final state = const EarthState(raw);

    expect(state.clock['day'], 10);
    expect(state.human['id'], 'H-1');
    expect(state.world['health'], 100);
    expect(state.resources['food'], 50);
    expect(state.business['id'], 'B-1');
    expect(state.technology['eff'], 1);
    expect(state.technologyRegistry['research']['eff'], 1);
    expect(state.governance['active'], isEmpty);
    expect(state.institutions['city'], isNotNull);
    expect(state.life['vitality'], 90);
    expect(state.machines.length, 1);
    expect(state.productionEvents.length, 1);
    expect(state.aiAssistants.length, 1);
    expect(state.aiRecommendations.length, 1);
    expect(state.market['food'], 10.0);
    expect(state.marketBook.length, 1);
    expect(state.marketTrades.length, 1);
    expect(state.marketOrders.length, 1);
    expect(state.marketFeeRate, 0.01);
    expect(state.communities.length, 1);
    expect(state.audit['ok'], isTrue);
    expect(state.finance['m0'], 1000);
    expect(state.ledgerEntries.length, 1);
    expect(state.publicActivity.length, 1);
    expect(state.opportunities.length, 1);
    expect(state.rankings['cities'], isEmpty);
    expect(state.history['events'], isEmpty);
    expect(state.financeStatus.length, 1);
    expect(state.personalFinance['tax'], 10);
    expect(state.contracts.length, 1);
    expect(state.roles.first, 'founder');
    expect(state.membership?['city_id'], 'CITY-1');
  });
}
