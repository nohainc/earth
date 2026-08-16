import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';

void main() {
  late EarthApi api;
  final recordedCalls = <String>[];

  setUp(() {
    recordedCalls.clear();
    final client = MockClient((request) async {
      recordedCalls.add('${request.method} ${request.url.path}');
      final baseResponse = <String, dynamic>{
        'ok': true,
        'state': {
          'clock': {'day': 1},
          'world': {'id': 'WORLD'},
          'human': {'id': 'H-1', 'credits': 1000},
          'resources': {'energy': 10},
          'life': {'alive': true},
          'market': {'products': {}, 'orders': [], 'trades': [], 'book': []},
          'business': {'businesses': [], 'myShares': [], 'financials': {}},
          'governance': {'proposals': [], 'roles': []},
          'technology': {'research': {}},
          'institutions': {'communities': [], 'cities': [], 'corporations': []},
          'machines': [],
          'productionEvents': [],
          'aiAssistants': [],
          'aiRecommendations': [],
        },
        'events': [],
        'notifications': [],
        'sessions': [],
        'orders': [],
        'trades': [],
        'cities': [],
        'corporations': [],
        'communities': [],
        'rankings': [],
        'pantheon': [],
        'checks': {'balancesValid': true},
      };

      return http.Response(
        jsonEncode(baseResponse),
        200,
        headers: {'x-earth-api-version': '2026-08', 'content-type': 'application/json'},
      );
    });

    final transport = EarthApiTransport(baseUrl: 'https://earthuc.com', client: client);
    api = EarthApi(transport: transport);
  });

  test('Auth API endpoints execute expected HTTP calls', () async {
    await api.login('amara@earthuc.com', 'password123');
    await api.register('Amara Vance', 'amara@earthuc.com', 'password123');
    await api.logout();
    await api.enrollMfa();
    await api.confirmMfa('123456');
    await api.disableMfa('123456');
    await api.sessions();
    await api.revokeSession('sess-1');

    expect(recordedCalls.contains('POST /api/auth/login'), true);
    expect(recordedCalls.contains('POST /api/auth/register'), true);
    expect(recordedCalls.contains('POST /api/auth/logout'), true);
  });

  test('World & Simulation API endpoints execute expected HTTP calls', () async {
    await api.world();
    await api.events();
    await api.advanceDay();
    await api.rankings();
    await api.pantheon();
    await api.publicActivity();
    await api.ownershipEvents();
    await api.membershipEvents();
    await api.authorityEvents();
    await api.productionCatalog();
    await api.notifications();
    await api.markNotificationRead('notif-1');
    await api.markAllNotificationsRead();

    expect(recordedCalls.contains('GET /api/world'), true);
    expect(recordedCalls.contains('GET /api/events'), true);
    expect(recordedCalls.contains('POST /api/day/advance'), true);
    expect(recordedCalls.contains('GET /api/rankings'), true);
  });

  test('Business API endpoints execute expected HTTP calls', () async {
    await api.createBusiness('Solar Fab', 'energy');
    await api.appointBusinessManager('B-1', 'H-2');
    await api.liquidateBusiness('B-1', otp: '123456');
    await api.updateBusinessConstitution('B-1', 0.6, 0.6, 7);
    await api.transferShares('H-2', 10);
    await api.distributeDividends('B-1', 5000);
    await api.issueShares('B-1', 'H-2', 20, 100);
    await api.proposeMerger(acquirerBusinessId: 'B-1', targetBusinessId: 'B-2', pricePerShare: 150);
    await api.executeMerger('MERGER-1');

    expect(recordedCalls.contains('POST /api/businesses'), true);
    expect(recordedCalls.contains('POST /api/businesses/B-1/manager'), true);
    expect(recordedCalls.contains('POST /api/businesses/B-1/liquidate'), true);
    expect(recordedCalls.contains('POST /api/businesses/B-1/dividends'), true);
  });

  test('Contracts API endpoints execute expected HTTP calls', () async {
    await api.contracts();
    await api.contract('C-1');
    await api.createContract('strategic', 'H-2', 'Supply Contract', 500);
    await api.acceptContract('C-1');
    await api.cancelContract('C-1');
    await api.disputeContract('C-1', 'Failed delivery');
    await api.resolveContract('C-1', 'uphold', 'Terms verified');

    expect(recordedCalls.contains('POST /api/contracts'), true);
    expect(recordedCalls.contains('POST /api/contracts/C-1/accept'), true);
    expect(recordedCalls.contains('POST /api/contracts/C-1/cancel'), true);
    expect(recordedCalls.contains('POST /api/contracts/C-1/dispute'), true);
  });

  test('Governance & Institutions API endpoints execute expected HTTP calls', () async {
    await api.createProposal('Tax Reform', 'Adjust municipal tax charter to 2.5%');
    await api.vote('P-1', 'yes');
    await api.challengeProposal('P-1', 'Constitutional dispute');
    await api.resolveConstitutionalAppeal('P-1', 'uphold', 'Ruling upheld');
    await api.claimRole('ROLE-1');
    await api.resignRole('ROLE-1');
    await api.delegateRole('ROLE-1', 'H-3');

    await api.createCommunity();
    await api.joinCommunity('COM-1');
    await api.leaveCommunity('COM-1');
    await api.createCity('New Kyoto', 'COM-1');
    await api.setCityBudget('energy');
    await api.setCityTaxCharter(incomeTaxBps: 300, salesTaxBps: 200);
    await api.createCorporation('Aether Dyn', 'CITY-1');
    await api.joinCorporation();
    await api.leaveCorporation();

    expect(recordedCalls.contains('POST /api/governance/proposals'), true);
    expect(recordedCalls.contains('POST /api/governance/proposals/P-1/vote'), true);
    expect(recordedCalls.contains('POST /api/communities'), true);
    expect(recordedCalls.contains('POST /api/cities'), true);
  });

  test('Lifecycle, Machines, Market, Finance & Technology API endpoints execute expected HTTP calls', () async {
    await api.registerSuccessor('Kaelen Vance', successorHumanId: 'H-2', estatePeriodDays: 45);
    await api.settleInheritance(predecessorId: 'H-1', successorId: 'H-2', successorName: 'Kaelen');

    await api.acquireMachine('fabricator');
    await api.upgradeMachine('M-1', otp: '123456');
    await api.decommissionMachine('M-1', otp: '123456');
    await api.maintainMachine('M-1');
    await api.setMachineUtilization('M-1', 90);
    await api.sellMachine('M-1', 'H-2', 500);

    await api.submitOrder('energy', 1.25, side: 'buy', quantity: 100);
    await api.settleMarket('energy');
    await api.cancelOrder('ORD-1');
    await api.marketPriceHistory('energy');

    await api.personalFinance();
    await api.declareInsolvencyRestructuring(reason: 'Restructuring');
    await api.settlePersonalTax(1000);

    await api.startResearch('Hyperdrive', 1000);
    await api.fundResearch();
    await api.grantPatent();
    await api.licenseTechnology();
    await api.licenseTechnologyTo('H-2', 300, '123456');

    expect(recordedCalls.contains('POST /api/life/successor'), true);
    expect(recordedCalls.contains('POST /api/machines/acquire'), true);
    expect(recordedCalls.contains('POST /api/market/orders'), true);
    expect(recordedCalls.contains('DELETE /api/market/orders/ORD-1'), true);
    expect(recordedCalls.contains('POST /api/technology/projects'), true);
  });
}
