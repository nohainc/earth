import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/core/api/earth_api.dart';
import 'package:earth_client/core/api/earth_api_transport.dart';
import 'package:earth_client/features/world/initiatives_panel.dart';
import 'package:earth_client/shared/widgets/format_helpers.dart';

void main() {
  final api = EarthApi(transport: _InitiativeTransport());
  test(
      'initiative CREDIT values use atomic-unit formatting at the display boundary',
      () {
    expect(formatCreditUnits('50000'), '500.00 C');
    expect(formatCreditUnits('100'), '1.00 C');
  });

  testWidgets(
      'InitiativesPanel renders canonical filters and exact funding progress',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 100},
      'human': {'name': 'Test Citizen'},
      'publicProjects': {'projects': []},
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InitiativesPanel(
            state: state,
            personalFinanceData: const {},
            busy: false,
            action: (fn) async {},
            api: api,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('INITIATIVES'), findsWidgets);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('FUNDING'), findsWidgets);
    expect(find.text('MY SUPPORT'), findsOneWidget);
    expect(find.text('Fusion Grid'), findsOneWidget);
    expect(find.textContaining('FUNDING 50.00%'), findsOneWidget);
  });
}

class _InitiativeTransport extends EarthApiTransport {
  _InitiativeTransport() : super(baseUrl: 'http://initiative.test');

  @override
  Future<dynamic> request(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (path.startsWith('/api/initiatives')) {
      return {
        'initiatives': [
          {
            'id': 'INIT-1',
            'scope': {'type': 'EARTH'},
            'type': 'PROGRAM',
            'name': 'Fusion Grid',
            'description': 'Earth energy infrastructure',
            'status': 'FUNDING',
            'fundingTargetUnits': '100000',
            'communityContributionUnits': '50000',
            'matchCommittedUnits': '0',
            'matchAppliedUnits': '0',
            'treasuryCommittedUnits': '0',
            'fundingProgressBps': 5000,
            'supporterCount': 4,
            'deadlineGameDay': 200,
            'houseContributionUnits': '0',
            'outcomePreview': {'type': 'SERVICE_CAPACITY'},
            'execution': {'status': 'PENDING', 'progressBps': 0},
            'capabilities': {'canContribute': true, 'viewerHasSupport': false, 'canManageFunding': false, 'canSettle': false},
          }
        ],
        'summary': {'activeCount': 1, 'fundingCount': 1, 'completedCount': 0, 'communityCapitalUnits': '50000', 'supportingInitiativesCount': 0},
      };
    }
    return {'clock': {'day': 1}};
  }
}
