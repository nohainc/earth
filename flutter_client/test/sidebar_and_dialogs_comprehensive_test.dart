import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/command_center/sidebar.dart';
import 'package:earth_client/features/governance/governance_dialogs.dart';
import 'package:earth_client/features/operations/technology_dialogs.dart';

void main() {
  testWidgets('Sidebar expands one category at a time and triggers onNavigate',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'life': {'houseName': 'House Vance'},
      'membership': {'corporation_id': 'CORP-001'},
      'institutions': {
        'corporation': {'name': 'Aether Dynamics'},
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

    // Default expanded group: COMMAND (0)
    expect(find.text('COMMAND'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Daily Briefing'), findsOneWidget);
    expect(find.text('News'), findsOneWidget);
    expect(find.text('Market'), findsNothing);

    // Expand ECONOMY
    await tester.tap(find.text('ECONOMY'));
    await tester.pumpAndSettle();
    expect(find.text('Buildings'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Technology'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);

    // Expand HOUSE
    await tester.tap(find.text('HOUSE'));
    await tester.pumpAndSettle();
    expect(find.text('Amara'), findsOneWidget);
    expect(find.text('Vance'), findsOneWidget);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Automation'), findsOneWidget);

    final financeButton = find.text('Finance');
    expect(financeButton, findsOneWidget);
    await tester.tap(financeButton);
    await tester.pumpAndSettle();
    expect(navigatedTo, 'finance');

    // Expand WORLD group
    final worldFinder = find.text('WORLD');
    expect(worldFinder, findsOneWidget);
    await tester.ensureVisible(worldFinder);
    await tester.tap(worldFinder);
    await tester.pumpAndSettle();
    expect(find.text('Conditions'), findsOneWidget);
    expect(find.text('Rankings'), findsOneWidget);
    expect(find.text('Initiatives'), findsOneWidget);
    expect(find.text('Constitution'), findsOneWidget);
    expect(find.text('Memorial'), findsOneWidget);

    final constitutionFinder = find.text('Constitution');
    await tester.ensureVisible(constitutionFinder);
    await tester.tap(constitutionFinder);
    await tester.pumpAndSettle();
    expect(navigatedTo, 'constitution');
  });

  testWidgets('Sidebar hides My Corporation when unaffiliated', (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'membership': {},
      'institutions': {},
      'business': {},
      'technology': {'research': {}},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 900,
            width: 250,
            child: Sidebar(
              state: state,
              selectedSection: 'command',
              onNavigate: (section) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SOCIETY'));
    await tester.pumpAndSettle();
    expect(find.text('My Corporation'), findsNothing);
    expect(find.text('Corporations'), findsOneWidget);
    expect(find.text('Territories'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(find.text('Governance'), findsOneWidget);
  });

  testWidgets(
      'Sidebar displays joined corporation in SOCIETY group when affiliated',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'membership': {'corporation_id': 'CORP-01'},
      'institutions': {
        'corporation': {'name': 'Aether Dynamics'},
      },
      'business': {},
      'technology': {'research': {}},
    });

    String? target;
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
                target = section;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('SOCIETY'));
    await tester.pumpAndSettle();
    expect(find.text('Aether Dynamics'), findsOneWidget);
    expect(find.text('Corporations'), findsOneWidget);
    expect(find.text('Territories'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(find.text('Governance'), findsOneWidget);

    await tester.tap(find.text('Aether Dynamics'));
    await tester.pumpAndSettle();
    expect(target, 'corporation');
  });

  testWidgets('Sidebar footer renders Account and triggers onNavigate',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'life': {'houseName': 'House Vance'},
      'membership': {},
      'institutions': {},
      'business': {},
      'technology': {'research': {}},
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

    final accountItem = find.text('Account');
    expect(accountItem, findsOneWidget);
    await tester.tap(accountItem);
    await tester.pumpAndSettle();

    expect(navigatedTo, 'account');
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
        find.widgetWithText(TextField, 'Initial budget (minimum 240 C)'),
        '500');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(started, true);
  });

  testWidgets('Sidebar renders in slim rail mode when isSlim is true',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 185, 'minute': 720},
      'human': {'name': 'Amara Vance'},
      'membership': {'corporation_id': 'CORP-001'},
      'institutions': {
        'corporation': {'name': 'Aether Dynamics'},
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
            width: 60,
            child: Sidebar(
              state: state,
              selectedSection: 'messages',
              isSlim: true,
              onNavigate: (section) {
                navigatedTo = section;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Group text headers should NOT be present in slim mode
    expect(find.text('COMMAND'), findsNothing);
    expect(find.text('ECONOMY'), findsNothing);

    // Tooltips with labels should be present
    expect(find.byTooltip('Overview'), findsOneWidget);
    expect(find.byTooltip('Market'), findsOneWidget);
    expect(find.byTooltip('Account'), findsOneWidget);

    // Tapping a slim icon triggers navigation
    await tester.tap(find.byTooltip('Market'));
    await tester.pumpAndSettle();

    expect(navigatedTo, 'market');
  });
}
