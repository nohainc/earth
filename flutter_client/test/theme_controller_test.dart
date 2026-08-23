import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:earth_client/app/theme.dart';
import 'package:earth_client/features/command_center/theme_customizer_dialog.dart';

void main() {
  test('EarthThemeController sets and switches all 6 theme modes correctly', () {
    final controller = EarthThemeController.instance;

    controller.setMode(EarthThemeMode.solarGold);
    expect(controller.mode, EarthThemeMode.solarGold);
    expect(controller.primaryAccent, const Color(0xfff59e0b));

    controller.setMode(EarthThemeMode.foundryCrimson);
    expect(controller.mode, EarthThemeMode.foundryCrimson);
    expect(controller.primaryAccent, const Color(0xffff4d4d));

    controller.setMode(EarthThemeMode.orbitalViolet);
    expect(controller.mode, EarthThemeMode.orbitalViolet);
    expect(controller.primaryAccent, const Color(0xffa855f7));

    controller.setMode(EarthThemeMode.biosphereEmerald);
    expect(controller.mode, EarthThemeMode.biosphereEmerald);
    expect(controller.primaryAccent, const Color(0xff10b981));

    controller.setMode(EarthThemeMode.tacticalTitanium);
    expect(controller.mode, EarthThemeMode.tacticalTitanium);
    expect(controller.primaryAccent, const Color(0xffe2e8f0));

    controller.setMode(EarthThemeMode.zenithCyan);
    expect(controller.mode, EarthThemeMode.zenithCyan);
    expect(controller.primaryAccent, const Color(0xff55d8b2));

    expect(EarthThemeMode.fromId('solar_gold'), EarthThemeMode.solarGold);
    expect(EarthThemeMode.fromId('matrix_amber'), EarthThemeMode.foundryCrimson);
    expect(EarthThemeMode.fromId('unknown_invalid'), EarthThemeMode.zenithCyan);
  });

  testWidgets('ThemeCustomizerDialog renders all themes and allows selection', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThemeCustomizerDialog(),
        ),
      ),
    );

    expect(find.text('COMMAND CENTER AESTHETICS & THEMES'), findsOneWidget);
    expect(find.text('Zenith Ice Cyan'), findsOneWidget);
    expect(find.text('Sovereign Solar Gold'), findsOneWidget);
    expect(find.text('Foundry Magma Crimson'), findsOneWidget);
    expect(find.text('Orbital Neon Synth'), findsOneWidget);
    expect(find.text('Biosphere Emerald'), findsOneWidget);
    expect(find.text('Tactical Titanium Slate'), findsOneWidget);

    // Select Sovereign Solar Gold
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
