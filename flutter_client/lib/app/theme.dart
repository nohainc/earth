import 'package:flutter/material.dart';

const violetColor = Color(0xff8b7cf6);
const inkColor = Color(0xfff1f0ff);
const canvasColor = Color(0xff111327);
const surfaceColor = Color(0xff1b1e38);
const mutedColor = Color(0xff9698b5);
const cyanAccentColor = Color(0xff55d8b2);

ThemeData createEarthTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvasColor,
      canvasColor: canvasColor,
      cardColor: surfaceColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: violetColor,
        brightness: Brightness.dark,
        surface: surfaceColor,
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
        color: surfaceColor.withValues(alpha: .72),
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
