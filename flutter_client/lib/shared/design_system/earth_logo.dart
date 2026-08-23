import 'package:flutter/material.dart';
import 'earth_theme_context.dart';

/// Bespoke vector logo widget for EARTH: United Corporations.
/// Renders the United Quadrant Crest: 4 interlocking corporate chevrons
/// framing the Earth globe with continental trade network nodes.
class EarthLogo extends StatelessWidget {
  final double size;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? accentColor;
  final bool showGlow;

  const EarthLogo({
    super.key,
    this.size = 28.0,
    this.primaryColor,
    this.secondaryColor,
    this.accentColor,
    this.showGlow = true,
  });

  /// Exports an SVG string representation configured with the active theme colors.
  static String generateSvg({
    required Color primaryColor,
    required Color secondaryColor,
    Color accentColor = const Color(0xFFFFB300),
    Color backgroundColor = const Color(0xFF070A14),
  }) {
    final primHex = _colorToHex(primaryColor);
    final secHex = _colorToHex(secondaryColor);
    final accHex = _colorToHex(accentColor);
    final bgHex = _colorToHex(backgroundColor);

    return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="100%" height="100%">
  <defs>
    <linearGradient id="nexusGold" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="$accHex" stop-opacity="1" />
      <stop offset="100%" stop-color="$secHex" stop-opacity="0.9" />
    </linearGradient>
    <linearGradient id="nexusCyan" x1="0%" y1="100%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="$primHex" stop-opacity="1" />
      <stop offset="100%" stop-color="$secHex" stop-opacity="0.85" />
    </linearGradient>
    <radialGradient id="planetCore" cx="38%" cy="32%" r="68%">
      <stop offset="0%" stop-color="$primHex" stop-opacity="0.95" />
      <stop offset="55%" stop-color="$secHex" stop-opacity="0.65" />
      <stop offset="100%" stop-color="$bgHex" stop-opacity="1" />
    </radialGradient>
  </defs>
  <circle cx="256" cy="256" r="230" fill="$primHex" opacity="0.12" />
  <path d="M 256,26 L 360,130 L 330,130 L 256,56 L 182,130 L 152,130 Z" fill="url(#nexusGold)" />
  <path d="M 256,486 L 360,382 L 330,382 L 256,456 L 182,382 L 152,382 Z" fill="url(#nexusGold)" />
  <path d="M 486,256 L 382,152 L 382,182 L 456,256 L 382,330 L 382,360 Z" fill="url(#nexusCyan)" />
  <path d="M 26,256 L 130,152 L 130,182 L 56,256 L 130,330 L 130,360 Z" fill="url(#nexusCyan)" />
  <circle cx="256" cy="256" r="148" fill="url(#planetCore)" />
  <circle cx="256" cy="256" r="148" fill="none" stroke="url(#nexusCyan)" stroke-width="4.5" />
</svg>
''';
  }

  static String _colorToHex(Color color) {
    return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final effectivePrimary = primaryColor ?? context.primaryColor;
    final effectiveSecondary = secondaryColor ?? context.secondaryColor;
    final effectiveAccent = accentColor ?? context.goldColor;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _UnitedQuadrantCrestPainter(
          primaryColor: effectivePrimary,
          secondaryColor: effectiveSecondary,
          accentColor: effectiveAccent,
          showGlow: showGlow,
        ),
      ),
    );
  }
}

class _UnitedQuadrantCrestPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final bool showGlow;

  _UnitedQuadrantCrestPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.showGlow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Atmospheric Ambient Glow
    if (showGlow) {
      final glowPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.32)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.48);
      canvas.drawCircle(center, radius * 0.78, glowPaint);
    }

    // 2. The 4 Interlocking Corporate Quadrant Chevrons
    final chevronGoldPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          accentColor.withValues(alpha: 0.95),
          secondaryColor,
          accentColor.withValues(alpha: 0.85),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final chevronCyanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          primaryColor,
          secondaryColor.withValues(alpha: 0.9),
          primaryColor.withValues(alpha: 0.85),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final chevronStrokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.02).clamp(0.6, 1.6)
      ..strokeJoin = StrokeJoin.round;

    final outerR = radius * 0.94;
    final innerR = radius * 0.72;
    final wingSpread = radius * 0.38;
    final wingThick = radius * 0.11;

    // North Chevron (Apex / Governance)
    final northPath = Path()
      ..moveTo(center.dx, center.dy - outerR)
      ..lineTo(center.dx + wingSpread, center.dy - outerR + wingSpread)
      ..lineTo(center.dx + wingSpread - wingThick, center.dy - outerR + wingSpread)
      ..lineTo(center.dx, center.dy - innerR)
      ..lineTo(center.dx - wingSpread + wingThick, center.dy - outerR + wingSpread)
      ..lineTo(center.dx - wingSpread, center.dy - outerR + wingSpread)
      ..close();
    canvas.drawPath(northPath, chevronGoldPaint);
    canvas.drawPath(northPath, chevronStrokePaint);

    // South Chevron (Industry / Infrastructure)
    final southPath = Path()
      ..moveTo(center.dx, center.dy + outerR)
      ..lineTo(center.dx + wingSpread, center.dy + outerR - wingSpread)
      ..lineTo(center.dx + wingSpread - wingThick, center.dy + outerR - wingSpread)
      ..lineTo(center.dx, center.dy + innerR)
      ..lineTo(center.dx - wingSpread + wingThick, center.dy + outerR - wingSpread)
      ..lineTo(center.dx - wingSpread, center.dy + outerR - wingSpread)
      ..close();
    canvas.drawPath(southPath, chevronGoldPaint);
    canvas.drawPath(southPath, chevronStrokePaint);

    // East Chevron (Finance / Markets)
    final eastPath = Path()
      ..moveTo(center.dx + outerR, center.dy)
      ..lineTo(center.dx + outerR - wingSpread, center.dy - wingSpread)
      ..lineTo(center.dx + outerR - wingSpread, center.dy - wingSpread + wingThick)
      ..lineTo(center.dx + innerR, center.dy)
      ..lineTo(center.dx + outerR - wingSpread, center.dy + wingSpread - wingThick)
      ..lineTo(center.dx + outerR - wingSpread, center.dy + wingSpread)
      ..close();
    canvas.drawPath(eastPath, chevronCyanPaint);
    canvas.drawPath(eastPath, chevronStrokePaint);

    // West Chevron (Energy / Technology)
    final westPath = Path()
      ..moveTo(center.dx - outerR, center.dy)
      ..lineTo(center.dx - outerR + wingSpread, center.dy - wingSpread)
      ..lineTo(center.dx - outerR + wingSpread, center.dy - wingSpread + wingThick)
      ..lineTo(center.dx - innerR, center.dy)
      ..lineTo(center.dx - outerR + wingSpread, center.dy + wingSpread - wingThick)
      ..lineTo(center.dx - outerR + wingSpread, center.dy + wingSpread)
      ..close();
    canvas.drawPath(westPath, chevronCyanPaint);
    canvas.drawPath(westPath, chevronStrokePaint);

    // 3. Inner Connecting Inset Diamond & Cardinal Alignment Nodes
    final connectingDiamondPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.02).clamp(0.6, 1.4);

    final insetDiamondPath = Path()
      ..moveTo(center.dx, center.dy - innerR)
      ..lineTo(center.dx + innerR, center.dy)
      ..lineTo(center.dx, center.dy + innerR)
      ..lineTo(center.dx - innerR, center.dy)
      ..close();
    canvas.drawPath(insetDiamondPath, connectingDiamondPaint);

    // 4. Central Planetary Sphere (Earth)
    final planetRadius = radius * 0.56;
    final planetRect = Rect.fromCircle(center: center, radius: planetRadius);

    // Planet core with dynamic gradient
    final planetBasePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        radius: 0.88,
        colors: [
          primaryColor.withValues(alpha: 0.98),
          primaryColor.withValues(alpha: 0.58),
          secondaryColor.withValues(alpha: 0.28),
        ],
      ).createShader(planetRect);
    canvas.drawCircle(center, planetRadius, planetBasePaint);

    // Continental Landmasses, Meridians, and Megalopolis Nodes (Clipped to Globe)
    canvas.save();
    canvas.clipPath(Path()..addOval(planetRect));

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.02).clamp(0.5, 1.2);

    // Equator & Meridians
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: planetRadius * 1.88,
        height: planetRadius * 0.56,
      ),
      gridPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: planetRadius * 0.56,
        height: planetRadius * 1.88,
      ),
      gridPaint,
    );

    canvas.restore();

    // Atmosphere Rim Glow
    final planetRimPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.04).clamp(0.9, 2.6);
    canvas.drawCircle(center, planetRadius, planetRimPaint);
  }

  @override
  bool shouldRepaint(covariant _UnitedQuadrantCrestPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.showGlow != showGlow;
  }
}
