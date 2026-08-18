import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';

void showThemeCustomizerDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const ThemeCustomizerDialog(),
  );
}

class ThemeCustomizerDialog extends StatelessWidget {
  const ThemeCustomizerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EarthThemeController.instance,
      builder: (context, _) {
        final currentMode = EarthThemeController.instance.mode;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 700),
            decoration: BoxDecoration(
              color: EarthColors.panelSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: EarthThemeController.instance.primaryAccent.withAlpha(100), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: EarthThemeController.instance.primaryAccent.withAlpha(40),
                  blurRadius: 24,
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
                  decoration: BoxDecoration(
                    color: EarthColors.cardSurface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                    border: const Border(bottom: BorderSide(color: EarthColors.borderSubtle)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.palette_outlined, color: EarthThemeController.instance.primaryAccent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'COMMAND CENTER AESTHETICS & THEMES',
                                    style: TextStyle(
                                      color: EarthThemeController.instance.primaryAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      letterSpacing: 1.1,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Text(
                                    'Select your preferred tactical interface palette & visual radiance.',
                                    style: TextStyle(color: EarthColors.textMuted, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: EarthColors.textMuted, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          EarthAudioEngine.instance.playClick();
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),

                // Theme Options List
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    itemCount: EarthThemeMode.values.length,
                    itemBuilder: (context, index) {
                      final themeMode = EarthThemeMode.values[index];
                      final isSelected = themeMode == currentMode;

                      return InkWell(
                        key: Key('theme-item-${themeMode.id}'),
                        onTap: () {
                          EarthAudioEngine.instance.playChime();
                          EarthThemeController.instance.setMode(themeMode);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? themeMode.primary.withAlpha(25)
                                : EarthColors.cardSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? themeMode.primary : EarthColors.borderSubtle,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Palette Preview Swatches
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: themeMode.canvas,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white24),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: themeMode.primary,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: themeMode.secondary,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: themeMode.surface,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Description & Title
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          themeMode.name,
                                          style: TextStyle(
                                            color: isSelected ? themeMode.primary : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (isSelected) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: themeMode.primary.withAlpha(40),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: themeMode.primary),
                                            ),
                                            child: Text(
                                              'ACTIVE',
                                              style: TextStyle(
                                                color: themeMode.primary,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: .6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      themeMode.description,
                                      style: const TextStyle(color: EarthColors.textMuted, fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),

                              // Radio Indicator
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? themeMode.primary : EarthColors.textMuted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
