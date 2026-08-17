import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/ai_panel.dart';

void main() {
  testWidgets('AiAssistantPanel renders tier, policy, and toggles policy',
      (tester) async {
    const state = EarthState({
      'clock': {'day': 184, 'minute': 100},
      'human': {'id': 'H-0044', 'credits': 5000},
      'world': {'health': 100},
      'resources': {},
      'business': {},
      'technology': {'research': {}},
      'institutions': {},
      'life': {},
      'governance': {},
      'market': {'orders': []},
      'aiAssistants': [
        {
          'id': 'AI-01',
          'tier': 'basic',
          'policy': 'recommend',
          'enabled': true,
        },
      ],
      'aiRecommendations': [
        {
          'priority': 'high',
          'message': 'Machine M-01 condition is 38%. Schedule maintenance.',
          'reason': 'Telemetry condition threshold < 40%',
        },
      ],
    });

    bool policyToggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                AiAssistantPanel(
                  state: state,
                  busy: false,
                  action: (cb) async {
                    policyToggled = true;
                  },
                ),
                const AiRecommendationsPanel(state: state),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('AI ASSISTANT / BOUNDED AUTOMATION'), findsOneWidget);
    expect(find.textContaining('BASIC AI ASSISTANT (AI-01)'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('POLICY: MAINTAIN'), findsOneWidget);

    // Verify info icon opens dialog
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bounded AI Assistants'), findsOneWidget);
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();

    expect(find.text('AI / EXPLAINABLE RECOMMENDATIONS'), findsOneWidget);
    expect(find.textContaining('Machine M-01 condition is 38%'), findsOneWidget);
    expect(find.textContaining('Source: Telemetry condition threshold < 40%'), findsOneWidget);

    await tester.tap(find.text('POLICY: MAINTAIN'));
    await tester.pumpAndSettle();

    expect(policyToggled, isTrue);
  });
}
