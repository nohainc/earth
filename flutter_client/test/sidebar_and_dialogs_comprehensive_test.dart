import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/sidebar.dart';
import 'package:earth_client/features/governance/governance_dialogs.dart';
import 'package:earth_client/features/operations/technology_dialogs.dart';

void main() {
  testWidgets('Sidebar renders all nav items and triggers onNavigate',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'institutions': {
        'city': {'name': 'New Kyoto'}
      },
      'business': {'name': 'Aether Dynamics'},
      'technology': {'research': {}},
      'technologyRegistry': {'activeProject': 'Quantum Grid'},
    });

    String? navigatedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            width: 250,
            child: Sidebar(
              state: state,
              selectedSection: 'command',
              onNavigate: (section) {
                navigatedTo = section;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('◌  EARTH'), findsOneWidget);
    expect(find.text('Amara Vance · New Kyoto'), findsOneWidget);

    final marketButton = find.text('Central Market');
    expect(marketButton, findsOneWidget);
    await tester.tap(marketButton);
    await tester.pumpAndSettle();

    expect(navigatedTo, 'market');
  });

  testWidgets('showProposalComposer validates length and submits proposal',
      (tester) async {
    bool submitted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showProposalComposer(
                context,
                (fn) async {
                  submitted = true;
                },
              ),
              child: const Text('Open Proposal Composer'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Proposal Composer'));
    await tester.pumpAndSettle();

    expect(find.text('Create UC proposal'), findsOneWidget);
    expect(find.text('Submit proposal'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Title (8–140 characters)'),
        'Municipal Solar Expansion');
    await tester.enterText(
        find.widgetWithText(TextField, 'Policy proposal (20–4000 characters)'),
        'Allocate credits from treasury to expand solar panel infrastructure in Sector 4.');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit proposal'));
    await tester.pumpAndSettle();

    expect(submitted, true);
  });

  testWidgets(
      'showResearchComposerDialog validates budget and submits research project',
      (tester) async {
    bool started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showResearchComposerDialog(
                context,
                (fn) async {
                  started = true;
                },
              ),
              child: const Text('Open Research Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Research Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Start Research Project'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Technology focus'), 'Fusion Cell');
    await tester.enterText(
        find.widgetWithText(TextField, 'Initial budget (minimum 240 C)'),
        '500');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(started, true);
  });

  testWidgets('showLicenseComposerDialog validates inputs and submits license',
      (tester) async {
    bool licensed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showLicenseComposerDialog(
                context,
                (fn) async {
                  licensed = true;
                },
              ),
              child: const Text('Open License Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open License Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('License technology'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Licensee Human ID'), 'H-0042');
    await tester.enterText(
        find.widgetWithText(TextField, 'License fee (minimum 50 C)'), '200');
    await tester.pumpAndSettle();

    await tester.tap(find.text('License'));
    await tester.pumpAndSettle();

    expect(licensed, true);
  });
}
