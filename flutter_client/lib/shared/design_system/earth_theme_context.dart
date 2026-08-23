import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/ui_style_tokens.dart';

/// Extension on [BuildContext] for ergonomic, consistent access to design tokens and dynamic theme colors.
extension EarthThemeContext on BuildContext {
  /// The active [UiStyleTokens] singleton.
  UiStyleTokens get tokens => UiStyleTokens.current;

  /// Dynamic EarthThemeExtension from active ThemeData if available.
  EarthThemeExtension? get themeExt => Theme.of(this).extension<EarthThemeExtension>();

  /// Dynamic primary theme color selected by the user.
  Color get primaryColor => themeExt?.primary ?? Theme.of(this).colorScheme.primary;

  /// Dynamic primary container / subtle tint.
  Color get primarySubtle => primaryColor.withValues(alpha: .15);

  /// Secondary accent color (e.g. violet / crimson / cyan).
  Color get secondaryColor => themeExt?.secondary ?? tokens.color('colors.secondary', violetColor);

  /// Main app background canvas color.
  Color get canvasColor => themeExt?.canvas ?? tokens.color('colors.canvas', const Color(0xFF0D121B));

  /// Base panel background color.
  Color get panelColor => themeExt?.panel ?? tokens.color('colors.panel', const Color(0xFF141A24));

  /// Elevated card surface background color.
  Color get surfaceColor => themeExt?.surface ?? tokens.color('colors.surface', const Color(0xFF1B2331));

  /// Card surface background color.
  Color get cardColor => themeExt?.card ?? surfaceColor;

  /// Gold accent color.
  Color get goldColor => themeExt?.gold ?? const Color(0xFFEAB308);

  /// Primary high-contrast text color.
  Color get inkColor => tokens.color('colors.ink', Colors.white);

  /// Secondary muted text / label color.
  Color get mutedColor => tokens.color('colors.muted', const Color(0xFF8B9BB4));

  /// Success / Positive / Live indicator color.
  Color get successColor => tokens.color('colors.success', const Color(0xFF10B981));

  /// Warning / Pending / Caution indicator color.
  Color get warningColor => tokens.color('colors.warning', const Color(0xFFF59E0B));

  /// Danger / Critical / Distress indicator color.
  Color get errorColor => tokens.color('colors.error', const Color(0xFFEF4444));

  /// Danger alias for semantic clarity.
  Color get dangerColor => errorColor;

  /// Standard subtle border color.
  Color get subtleBorderColor => Colors.white.withValues(alpha: 0.08);

  /// Primary theme accent tinted border.
  Color get themeBorderColor => primaryColor.withValues(alpha: .28);

  /// Spacing values from tokens.
  double get spacingPage => tokens.number('spacing.page', 24);
  double get spacingSection => tokens.number('spacing.section', 34);
  double get spacingTopic => tokens.number('spacing.topic', 16);
  double get spacingInline => tokens.number('spacing.inline', 8);
  double get spacingControl => tokens.number('spacing.control', 10);
  double get spacingTitleOffset => tokens.number('spacing.titleOffset', 12);
  double get spacingTitleGap => tokens.number('spacing.titleGap', 24);

  /// Radius values from tokens.
  double get radiusPanel => tokens.number('radius.panel', 14);
  double get radiusCard => tokens.number('radius.card', 10);
  double get radiusControl => tokens.number('radius.control', 6);

  /// Control heights.
  double get buttonHeight => tokens.number('controls.buttonHeight', 34);
  double get inputHeight => tokens.number('controls.inputHeight', 42);
  double get iconSize => tokens.number('controls.iconSize', 16);

  /// Card padding.
  double get cardPadding => tokens.number('pageTopics.cardPadding', 14);

  /// Standard Page Title Text Style.
  TextStyle get pageTitleStyle => TextStyle(
        color: primaryColor,
        fontSize: tokens.number('typography.pageTitle.size', 16),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.pageTitle.letterSpacing', 1.4),
      );

  /// Standard Topic / Section Header Text Style.
  TextStyle get topicTitleStyle => TextStyle(
        color: mutedColor,
        fontSize: tokens.number('typography.topicTitle.size', 12),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.topicTitle.letterSpacing', 1.4),
      );

  /// Standard Widget / Card Title Text Style.
  TextStyle get widgetTitleStyle => TextStyle(
        color: mutedColor,
        fontSize: tokens.number('typography.widgetTitle.size', 10),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.widgetTitle.letterSpacing', 1.4),
      );

  /// Standard Widget Value Text Style.
  TextStyle get widgetValueStyle => TextStyle(
        color: primaryColor,
        fontSize: tokens.number('typography.widgetValue.size', 12),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.widgetValue.letterSpacing', 1.4),
      );

  /// Standard Widget Footer / Subtitle Text Style.
  TextStyle get widgetFooterStyle => TextStyle(
        color: mutedColor,
        fontSize: tokens.number('typography.widgetFooter.size', 10),
        fontWeight: FontWeight.w400,
        letterSpacing: tokens.number('typography.widgetFooter.letterSpacing', 1.0),
      );

  /// Standard Body Text Style.
  TextStyle get bodyStyle => TextStyle(
        color: inkColor.withValues(alpha: .85),
        fontSize: tokens.number('typography.body.size', 10),
        fontWeight: FontWeight.w400,
        letterSpacing: tokens.number('typography.body.letterSpacing', 1.0),
      );

  /// Standard Button / Control Label Text Style.
  TextStyle get controlStyle => TextStyle(
        fontSize: tokens.number('typography.control.size', 10),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.control.letterSpacing', 1.4),
      );

  /// Standard Caption / Badge Text Style.
  TextStyle get captionStyle => TextStyle(
        fontSize: tokens.number('typography.caption.size', 8),
        fontWeight: FontWeight.w700,
        letterSpacing: tokens.number('typography.caption.letterSpacing', 1.4),
      );
}
