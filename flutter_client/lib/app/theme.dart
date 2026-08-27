import 'package:flutter/material.dart';
import '../core/ui_style_tokens.dart';

// Default static constants for backward compatibility
const violetColor = Color(0xff8b7cf6);
const inkColor = Color(0xfff1f5f9);
const canvasColor = Color(0xff070a12);
const surfaceColor = Color(0xff0d121f);
const mutedColor = Color(0xff94a3b8);
const cyanAccentColor = Color(0xff55d8b2);

/// Stable semantic colors for the six player resources.
/// Use these colors for resource icons and badges; keep numeric values neutral.
class EarthResourceColors {
  static const Color credits = Color(0xfff59e0b); // Gold credits (CRD)
  static const Color energy = Color(0xfffbbf24); // Solar amber (NRG)
  static const Color food = Color(0xff34d399); // Biosphere emerald (BIO)
  static const Color materials = Color(0xff94a3b8); // Slate titanium (ORE)
  static const Color components = Color(0xff38bdf8); // Sky components (MAT)
  static const Color compute = Color(0xff818cf8); // Quantum indigo (DAT)
}

/// Metadata and canonical definitions for the 6 core resources.
class EarthResourceMeta {
  final String key;
  final String shortCode;
  final String label;
  final String longName;
  final IconData icon;
  final Color color;

  const EarthResourceMeta({
    required this.key,
    required this.shortCode,
    required this.label,
    required this.longName,
    required this.icon,
    required this.color,
  });

  static const List<EarthResourceMeta> all = [
    EarthResourceMeta(
      key: 'credits',
      shortCode: 'CRD',
      label: 'Credits',
      longName: 'Universal Currency',
      icon: Icons.monetization_on_outlined,
      color: EarthResourceColors.credits,
    ),
    EarthResourceMeta(
      key: 'energy',
      shortCode: 'NRG',
      label: 'Energy',
      longName: 'Grid Power & Megawatts',
      icon: Icons.bolt_rounded,
      color: EarthResourceColors.energy,
    ),
    EarthResourceMeta(
      key: 'food',
      shortCode: 'BIO',
      label: 'Food',
      longName: 'Biomass & Agrifood',
      icon: Icons.eco_outlined,
      color: EarthResourceColors.food,
    ),
    EarthResourceMeta(
      key: 'material',
      shortCode: 'ORE',
      label: 'Materials',
      longName: 'Raw Minerals & Ores',
      icon: Icons.terrain_outlined,
      color: EarthResourceColors.materials,
    ),
    EarthResourceMeta(
      key: 'components',
      shortCode: 'MAT',
      label: 'Components',
      longName: 'Refined Alloys & Modules',
      icon: Icons.precision_manufacturing_outlined,
      color: EarthResourceColors.components,
    ),
    EarthResourceMeta(
      key: 'compute',
      shortCode: 'DAT',
      label: 'Compute',
      longName: 'Quantum Data & Telemetry',
      icon: Icons.memory_rounded,
      color: EarthResourceColors.compute,
    ),
  ];

  static EarthResourceMeta forCommodity(String key) {
    final normalized = key.toLowerCase().trim();
    return all.firstWhere(
      (m) =>
          m.key == normalized ||
          (normalized == 'materials' && m.key == 'material') ||
          m.shortCode.toLowerCase() == normalized,
      orElse: () => EarthResourceMeta(
        key: normalized,
        shortCode: normalized.length >= 3 ? normalized.substring(0, 3).toUpperCase() : normalized.toUpperCase(),
        label: normalized.toUpperCase(),
        longName: normalized.toUpperCase(),
        icon: Icons.category_outlined,
        color: EarthResourceColors.materials,
      ),
    );
  }
}

/// ThemeExtension to propagate dynamic surfaces, panels, cards, and accents throughout the UI.
class EarthThemeExtension extends ThemeExtension<EarthThemeExtension> {
  final Color primary;
  final Color secondary;
  final Color canvas;
  final Color surface;
  final Color panel;
  final Color card;
  final Color accent;
  final Color gold;

  const EarthThemeExtension({
    required this.primary,
    required this.secondary,
    required this.canvas,
    required this.surface,
    required this.panel,
    required this.card,
    required this.accent,
    required this.gold,
  });

