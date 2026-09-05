import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

enum EarthButtonVariant {
  primary,
  secondary,
  danger,
  warning,
  ghost,
  neutral,
}

/// Standardized action button conforming strictly to design tokens.
class EarthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final EarthButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final double? height;
  final Key? buttonKey;

  const EarthButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = EarthButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.height,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final activeHeight = height ?? context.buttonHeight;
    final isEnabled = onPressed != null && !isLoading;

    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case EarthButtonVariant.primary:
        bg = isEnabled ? context.primaryColor : Colors.grey[800]!;
        fg = isEnabled ? context.canvasColor : Colors.white38;
        break;
      case EarthButtonVariant.secondary:
        bg = context.surfaceColor;
        fg = isEnabled ? context.primaryColor : Colors.white38;
        border = BorderSide(color: context.primaryColor.withValues(alpha: .5));
        break;
      case EarthButtonVariant.danger:
        bg = isEnabled ? context.errorColor : Colors.grey[800]!;
        fg = Colors.white;
        break;
      case EarthButtonVariant.warning:
        bg = isEnabled ? context.warningColor : Colors.grey[800]!;
        fg = Colors.black;
        break;
      case EarthButtonVariant.ghost:
        bg = Colors.transparent;
        fg = isEnabled ? context.mutedColor : Colors.white38;
        break;
      case EarthButtonVariant.neutral:
        bg = context.surfaceColor;
        fg = isEnabled ? context.inkColor : Colors.white38;
        border = BorderSide(color: context.subtleBorderColor);
        break;
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: fg,
            ),
          ),
          SizedBox(width: context.spacingInline),
        ] else if (icon != null) ...[
          Icon(icon, size: context.iconSize - 2, color: fg),
          SizedBox(width: context.spacingInline),
        ],
        Text(
          label,
          style: context.controlStyle.copyWith(color: fg),
        ),
      ],
    );

    if (variant == EarthButtonVariant.ghost) {
      return SizedBox(
        height: activeHeight,
        child: TextButton(
          key: buttonKey,
          onPressed: isEnabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: fg,
            padding: EdgeInsets.symmetric(horizontal: context.spacingControl, vertical: 0),
          ),
          child: content,
        ),
      );
    }

    if (variant == EarthButtonVariant.secondary || variant == EarthButtonVariant.neutral) {
      return SizedBox(
        height: activeHeight,
        child: OutlinedButton(
          key: buttonKey,
          onPressed: isEnabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            side: border ?? BorderSide(color: context.subtleBorderColor),
            padding: EdgeInsets.symmetric(horizontal: context.spacingControl, vertical: 0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.radiusControl),
            ),
          ),
          child: content,
        ),
      );
    }

    return SizedBox(
      height: activeHeight,
      child: FilledButton(
        key: buttonKey,
        onPressed: isEnabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: context.spacingControl,
            vertical: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radiusControl),
            side: border ?? BorderSide.none,
          ),
        ),
        child: content,
      ),
    );
  }
}

/// Standardized search & text input control conforming to height 42px and token radius.
class EarthSearchInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final VoidCallback? onClear;
  final double? fontSize;
  final FocusNode? focusNode;
  final bool autofocus;

  const EarthSearchInput({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Search...',
    this.onClear,
    this.fontSize,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = context.bodyStyle.copyWith(
      color: context.inkColor,
      fontSize: fontSize,
    );
    final effectiveHintStyle = context.widgetFooterStyle.copyWith(
      fontSize: fontSize,
    );

    return Container(
      height: context.inputHeight,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(context.radiusControl),
        border: Border.all(color: context.subtleBorderColor),
      ),
      child: Semantics(
        textField: true,
        label: hintText,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          onChanged: onChanged,
          style: effectiveStyle,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: effectiveHintStyle,
            prefixIcon: Icon(Icons.search, size: 16, color: context.mutedColor),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close, size: 14, color: context.mutedColor),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      controller.clear();
                      onClear?.call();
                      onChanged?.call('');
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          ),
        ),
      ),
    );
  }
}
