import 'package:flutter/material.dart';
import '../core/ui_style_tokens.dart';
import '../features/auth/auth_gate.dart';
import '../shared/design_system/design_system.dart';
import 'theme.dart';

class EarthApp extends StatefulWidget {
  const EarthApp({super.key});

  @override
  State<EarthApp> createState() => _EarthAppState();
}

class _EarthAppState extends State<EarthApp> {
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Configure high-performance image cache budget
      PaintingBinding.instance.imageCache.maximumSize = 100;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50 MB
      for (final path in EarthBuildingMeta.getAllAssetPaths()) {
        precacheImage(
          AssetImage(path),
          context,
          size: const Size(256, 256),
        );
      }
    }
  }

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