  @override
  EarthThemeExtension copyWith({
    Color? primary,
    Color? secondary,
    Color? canvas,
    Color? surface,
    Color? panel,
    Color? card,
    Color? accent,
    Color? gold,
  }) {
    return EarthThemeExtension(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      panel: panel ?? this.panel,
      card: card ?? this.card,
      accent: accent ?? this.accent,
      gold: gold ?? this.gold,
    );
  }

  @override
  EarthThemeExtension lerp(ThemeExtension<EarthThemeExtension>? other, double t) {
    if (other is! EarthThemeExtension) return this;
    return EarthThemeExtension(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      secondary: Color.lerp(secondary, other.secondary, t) ?? secondary,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      panel: Color.lerp(panel, other.panel, t) ?? panel,
      card: Color.lerp(card, other.card, t) ?? card,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      gold: Color.lerp(gold, other.gold, t) ?? gold,
    );
  }
}

enum EarthThemeMode {
  zenithCyan(
    id: 'zenith_cyan',
    name: 'Zenith Ice Cyan',
    description:
        'Planetary Command & Tactical Interface with ice-cyan clarity and deep obsidian space.',
    primary: Color(0xff55d8b2),
    secondary: Color(0xff8b7cf6),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xff55d8b2),
    gold: Color(0xffeab308),
  ),
  solarGold(
    id: 'solar_gold',
    name: 'Sovereign Solar Gold',
    description:
        'Imperial solar gold and regal crimson for prestigious noble houses and high-stakes finance.',
    primary: Color(0xfff59e0b),
    secondary: Color(0xffe11d48),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xfffbbf24),
    gold: Color(0xfffbbf24),
  ),
  foundryCrimson(
    id: 'foundry_crimson',
    name: 'Foundry Magma Crimson',
    description:
        'Heavy industrial magma crimson and forge amber for blast furnaces and automated manufacturing.',
    primary: Color(0xffff4d4d),
    secondary: Color(0xfff97316),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xffff6b6b),
    gold: Color(0xfff59e0b),
  ),
  orbitalViolet(
    id: 'orbital_violet',
    name: 'Orbital Neon Synth',
    description:
        'Hyper-advanced cosmic violet and electric magenta synthwave for deep AI and transhumanism.',
    primary: Color(0xffa855f7),
    secondary: Color(0xffec4899),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xffc084fc),
    gold: Color(0xfffacc15),
  ),
  biosphereEmerald(
    id: 'biosphere_emerald',
    name: 'Biosphere Emerald',
    description:
        'Biotech vertical farm and hydroponic energy aesthetic with vibrant emerald and aqua.',
    primary: Color(0xff10b981),
    secondary: Color(0xff06b6d4),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xff34d399),
    gold: Color(0xffeab308),
  ),
  tacticalTitanium(
    id: 'tactical_titanium',
    name: 'Tactical Titanium Slate',
    description:
        'Ultra-clean titanium platinum and tactical sky-blue for zero-fatigue high-contrast command.',
    primary: Color(0xffe2e8f0),
    secondary: Color(0xff38bdf8),
    canvas: Color(0xff070a12),
    surface: Color(0xff0d121f),
    panel: Color(0xff111828),
    card: Color(0xff161f33),
    accent: Color(0xff38bdf8),
    gold: Color(0xfffacc15),
  );

  final String id;
  final String name;
  final String description;
  final Color primary;
  final Color secondary;
  final Color canvas;
  final Color surface;
  final Color panel;
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
    required this.panel,
    required this.card,
    required this.accent,
    required this.gold,
  });

  static EarthThemeMode fromId(String? id) {
    if (id == 'matrix_amber') return EarthThemeMode.foundryCrimson;
    if (id == 'midnight_emerald') return EarthThemeMode.biosphereEmerald;
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

ThemeData createEarthTheme([EarthThemeMode mode = EarthThemeMode.zenithCyan]) {
  final ext = EarthThemeExtension(
    primary: mode.primary,
    secondary: mode.secondary,
    canvas: mode.canvas,
    surface: mode.surface,
    panel: mode.panel,
    card: mode.card,
    accent: mode.accent,
    gold: mode.gold,
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: mode.canvas,
    canvasColor: mode.canvas,
    cardColor: mode.card,
    colorScheme: ColorScheme.fromSeed(
      seedColor: mode.secondary,
      primary: mode.primary,
      secondary: mode.secondary,
      brightness: Brightness.dark,
      surface: mode.surface,
    ),
    extensions: [ext],
      fontFamily: UiStyleTokens.current.value('font.family', 'Manrope'),
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
}
