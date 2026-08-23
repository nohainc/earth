import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/audio/earth_audio_engine.dart';
import '../../shared/design_system/design_system.dart';

void showThemeCustomizerDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => const ThemeCustomizerDialog(),
  );
}

class ThemeCustomizerDialog extends StatefulWidget {
  const ThemeCustomizerDialog({super.key});

  @override
  State<ThemeCustomizerDialog> createState() => _ThemeCustomizerDialogState();
}

class _ThemeCustomizerDialogState extends State<ThemeCustomizerDialog> {
  Offset _windowOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: EarthThemeController.instance,
      builder: (dialogContext, _) {
        final currentMode = EarthThemeController.instance.mode;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Transform.translate(
            offset: _windowOffset,
            child: Container(
            width: 660,
            constraints: const BoxConstraints(maxHeight: 760),
            decoration: BoxDecoration(
              color: currentMode.panel,
              borderRadius: BorderRadius.circular(context.radiusPanel),
              border: Border.all(
                color: currentMode.primary.withValues(alpha: .35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: currentMode.primary.withValues(alpha: .15),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header — drag this area to move the window.
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() => _windowOffset += details.delta);
                  },
                  child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: currentMode.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(context.radiusPanel - 1)),
                    border: Border(bottom: BorderSide(color: currentMode.primary.withValues(alpha: .2))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.palette_outlined, color: currentMode.primary, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'COMMAND CENTER AESTHETICS & THEMES',
                                    style: TextStyle(
                                      color: currentMode.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1.2,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Select your preferred tactical interface palette & visual radiance.',
                                    style: TextStyle(color: context.mutedColor, fontSize: 11),
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
                        icon: Icon(Icons.close, color: context.mutedColor, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          EarthAudioEngine.instance.playClick();
                          Navigator.of(dialogContext).pop();
                        },
                      ),
                    ],
                  ),
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
                        borderRadius: BorderRadius.circular(context.radiusCard),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? themeMode.surface
                                : currentMode.surface.withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(context.radiusCard),
                            border: Border.all(
                              color: isSelected ? themeMode.primary : Colors.white12,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Interactive Mini Tactical UI Preview
                              Container(
                                width: 90,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: themeMode.canvas,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? themeMode.primary.withValues(alpha: .5)
                                        : Colors.white24,
                                  ),
                                ),
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: themeMode.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: themeMode.secondary.withValues(alpha: .25),
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                          child: Text(
                                            'LIVE',
                                            style: TextStyle(
                                              fontSize: 6,
                                              fontWeight: FontWeight.bold,
                                              color: themeMode.secondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: themeMode.panel,
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(color: themeMode.primary.withValues(alpha: .3)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            width: 24,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: themeMode.primary,
                                              borderRadius: BorderRadius.circular(1),
                                            ),
                                          ),
                                          Container(
                                            width: 12,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: themeMode.gold,
                                              borderRadius: BorderRadius.circular(1),
                                            ),
                                          ),
                                        ],
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
                                              color: themeMode.primary.withValues(alpha: .2),
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
                                      style: TextStyle(color: context.mutedColor, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              // Radio Indicator
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? themeMode.primary : context.mutedColor,
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
          ),
        );
      },
    );
  }
}
