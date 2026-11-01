import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Local vector logo for Moodly: a rounded squircle with a gentle smile, drawn
/// entirely with CustomPaint so there is no network or asset dependency.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 56, this.withShadow = true});

  final double size;
  final bool withShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: withShadow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.32),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: size * 0.28,
                  offset: Offset(0, size * 0.10),
                ),
              ],
            )
          : null,
      child: CustomPaint(
        painter: _LogoPainter(radius: size * 0.32),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final bgPaint = Paint()
      ..shader = AppColors.brandGradient.createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    // Mint smile + eyes on the purple squircle.
    final mintStroke = Paint()
      ..color = AppColors.mint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final eyePaint = Paint()..color = AppColors.mint;

    final eyeRadius = Radius.circular(size.width * 0.055);
    final eyeY = size.height * 0.40;
    for (final dx in const [0.35, 0.65]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width * dx, eyeY),
            width: size.width * 0.11,
            height: size.width * 0.11,
          ),
          eyeRadius,
        ),
        eyePaint,
      );
    }

    mintStroke.strokeWidth = size.width * 0.075;
    final smile = Path()
      ..moveTo(size.width * 0.28, size.height * 0.60)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.78,
        size.width * 0.72,
        size.height * 0.60,
      );
    canvas.drawPath(smile, mintStroke);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => oldDelegate.radius != radius;
}

/// Logo mark + wordmark + tagline, used on the splash and settings screens.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.markSize = 72,
    this.textColor,
    this.taglineColor,
  });

  final double markSize;
  final Color? textColor;
  final Color? taglineColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: markSize),
        const SizedBox(height: 18),
        Text(
          'Moodly',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: textColor ?? AppColors.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your Daily Mood',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: taglineColor ?? AppColors.lightSecondaryText,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
