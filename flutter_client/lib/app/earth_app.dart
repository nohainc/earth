import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import '../core/ui_style_tokens.dart';
import 'theme.dart';

class EarthApp extends StatefulWidget {
  const EarthApp({super.key});

  @override
  State<EarthApp> createState() => _EarthAppState();
}

class _EarthAppState extends State<EarthApp> {
  @override
  void reassemble() {
    super.reassemble();
    UiStyleTokens.reload().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: EarthThemeController.instance,
      builder: (context, _) => MaterialApp(
        title: 'EARTH — United Corporations',
        debugShowCheckedModeBanner: false,
        theme: createEarthTheme(EarthThemeController.instance.mode),
        home: const AuthGate(),
      ),
    );
}
