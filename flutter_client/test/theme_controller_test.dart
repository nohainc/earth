import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/features/command_center/theme_customizer_dialog.dart';

void main() {
  test('EarthThemeController sets and switches all 5 theme modes correctly', () {
    final controller = EarthThemeController.instance;

    controller.setMode(EarthThemeMode.solarGold);
    expect(controller.mode, EarthThemeMode.solarGold);
    expect(controller.primaryAccent, const Color(0xfff59e0b));

    controller.setMode(EarthThemeMode.matrixAmber);
    expect(controller.mode, EarthThemeMode.matrixAmber);
    expect(controller.primaryAccent, const Color(0xffffb300));

    controller.setMode(EarthThemeMode.orbitalViolet);
    expect(controller.mode, EarthThemeMode.orbitalViolet);
    expect(controller.primaryAccent, const Color(0xffa855f7));

    controller.setMode(EarthThemeMode.midnightEmerald);
    expect(controller.mode, EarthThemeMode.midnightEmerald);
    expect(controller.primaryAccent, const Color(0xff10b981));

    controller.setMode(EarthThemeMode.zenithCyan);
    expect(controller.mode, EarthThemeMode.zenithCyan);
    expect(controller.primaryAccent, const Color(0xff55d8b2));

    expect(EarthThemeMode.fromId('solar_gold'), EarthThemeMode.solarGold);
    expect(EarthThemeMode.fromId('unknown_invalid'), EarthThemeMode.zenithCyan);
  });

  testWidgets('ThemeCustomizerDialog renders all themes and allows selection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThemeCustomizerDialog(),
        ),
      ),
    );

    expect(find.text('COMMAND CENTER AESTHETICS & THEMES'), findsOneWidget);
    expect(find.text('Zenith Ice Cyan'), findsOneWidget);
    expect(find.text('Deep Solar Gold'), findsOneWidget);
    expect(find.text('Matrix Phosphor Amber'), findsOneWidget);
    expect(find.text('Orbital Neon Synth'), findsOneWidget);
    expect(find.text('Midnight Biotech Emerald'), findsOneWidget);

    // Select Deep Solar Gold
    final solarCard = find.byKey(const Key('theme-item-solar_gold'));
    expect(solarCard, findsOneWidget);
    await tester.tap(solarCard);
    await tester.pump();

    expect(EarthThemeController.instance.mode, EarthThemeMode.solarGold);
    expect(find.text('ACTIVE'), findsOneWidget);

    // Reset back to zenithCyan for other tests
    EarthThemeController.instance.setMode(EarthThemeMode.zenithCyan);
  });
}
