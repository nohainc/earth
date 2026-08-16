import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/earth_state.dart';
import 'package:earth_client/features/operations/ai_panel.dart';

void main() {
  testWidgets('AiAssistantPanel renders empty state when no assistant registered',
      (tester) async {
    const state = EarthState({
      'aiAssistants': <dynamic>[],
      'aiRecommendations': <dynamic>[],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiAssistantPanel(
            state: state,
            busy: false,
            action: (fn) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI ASSISTANT / BOUNDED AUTOMATION'), findsOneWidget);
    expect(find.text('No AI assistant is registered for this citizen.'),
        findsOneWidget);
  });

  testWidgets('AiAssistantPanel renders active assistant, tier, policy, and upgrades',
      (tester) async {
    const state = EarthState({
      'aiAssistants': [
        {
          'id': 'AI-001',
          'tier': 'basic',
          'policy': 'recommend',
          'enabled': true,
          'status': 'active',
        }
      ],
      'aiRecommendations': <dynamic>[],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiAssistantPanel(
              state: state,
              busy: false,
              action: (fn) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BASIC AI ASSISTANT (AI-001)'), findsOneWidget);
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('UPGRADE (2,400 C)'), findsOneWidget);
    expect(find.text('POLICY: RECOMMEND'), findsOneWidget);
  });

  testWidgets('showAiUpgradeDialog displays upgrade cost and submits action',
      (tester) async {
    bool upgraded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAiUpgradeDialog(
                context,
                (fn) async {
                  upgraded = true;
                },
                'AI-001',
              ),
              child: const Text('Upgrade AI'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Upgrade AI'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade to Business AI'), findsOneWidget);
    expect(find.text('Upgrade · 2,400 C'), findsOneWidget);

    await tester.tap(find.text('Upgrade · 2,400 C'));
    await tester.pumpAndSettle();

    expect(upgraded, true);
  });
}
