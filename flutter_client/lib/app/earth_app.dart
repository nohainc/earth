import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import 'theme.dart';

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});

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
