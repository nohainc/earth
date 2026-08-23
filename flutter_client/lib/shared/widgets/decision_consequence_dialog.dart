import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/models/decision_consequence.dart';
import '../../core/audio/earth_audio_engine.dart';
import 'consequence_preview_card.dart';

Future<bool?> showDecisionConsequenceDialog(
  BuildContext context, {
  required DecisionConsequence consequence,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => DecisionConsequenceDialog(consequence: consequence),
  );
}

class DecisionConsequenceDialog extends StatefulWidget {
  final DecisionConsequence consequence;

  const DecisionConsequenceDialog({
    super.key,
    required this.consequence,
  });

  @override
  State<DecisionConsequenceDialog> createState() => _DecisionConsequenceDialogState();
}

class _DecisionConsequenceDialogState extends State<DecisionConsequenceDialog> {
  final bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.consequence;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 640,
        decoration: BoxDecoration(
          color: EarthColors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(150), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: EarthThemeController.instance.primaryAccent.withAlpha(40),
              blurRadius: 28,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: EarthThemeController.instance.primaryAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EXECUTIVE IMPACT ASSESSMENT',
                          style: TextStyle(
                            color: EarthThemeController.instance.primaryAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const Text(
                          'Review downstream economic, operational, and systemic consequences before ratification.',
                          style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
            ),

            // Card Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: ConsequencePreviewCard(consequence: c),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: EarthColors.cardSurface,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
                border: Border(top: BorderSide(color: EarthColors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      EarthAudioEngine.instance.playClick();
                      Navigator.of(context).pop(false);
                    },
                    child: const Text('ABORT DECISION', style: TextStyle(color: EarthColors.textMuted, fontSize: 11)),
                  ),
                  FilledButton.icon(
                    key: const Key('btn-confirm-consequence-decision'),
                    onPressed: _confirming
                        ? null
                        : () {
                            EarthAudioEngine.instance.playClick();
                            Navigator.of(context).pop(true);
                          },
                    icon: const Icon(Icons.check_circle_outline, size: 15),
                    label: Text(c.confirmLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: EarthThemeController.instance.primaryAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
