import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/governance/constitution_panel.dart';

void main() {
  testWidgets('ConstitutionPanel renders the two policy scopes and statutes',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185},
      'constitutionalRules': [
        {
          'id': 'CONST-TIME-001',
          'part_number': 1,
          'rule_number': '1.1',
          'category': 'TIME & SETTLEMENT',
          'title': 'Authoritative World Time',
          'description': 'The canonical World Clock governs settlement.',
          'default_value': 'World Clock',
          'permitted_values': 'Immutable',
          'authority': 'EARTH',
          'invariant': true,
        },
        {
          'id': 'CONST-AMEND-001',
          'part_number': 10,
          'rule_number': '10.1',
          'category': 'AMENDMENTS & CONSTITUTION',
          'title': 'Constitutional Amendment Supermajority',
          'description': 'Constitutional amendments require supermajority.',
          'default_value': '67%',
          'permitted_values': 'Planetary Referendum',
          'authority': 'EARTH',
          'invariant': true,
        },
      ],
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(state: state),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Core Header & Policy Scope Metrics
    expect(find.text('PLANETARY CONSTITUTION'), findsOneWidget);
    expect(find.text('EARTH'), findsWidgets);
    expect(find.text('CORPORATION'), findsWidgets);
    expect(find.text('2 Scopes'), findsOneWidget);
    expect(find.text('ORGANIZATION'), findsNothing);
    expect(find.text('TERRITORY'), findsNothing);

    // 2. Canonical Articles & Search
    expect(find.text('Authoritative World Time'), findsOneWidget);
    expect(find.text('Constitutional Amendment Supermajority'), findsOneWidget);
  });

  testWidgets('ConstitutionPanel can render a canonical typed policy snapshot',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185}
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(
            state: state,
            canonicalLoader: () async => {
              'ok': true,
              'gameDay': 185,
              'rules': {
                'EARTH.CAPACITY.BASE_RATE': '1000',
                'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': 'SCHEDULE-V1',
              },
              'versionIds': {
                'EARTH.CAPACITY.BASE_RATE': 'CONST-V1',
                'EARTH.CAPACITY.PROGRESSIVE_SCHEDULE': 'CONST-SCHEDULE-V1',
              },
              'scheduleBrackets': {
                'SCHEDULE-V1': [
                  {
                    'lower_bound_units': '0',
                    'upper_bound_units': '10',
                    'marginal_multiplier_numerator': '1',
                    'marginal_multiplier_denominator': '1',
                  },
                  {
                    'lower_bound_units': '10',
                    'marginal_multiplier_numerator': '2',
                    'marginal_multiplier_denominator': '1',
                  },
                ],
              },
              'history': [
                {
                  'rule_code': 'EARTH.CAPACITY.BASE_RATE',
                  'value_json': {'value': '1000'},
                  'effective_from_game_day': 1,
                  'status': 'ACTIVE',
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('EARTH.CAPACITY.BASE_RATE'), findsNWidgets(2));
    expect(find.text('1000 · CONST-V1'), findsOneWidget);
    expect(find.text('CONSTITUTION RULE HISTORY'), findsOneWidget);
    expect(find.textContaining('DAY 1 · ACTIVE'), findsOneWidget);
    expect(find.text('PROGRESSIVE BRACKETS'), findsOneWidget);
    expect(find.text('0–10 · ×1/1'), findsOneWidget);
  });

  testWidgets('groups canonical statutes by present articles only',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185}
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(
            state: state,
            canonicalLoader: () async => {
              'ok': true,
              'gameDay': 185,
              'ruleViews': [
                {
                  'code': 'EARTH.CAPACITY.BASE_RATE',
                  'articleCode': 'TERRITORY_CAPACITY',
                  'valueType': 'CREDIT_UNITS',
                  'authorityModel': 'EARTH_LOCKED',
                  'policyGroup': 'CAPACITY_POLICY',
                  'amendmentClass': 'POLICY',
                  'calculationKey': 'earth.capacity.base_rate',
                  'displayName': 'Base Rate',
                  'description': 'Capacity rule',
                  'allowedValues': [],
                  'resolved': {
                    'value': '1250',
                    'source': 'EARTH',
                    'versionId': 'v1',
                    'effectiveFromGameDay': 1,
                  },
                },
                {
                  'code': 'EARTH.GOVERNANCE.QUORUM_BPS',
                  'articleCode': 'EARTH_GOVERNANCE',
                  'valueType': 'RATE_BPS',
                  'authorityModel': 'EARTH_LOCKED',
                  'policyGroup': 'GOVERNANCE_POLICY',
                  'amendmentClass': 'POLICY',
                  'calculationKey': 'earth.governance.quorum_bps',
                  'displayName': 'Quorum',
                  'description': 'Governance rule',
                  'allowedValues': [],
                  'resolved': {
                    'value': '2500',
                    'source': 'EARTH',
                    'versionId': 'v2',
                    'effectiveFromGameDay': 1,
                  },
                },
              ],
              'rules': {},
              'definitions': [],
              'versionIds': {},
              'provenance': {},
              'scheduledChanges': [],
              'history': [],
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('CAPACITY & SCARCITY'), findsWidgets);
    expect(find.text('EARTH GOVERNANCE'), findsWidgets);
    expect(find.text('SUCCESSION'), findsNothing);
    expect(find.textContaining('PART '), findsNothing);
  });

  testWidgets(
      'shows Corporation inheritance and can propose returning to Earth',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185}
    });
    List<Map<String, dynamic>>? proposedChanges;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConstitutionPanel(
            state: state,
            onProposeAmendment: (changes) async {
              proposedChanges = changes;
              return {'ok': true};
            },
            canonicalLoader: () async => {
              'ok': true,
              'gameDay': 185,
              'corporationId': 'CORP-1',
              'ruleViews': [
                {
                  'code': 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS',
                  'articleCode': 'CORPORATION_GOVERNANCE',
                  'valueType': 'RATE_BPS',
                  'authorityModel': 'EARTH_DEFAULT_CORPORATION_OVERRIDE',
                  'policyGroup': 'GOVERNANCE_POLICY',
                  'amendmentClass': 'LOCAL_POLICY',
                  'calculationKey': 'corporation.governance.policy_quorum_bps',
                  'displayName': 'Policy Quorum',
                  'description': 'Corporation governance rule',
                  'allowedValues': [],
                  'resolved': {
                    'value': '3000',
                    'source': 'CORPORATION',
                    'versionId': 'corp-v1',
                    'effectiveFromGameDay': 180,
                  },
                  'earthDefault': {
                    'value': '2500',
                    'source': 'EARTH',
                    'versionId': 'earth-v1',
                    'effectiveFromGameDay': 1,
                  },
                  'inheritanceStatus': 'LOCAL_OVERRIDE',
                },
                {
                  'code': 'CORPORATION.GOVERNANCE.POLICY_APPROVAL_BPS',
                  'articleCode': 'CORPORATION_GOVERNANCE',
                  'valueType': 'RATE_BPS',
                  'authorityModel': 'EARTH_DEFAULT_CORPORATION_OVERRIDE',
                  'policyGroup': 'GOVERNANCE_POLICY',
                  'amendmentClass': 'LOCAL_POLICY',
                  'calculationKey':
                      'corporation.governance.policy_approval_bps',
                  'displayName': 'Policy Approval',
                  'description': 'Inherited governance rule',
                  'allowedValues': [],
                  'resolved': {
                    'value': '2500',
                    'source': 'EARTH',
                    'versionId': 'earth-v2',
                    'effectiveFromGameDay': 1,
                  },
                  'earthDefault': {
                    'value': '2500',
                    'source': 'EARTH',
                    'versionId': 'earth-v2',
                    'effectiveFromGameDay': 1,
                  },
                  'inheritanceStatus': 'INHERITED',
                },
              ],
              'rules': {},
              'definitions': [],
              'versionIds': {},
              'provenance': {},
              'scheduledChanges': [],
              'history': [],
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LOCAL OVERRIDE'), findsOneWidget);
    expect(find.text('INHERITED'), findsOneWidget);
    expect(find.text('EARTH DEFAULT'), findsWidgets);
    expect(find.text('RETURN TO EARTH DEFAULT'), findsOneWidget);

    await tester.ensureVisible(find.text('RETURN TO EARTH DEFAULT'));
    await tester.tap(find.text('RETURN TO EARTH DEFAULT'));
    await tester.pump();
    expect(proposedChanges, [
      {
        'ruleCode': 'CORPORATION.GOVERNANCE.POLICY_QUORUM_BPS',
        'clearOverride': true
      },
    ]);
  });
}
