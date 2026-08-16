import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import 'theme.dart';

class EarthApp extends StatelessWidget {
  const EarthApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'EARTH — United Corporations',
        debugShowCheckedModeBanner: false,
        theme: createEarthTheme(),
        home: const AuthGate(),
      );
}
