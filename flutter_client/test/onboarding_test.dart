import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/core/models/onboarding_state.dart';
import 'package:earth_client/core/onboarding_controller.dart';
import 'package:earth_client/features/onboarding/onboarding_guidance_bar.dart';
import 'package:earth_client/features/onboarding/onboarding_welcome_dialog.dart';
import 'package:earth_client/features/onboarding/onboarding_completion_dialog.dart';

void main() {
  test('OnboardingController handles full 6-step lifecycle, skip, and reset', () {
    final ctrl = OnboardingController.instance;
    ctrl.reset();

    expect(ctrl.currentStepIndex, 0);
    expect(ctrl.currentStep.id, 'world_status');
    expect(ctrl.isCompleted, isFalse);
    expect(ctrl.isDismissed, isFalse);

    // Step 1 -> 2
    ctrl.completeStep('world_status');
    expect(ctrl.progress.completedStepIds.contains('world_status'), isTrue);
    expect(ctrl.currentStepIndex, 1);
    expect(ctrl.currentStep.id, 'personal_resources');

    // Next / Previous
    ctrl.nextStep();
    expect(ctrl.currentStepIndex, 2);
    ctrl.previousStep();
    expect(ctrl.currentStepIndex, 1);

    // Complete all remaining steps
    ctrl.completeStep('personal_resources');
    ctrl.completeStep('join_community');
    ctrl.completeStep('first_market_decision');
    ctrl.completeStep('start_enterprise');
    ctrl.completeStep('receive_consequence');

    expect(ctrl.isCompleted, isTrue);
    expect(ctrl.progress.completedStepIds.length, 6);

    // Dismiss & Reset
    ctrl.setDismissed(true);
    expect(ctrl.isDismissed, isTrue);
    ctrl.reset();
    expect(ctrl.isCompleted, isFalse);
    expect(ctrl.isDismissed, isFalse);
  });

  testWidgets('OnboardingGuidanceBar renders steps, expands/minimizes, and navigates', (tester) async {
    final ctrl = OnboardingController.instance;
    ctrl.reset();

    String? navigatedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingGuidanceBar(
            onNavigate: (section) => navigatedTo = section,
          ),
        ),
      ),
    );

    expect(find.text('ORIENTATION STEP 1 OF 6'), findsOneWidget);
    expect(find.text('READ WORLD STATUS'), findsOneWidget);
    expect(find.text('INSPECT WORLD METRICS'), findsOneWidget);

    // Minimize & Expand
    final minBtn = find.byKey(const Key('btn-onboarding-minimize'));
    expect(minBtn, findsOneWidget);
    await tester.tap(minBtn);
    await tester.pump();

    expect(find.textContaining('ORIENTATION: STEP 1/6'), findsOneWidget);

    final expandBtn = find.byKey(const Key('btn-onboarding-expand'));
    expect(expandBtn, findsOneWidget);
    await tester.tap(expandBtn);
    await tester.pump();

    expect(find.text('READ WORLD STATUS'), findsOneWidget);

    // Next step button
    final nextBtn = find.byKey(const Key('btn-onboarding-next'));
    expect(nextBtn, findsOneWidget);
    await tester.tap(nextBtn);
    await tester.pump();

    expect(find.text('REVIEW PERSONAL RESOURCES'), findsOneWidget);

    // Action button
    final actionBtn = find.byKey(const Key('btn-onboarding-action-personal_resources'));
    expect(actionBtn, findsOneWidget);
    await tester.tap(actionBtn);
    await tester.pump();

    expect(navigatedTo, 'net_worth');
    expect(ctrl.progress.completedStepIds.contains('personal_resources'), isTrue);

    // Dismiss
    final skipBtn = find.byKey(const Key('btn-onboarding-skip'));
    expect(skipBtn, findsOneWidget);
    await tester.tap(skipBtn);
    await tester.pump();

    expect(ctrl.isDismissed, isTrue);
    expect(find.text('ORIENTATION STEP 1 OF 6'), findsNothing);

    ctrl.reset();
  });

  testWidgets('OnboardingWelcomeDialog renders 6 step previews and starts orientation', (tester) async {
    final ctrl = OnboardingController.instance;
    ctrl.reset();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingWelcomeDialog(),
        ),
      ),
    );

    expect(find.text('ONBOARDING & OPERATIONS GUIDE'), findsOneWidget);
    expect(find.text('READ WORLD STATUS'), findsOneWidget);
    expect(find.text('REVIEW PERSONAL RESOURCES'), findsOneWidget);
    expect(find.text('JOIN OR INSPECT A COMMUNITY'), findsOneWidget);
    expect(find.text('MAKE FIRST MARKET DECISION'), findsOneWidget);
    expect(find.text('START BUSINESS OR RESEARCH'), findsOneWidget);
    expect(find.text('RECEIVE SIMULATION SIGNAL'), findsOneWidget);

    final startBtn = find.byKey(const Key('btn-start-orientation-tour'));
    expect(startBtn, findsOneWidget);
    await tester.tap(startBtn);
    await tester.pump();

    expect(ctrl.isDismissed, isFalse);
    expect(ctrl.currentStepIndex, 0);
  });

  testWidgets('OnboardingCompletionDialog renders graduation and stipend award', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OnboardingCompletionDialog(),
        ),
      ),
    );

    expect(find.text('ORIENTATION PROTOCOL COMPLETE'), findsOneWidget);
    expect(find.text('PIONEER INDUCTION RATIFIED'), findsOneWidget);
    expect(find.text('+500.00 CR Civic Orientation Bonus Credited'), findsOneWidget);
    expect(find.byKey(const Key('btn-finish-onboarding')), findsOneWidget);
  });
}
