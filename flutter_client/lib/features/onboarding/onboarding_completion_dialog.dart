import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';

void showOnboardingCompletionDialog(BuildContext context) {
  EarthAudioEngine.instance.playCash();
  showDialog(
    context: context,
    builder: (context) => const OnboardingCompletionDialog(),
  );
}

class OnboardingCompletionDialog extends StatelessWidget {
  const OnboardingCompletionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 600,
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthThemeController.instance.goldMetallic, width: 2.0),
          boxShadow: [
            BoxShadow(
              color: EarthThemeController.instance.goldMetallic.withAlpha(60),
              blurRadius: 32,
              spreadRadius: 3,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: EarthThemeController.instance.goldMetallic.withAlpha(30),
                      shape: BoxShape.circle,
                      border: Border.all(color: EarthThemeController.instance.goldMetallic, width: 2),
                    ),
                    child: Icon(Icons.military_tech, color: EarthThemeController.instance.goldMetallic, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ORIENTATION PROTOCOL COMPLETE',
                    style: TextStyle(
                      color: EarthThemeController.instance.goldMetallic,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'PIONEER INDUCTION RATIFIED',
                    style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: .8),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                      'Congratulations, Pioneer. You have mastered the foundational pillars of the World: Planetary Chronometry, Macro Resource Economics, Municipal Governance, Spot Batch Auctions, Enterprise Formation, and Live Signal Dispatches.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: EarthColors.cardSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: EarthThemeController.instance.goldMetallic.withAlpha(100)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.workspace_premium_outlined, color: EarthThemeController.instance.goldMetallic, size: 20),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'AWARD: FOUNDING CITIZEN STIPEND',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                            Text(
                              '+500.00 CR Civic Orientation Bonus Credited',
                              style: TextStyle(color: EarthThemeController.instance.goldMetallic, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Action
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: FilledButton(
                key: const Key('btn-finish-onboarding'),
                onPressed: () {
                  EarthAudioEngine.instance.playClick();
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: EarthThemeController.instance.goldMetallic,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                child: const Text('ENTER PLANETARY COMMAND CENTER'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
