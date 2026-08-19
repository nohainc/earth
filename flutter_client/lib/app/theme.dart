import 'package:flutter/material.dart';

// Default static constants for backward compatibility
const violetColor = Color(0xff8b7cf6);
const inkColor = Color(0xfff1f0ff);
const canvasColor = Color(0xff111327);
const surfaceColor = Color(0xff1b1e38);
const mutedColor = Color(0xff9698b5);
const cyanAccentColor = Color(0xff55d8b2);

/// Stable semantic colors for the six player resources.
/// Use these colors for resource icons; keep numeric values neutral.
class EarthResourceColors {
  static const Color credits = Color(0xffa78bfa);
  static const Color food = Color(0xff86efac);
  static const Color energy = Color(0xfffbbf24);
  static const Color materials = Color(0xffd6a15d);
  static const Color components = Color(0xff38bdf8);
  static const Color compute = Color(0xffc084fc);
}

enum EarthThemeMode {
  zenithCyan(
    id: 'zenith_cyan',
    name: 'Zenith Ice Cyan',
    description:
        'High-clarity tactical cybernetic palette with ice-cyan primary & deep space canvas.',
    primary: Color(0xff55d8b2),
    secondary: Color(0xff8b7cf6),
    canvas: Color(0xff111327),
    surface: Color(0xff1b1e38),
    card: Color(0xff222646),
    accent: Color(0xff55d8b2),
    gold: Color(0xffeab308),
  ),
  solarGold(
    id: 'solar_gold',
    name: 'Deep Solar Gold',
    description:
        'Imperial solar gold accents for prestigious dynasties and high-stakes finance.',
    primary: Color(0xfff59e0b),
    secondary: Color(0xfffbbf24),
    canvas: Color(0xff0f0e0c),
    surface: Color(0xff1c1917),
    card: Color(0xff292524),
    accent: Color(0xfffbbf24),
    gold: Color(0xfffbbf24),
  ),
  matrixAmber(
    id: 'matrix_amber',
    name: 'Matrix Phosphor Amber',
    description:
        'Retro-futuristic tactical terminal palette with CRT phosphor amber radiance.',
    primary: Color(0xffffb300),
    secondary: Color(0xffff8f00),
    canvas: Color(0xff0d0f0c),
    surface: Color(0xff181a17),
    card: Color(0xff242722),
    accent: Color(0xffffca28),
    gold: Color(0xffffb300),
  ),
  orbitalViolet(
    id: 'orbital_violet',
    name: 'Orbital Neon Synth',
    description:
        'Hyper-advanced deep violet and electric purple synthwave void.',
    primary: Color(0xffa855f7),
    secondary: Color(0xffec4899),
    canvas: Color(0xff0e0b1f),
    surface: Color(0xff1a1438),
    card: Color(0xff271e54),
    accent: Color(0xffc084fc),
    gold: Color(0xfffacc15),
  ),
  midnightEmerald(
    id: 'midnight_emerald',
    name: 'Midnight Biotech Emerald',
    description:
        'Biotech vertical farm and hydroponic energy aesthetic with emerald luster.',
    primary: Color(0xff10b981),
    secondary: Color(0xff06b6d4),
    canvas: Color(0xff091410),
    surface: Color(0xff12231c),
    card: Color(0xff1b3329),
    accent: Color(0xff34d399),
    gold: Color(0xffeab308),
  );

  final String id;
  final String name;
  final String description;
  final Color primary;
  final Color secondary;
  final Color canvas;
  final Color surface;
  final Color card;
  final Color accent;
  final Color gold;

  const EarthThemeMode({
    required this.id,
    required this.name,
    required this.description,
    required this.primary,
    required this.secondary,
    required this.canvas,
    required this.surface,
    required this.card,
    required this.accent,
    required this.gold,
  });

  static EarthThemeMode fromId(String? id) {
    return EarthThemeMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => EarthThemeMode.zenithCyan,
    );
  }
}

class EarthThemeController extends ChangeNotifier {
  static final EarthThemeController instance = EarthThemeController._internal();

  EarthThemeController._internal();

  EarthThemeMode _mode = EarthThemeMode.zenithCyan;

  EarthThemeMode get mode => _mode;

  Color get primaryAccent => _mode.primary;
  Color get secondaryAccent => _mode.secondary;
  Color get canvas => _mode.canvas;
  Color get panelSurface => _mode.surface;
  Color get cardSurface => _mode.card;
  Color get accent => _mode.accent;
  Color get goldMetallic => _mode.gold;
  Color get textMuted => mutedColor;
  Color get borderSubtle => Colors.white12;

  void setMode(EarthThemeMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
  }
}

class EarthColors {
  static const Color panelSurface = surfaceColor;
  static const Color cardSurface = Color(0xff222646);
  static const Color borderSubtle = Colors.white12;
  static const Color goldMetallic = Color(0xffeab308);
  static const Color cyanAccent = cyanAccentColor;
  static const Color textMuted = mutedColor;
}

/// Shared typography tokens for navigation and popup menus.
class EarthTypography {
  static const TextStyle menu = TextStyle(
    fontSize: 13,
    letterSpacing: 0.7,
    fontWeight: FontWeight.w500,
    color: mutedColor,
  );

  static const TextStyle menuGroup = TextStyle(
    fontSize: 8.5,
    letterSpacing: 1.3,
    fontWeight: FontWeight.w700,
    color: mutedColor,
  );
}

ThemeData createEarthTheme([EarthThemeMode mode = EarthThemeMode.zenithCyan]) =>
    ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: mode.canvas,
      canvasColor: mode.canvas,
      cardColor: mode.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: mode.secondary,
        primary: mode.primary,
        secondary: mode.secondary,
        brightness: Brightness.dark,
        surface: mode.surface,
      ),
      fontFamily: 'Manrope',
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: inkColor,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: mode.surface.withValues(alpha: .72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white12),
        ),
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: inkColor,
            displayColor: inkColor,
          ),
    );
