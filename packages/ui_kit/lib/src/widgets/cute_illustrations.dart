import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';
import 'package:ui_kit/src/widgets/buttons.dart';

/// Lightweight smiling grocery basket illustration for empty states,
/// greetings, and micro-interactions.
class CuteBasketIllustration extends StatelessWidget {
  const CuteBasketIllustration({
    this.size = 80,
    this.showSparkles = true,
    super.key,
  });

  final double size;
  final bool showSparkles;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pastel background glow
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.softPink.withValues(alpha: 0.5),
            ),
          ),
          // Basket body
          CustomPaint(
            size: Size(size * 0.7, size * 0.7),
            painter: _CuteBasketPainter(),
          ),
          // Micro sparkle top-right
          if (showSparkles) ...[
            Positioned(
              top: size * 0.08,
              right: size * 0.12,
              child: const CuteSparkle(size: 14, color: AppColors.deepBlush),
            ),
            Positioned(
              bottom: size * 0.15,
              left: size * 0.1,
              child: const CuteSparkle(size: 10, color: AppColors.warmPeach),
            ),
          ],
        ],
      ),
    );
  }
}

class _CuteBasketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final basketPaint = Paint()
      ..color = AppColors.softPink
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final detailPaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.fill;

    // Handle
    final handleRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.35),
      width: size.width * 0.45,
      height: size.height * 0.45,
    );
    canvas.drawArc(handleRect, math.pi, math.pi, false, borderPaint);

    // Basket body path (trapezoid with rounded bottom)
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.42)
      ..lineTo(size.width * 0.85, size.height * 0.42)
      ..lineTo(size.width * 0.75, size.height * 0.88)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * 0.96,
        size.width * 0.25,
        size.height * 0.88,
      )
      ..close();

    canvas
      ..drawPath(path, basketPaint)
      ..drawPath(path, borderPaint)
      // Cute smiling face on the basket
      ..drawCircle(
        Offset(size.width * 0.38, size.height * 0.60),
        2.5,
        detailPaint,
      )
      ..drawCircle(
        Offset(size.width * 0.62, size.height * 0.60),
        2.5,
        detailPaint,
      );

    // Blush cheeks
    final blushPaint = Paint()
      ..color = AppColors.deepBlush.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas
      ..drawCircle(
        Offset(size.width * 0.32, size.height * 0.65),
        3.5,
        blushPaint,
      )
      ..drawCircle(
        Offset(size.width * 0.68, size.height * 0.65),
        3.5,
        blushPaint,
      );

    // Cute smile
    final smilePath = Path()
      ..moveTo(size.width * 0.44, size.height * 0.67)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.74,
        size.width * 0.56,
        size.height * 0.67,
      );
    final smilePaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// 1. TINY SHOPPING MASCOT ("Paa-chan" — cute shopping companion)
// -----------------------------------------------------------------------------

/// Tiny Paasel mascot for empty states, success celebrations, and onboarding.
class CuteShoppingMascot extends StatefulWidget {
  const CuteShoppingMascot({
    this.size = 90,
    this.animated = true,
    this.showSparkles = true,
    this.mood = MascotMood.happy,
    super.key,
  });

  final double size;
  final bool animated;
  final bool showSparkles;
  final MascotMood mood;

  @override
  State<CuteShoppingMascot> createState() => _CuteShoppingMascotState();
}

enum MascotMood { happy, celebrating, sleepy, waving }

class _CuteShoppingMascotState extends State<CuteShoppingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.animated) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant CuteShoppingMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animated && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final child = Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // Pastel halo glow
        Container(
          width: s * 0.95,
          height: s * 0.95,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.softPink.withValues(alpha: 0.7),
                AppColors.blush.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        // Mascot Custom Painter
        CustomPaint(
          size: Size(s * 0.75, s * 0.75),
          painter: _CuteMascotPainter(mood: widget.mood),
        ),
        // Floating sparkles
        if (widget.showSparkles) ...[
          Positioned(
            top: 2,
            right: 4,
            child: const TwinkleSparkle(size: 14, color: AppColors.deepBlush),
          ),
          Positioned(
            bottom: 6,
            left: 4,
            child: const TwinkleSparkle(size: 10, color: AppColors.gold),
          ),
        ],
      ],
    );

    if (!widget.animated) return SizedBox(width: s, height: s, child: child);

    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, _) => Transform.translate(
        offset: Offset(0, _bounceAnimation.value),
        child: SizedBox(width: s, height: s, child: child),
      ),
    );
  }
}

class _CuteMascotPainter extends CustomPainter {
  _CuteMascotPainter({required this.mood});
  final MascotMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Mascot Body: cute rounded shopping bag with pastel peach/rose gradient
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.15, h * 0.25, w * 0.7, h * 0.65),
      Radius.circular(w * 0.22),
    );

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF0F5), AppColors.softPink],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bodyRect.outerRect)
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final detailPaint = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.fill;

    // Handles: cute loop on top
    final handleRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.25),
      width: w * 0.36,
      height: h * 0.3,
    );
    canvas.drawArc(handleRect, math.pi, math.pi, false, outlinePaint);

    // Tiny Sprout / Leaf on Handle
    final leafPaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.fill;
    final leafPath = Path()
      ..moveTo(w * 0.5, h * 0.1)
      ..quadraticBezierTo(w * 0.56, h * 0.05, w * 0.62, h * 0.09)
      ..quadraticBezierTo(w * 0.56, h * 0.13, w * 0.5, h * 0.1);
    canvas.drawPath(leafPath, leafPaint);

    // Draw Body
    canvas.drawRRect(bodyRect, bodyPaint);
    canvas.drawRRect(bodyRect, outlinePaint);

    // Eyes
    if (mood == MascotMood.sleepy) {
      final eyePaint = Paint()
        ..color = AppColors.deepBlush
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(w * 0.38, h * 0.52),
          width: 8,
          height: 6,
        ),
        math.pi,
        math.pi,
        false,
        eyePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(w * 0.62, h * 0.52),
          width: 8,
          height: 6,
        ),
        math.pi,
        math.pi,
        false,
        eyePaint,
      );
    } else {
      // Big friendly anime sparkle eyes
      canvas.drawCircle(Offset(w * 0.38, h * 0.50), 3.5, detailPaint);
      canvas.drawCircle(Offset(w * 0.62, h * 0.50), 3.5, detailPaint);

      // Eye catchlights
      final whitePaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(w * 0.365, h * 0.485), 1.2, whitePaint);
      canvas.drawCircle(Offset(w * 0.605, h * 0.485), 1.2, whitePaint);
    }

    // Cheeks (blushing pink)
    final cheekPaint = Paint()
      ..color = AppColors.deepBlush.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.30, h * 0.58), 4.0, cheekPaint);
    canvas.drawCircle(Offset(w * 0.70, h * 0.58), 4.0, cheekPaint);

    // Mouth
    final mouthPaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (mood == MascotMood.celebrating) {
      final openMouthPath = Path()
        ..moveTo(w * 0.44, h * 0.60)
        ..quadraticBezierTo(w * 0.50, h * 0.72, w * 0.56, h * 0.60)
        ..close();
      final fillPaint = Paint()
        ..color = AppColors.deepBlush
        ..style = PaintingStyle.fill;
      canvas.drawPath(openMouthPath, fillPaint);
    } else {
      final smile = Path()
        ..moveTo(w * 0.44, h * 0.59)
        ..quadraticBezierTo(w * 0.50, h * 0.66, w * 0.56, h * 0.59);
      canvas.drawPath(smile, mouthPaint);
    }

    // Little waving hand on the right
    final handPaint = Paint()
      ..color = AppColors.softPink
      ..style = PaintingStyle.fill;
    final handBorder = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final handRect = Rect.fromCenter(
      center: Offset(w * 0.88, h * 0.48),
      width: w * 0.16,
      height: h * 0.16,
    );
    canvas.drawOval(handRect, handPaint);
    canvas.drawOval(handRect, handBorder);

    // Tiny feet
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.92),
        width: 10,
        height: 6,
      ),
      handPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.92),
        width: 10,
        height: 6,
      ),
      handBorder,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.64, h * 0.92),
        width: 10,
        height: 6,
      ),
      handPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.64, h * 0.92),
        width: 10,
        height: 6,
      ),
      handBorder,
    );
  }

  @override
  bool shouldRepaint(covariant _CuteMascotPainter oldDelegate) =>
      oldDelegate.mood != mood;
}

// -----------------------------------------------------------------------------
// 2. SMILING GROCERY ILLUSTRATIONS (Happy Apple + Milk Carton)
// -----------------------------------------------------------------------------

/// Smiling grocery items (happy apple + cute milk bottle) for empty states.
class SmilingGroceryIllustration extends StatelessWidget {
  const SmilingGroceryIllustration({this.size = 100, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient soft glow
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blush,
            ),
          ),
          CustomPaint(
            size: Size(size * 0.85, size * 0.85),
            painter: _SmilingGroceryPainter(),
          ),
          // Twinkles
          Positioned(
            top: 4,
            right: 10,
            child: const TwinkleSparkle(size: 14, color: AppColors.deepBlush),
          ),
          Positioned(
            bottom: 12,
            left: 6,
            child: const TwinkleSparkle(size: 10, color: AppColors.gold),
          ),
        ],
      ),
    );
  }
}

class _SmilingGroceryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Cute Milk Carton on Left
    final milkPaint = Paint()
      ..color = const Color(0xFFF3F0FF)
      ..style = PaintingStyle.fill;
    final milkBorder = Paint()
      ..color = AppColors.deepLavender
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final milkRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.28, w * 0.34, h * 0.58),
      const Radius.circular(8),
    );
    canvas.drawRRect(milkRect, milkPaint);
    canvas.drawRRect(milkRect, milkBorder);

    // Milk Carton Cap / Roof
    final roofPath = Path()
      ..moveTo(w * 0.12, h * 0.28)
      ..lineTo(w * 0.22, h * 0.15)
      ..lineTo(w * 0.36, h * 0.15)
      ..lineTo(w * 0.46, h * 0.28)
      ..close();
    canvas.drawPath(roofPath, milkPaint);
    canvas.drawPath(roofPath, milkBorder);

    // Milk Face
    final facePaint = Paint()..color = AppColors.deepLavender;
    canvas.drawCircle(Offset(w * 0.24, h * 0.50), 2.2, facePaint);
    canvas.drawCircle(Offset(w * 0.34, h * 0.50), 2.2, facePaint);
    // Blush
    final milkBlush = Paint()..color = AppColors.deepLavender.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(w * 0.20, h * 0.54), 2.8, milkBlush);
    canvas.drawCircle(Offset(w * 0.38, h * 0.54), 2.8, milkBlush);
    // Smile
    final milkSmile = Path()
      ..moveTo(w * 0.26, h * 0.56)
      ..quadraticBezierTo(w * 0.29, h * 0.61, w * 0.32, h * 0.56);
    canvas.drawPath(milkSmile, milkBorder);

    // 2. Cute Smiling Red Apple on Right
    final applePaint = Paint()
      ..color = const Color(0xFFFF6B81)
      ..style = PaintingStyle.fill;
    final appleBorder = Paint()
      ..color = const Color(0xFFC73659)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final appleCenter = Offset(w * 0.64, h * 0.60);
    final appleRadius = w * 0.26;
    canvas.drawCircle(appleCenter, appleRadius, applePaint);
    canvas.drawCircle(appleCenter, appleRadius, appleBorder);

    // Apple Stem & Leaf
    final stemPaint = Paint()
      ..color = const Color(0xFF5A3825)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.64, h * 0.34),
      Offset(w * 0.64, h * 0.24),
      stemPaint,
    );

    final appleLeaf = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.fill;
    final leafPath = Path()
      ..moveTo(w * 0.64, h * 0.27)
      ..quadraticBezierTo(w * 0.76, h * 0.20, w * 0.78, h * 0.26)
      ..quadraticBezierTo(w * 0.72, h * 0.32, w * 0.64, h * 0.27);
    canvas.drawPath(leafPath, appleLeaf);

    // Apple Face
    final appleInk = Paint()..color = const Color(0xFF5E1B2B);
    canvas.drawCircle(Offset(w * 0.56, h * 0.56), 2.5, appleInk);
    canvas.drawCircle(Offset(w * 0.72, h * 0.56), 2.5, appleInk);
    // Cheeks
    final appleCheek = Paint()..color = Colors.white.withValues(alpha: 0.45);
    canvas.drawCircle(Offset(w * 0.51, h * 0.61), 3.2, appleCheek);
    canvas.drawCircle(Offset(w * 0.77, h * 0.61), 3.2, appleCheek);
    // Smile
    final appleSmile = Path()
      ..moveTo(w * 0.60, h * 0.62)
      ..quadraticBezierTo(w * 0.64, h * 0.69, w * 0.68, h * 0.62);
    final appleSmileBorder = Paint()
      ..color = const Color(0xFF5E1B2B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(appleSmile, appleSmileBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// 3. CUTE EMPTY-CART ILLUSTRATION
// -----------------------------------------------------------------------------

/// Cute empty cart character with sleepy/curious smile and sparkles.
class CuteEmptyCartIllustration extends StatelessWidget {
  const CuteEmptyCartIllustration({this.size = 110, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pastel halo
          Container(
            width: size * 0.88,
            height: size * 0.88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.softPink.withValues(alpha: 0.6),
            ),
          ),
          CustomPaint(
            size: Size(size * 0.8, size * 0.8),
            painter: _CuteEmptyCartPainter(),
          ),
          // Floating little heart on top
          Positioned(
            top: size * 0.05,
            right: size * 0.2,
            child: const TwinkleSparkle(size: 16, color: AppColors.deepBlush),
          ),
          Positioned(
            top: size * 0.15,
            left: size * 0.12,
            child: const Icon(
              Icons.favorite,
              size: 12,
              color: AppColors.deepBlush,
            ),
          ),
        ],
      ),
    );
  }
}

class _CuteEmptyCartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final cartFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final cartBorder = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Cart wireframe body
    final basketPath = Path()
      ..moveTo(w * 0.18, h * 0.35)
      ..lineTo(w * 0.82, h * 0.35)
      ..lineTo(w * 0.72, h * 0.68)
      ..quadraticBezierTo(w * 0.50, h * 0.72, w * 0.28, h * 0.68)
      ..close();

    canvas.drawPath(basketPath, cartFill);
    canvas.drawPath(basketPath, cartBorder);

    // Push Handle
    final handlePath = Path()
      ..moveTo(w * 0.18, h * 0.35)
      ..lineTo(w * 0.08, h * 0.24);
    canvas.drawPath(handlePath, cartBorder);

    // Cute smiling face inside the cart
    final eyePaint = Paint()..color = AppColors.ink;
    canvas.drawCircle(Offset(w * 0.42, h * 0.50), 2.8, eyePaint);
    canvas.drawCircle(Offset(w * 0.58, h * 0.50), 2.8, eyePaint);

    // Blushing cheeks
    final blush = Paint()..color = AppColors.deepBlush.withValues(alpha: 0.35);
    canvas.drawCircle(Offset(w * 0.36, h * 0.54), 3.5, blush);
    canvas.drawCircle(Offset(w * 0.64, h * 0.54), 3.5, blush);

    // Smile
    final smile = Path()
      ..moveTo(w * 0.46, h * 0.55)
      ..quadraticBezierTo(w * 0.50, h * 0.61, w * 0.54, h * 0.55);
    final smilePaint = Paint()
      ..color = AppColors.deepBlush
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(smile, smilePaint);

    // Cart Wheels
    final wheelPaint = Paint()
      ..color = AppColors.graphite
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.35, h * 0.82), 5, wheelPaint);
    canvas.drawCircle(Offset(w * 0.65, h * 0.82), 5, wheelPaint);

    final hubPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.35, h * 0.82), 2, hubPaint);
    canvas.drawCircle(Offset(w * 0.65, h * 0.82), 2, hubPaint);

    // Wheel frame supports
    canvas.drawLine(
      Offset(w * 0.35, h * 0.70),
      Offset(w * 0.35, h * 0.80),
      cartBorder,
    );
    canvas.drawLine(
      Offset(w * 0.65, h * 0.70),
      Offset(w * 0.65, h * 0.80),
      cartBorder,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// 4. CUTE DELIVERY SCOOTER ILLUSTRATION
// -----------------------------------------------------------------------------

/// Cute delivery scooter with animated / playful motion trail and heart puff.
class CuteDeliveryScooter extends StatelessWidget {
  const CuteDeliveryScooter({
    this.size = 56,
    this.showTrail = true,
    super.key,
  });

  final double size;
  final bool showTrail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.peach,
              border: Border.all(
                color: AppColors.warmPeach.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Icon(
                Icons.moped_rounded,
                size: size * 0.62,
                color: AppColors.warmPeach,
              ),
            ),
          ),
          if (showTrail) ...[
            Positioned(
              top: 2,
              right: 2,
              child: const Icon(
                Icons.favorite,
                size: 10,
                color: AppColors.deepBlush,
              ),
            ),
            Positioned(
              bottom: 4,
              left: 2,
              child: const CuteSparkle(size: 8, color: AppColors.warmPeach),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mini delivery scooter illustration for "Earn with Paasel" and tracking.
class CuteScooterIllustration extends StatelessWidget {
  const CuteScooterIllustration({this.size = 50, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CuteDeliveryScooter(size: size);
  }
}

// -----------------------------------------------------------------------------
// 5. TINY FLOATING HEARTS MICRO-INTERACTION
// -----------------------------------------------------------------------------

/// Micro-interaction overlay widget that launches floating heart particles
/// when triggered (e.g. favoriting a shop).
class TinyFloatingHeartsWrapper extends StatefulWidget {
  const TinyFloatingHeartsWrapper({
    required this.child,
    this.isEnabled = true,
    super.key,
  });

  final Widget child;
  final bool isEnabled;

  static void trigger(GlobalKey<_TinyFloatingHeartsWrapperState> key) {
    key.currentState?.burst();
  }

  @override
  State<TinyFloatingHeartsWrapper> createState() =>
      _TinyFloatingHeartsWrapperState();
}

class _TinyFloatingHeartsWrapperState extends State<TinyFloatingHeartsWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final List<_HeartParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(_particles.clear);
        }
      });
  }

  void burst() {
    if (!widget.isEnabled) return;
    _particles.clear();
    for (var i = 0; i < 5; i++) {
      _particles.add(
        _HeartParticle(
          dx: (_random.nextDouble() - 0.5) * 36,
          dy: -(_random.nextDouble() * 40 + 20),
          size: _random.nextDouble() * 6 + 10,
          color: i.isEven ? AppColors.deepBlush : const Color(0xFFFF7E95),
        ),
      );
    }
    _controller.forward(from: 0.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        widget.child,
        if (_particles.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _controller.value;
                  final opacity = (1.0 - progress).clamp(0.0, 1.0);
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: _particles.map((p) {
                      final curX = p.dx * progress;
                      final curY = p.dy * progress;
                      return Transform.translate(
                        offset: Offset(curX, curY),
                        child: Opacity(
                          opacity: opacity,
                          child: Icon(
                            Icons.favorite,
                            size: p.size,
                            color: p.color,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// A convenience favorite heart button that automatically bursts floating hearts
/// when toggled on, if [isEnabled] is true (Pinkie mode).
class TinyFloatingHeartButton extends StatelessWidget {
  const TinyFloatingHeartButton({
    required this.isFav,
    required this.onToggle,
    this.isEnabled = true,
    this.size = 20,
    super.key,
  });

  final bool isFav;
  final VoidCallback onToggle;
  final bool isEnabled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final heartKey = GlobalKey<_TinyFloatingHeartsWrapperState>();
    return TinyFloatingHeartsWrapper(
      key: heartKey,
      isEnabled: isEnabled,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        icon: Icon(
          isFav ? Icons.favorite : Icons.favorite_border,
          size: size,
          color: isFav ? AppColors.deepBlush : AppColors.ash,
        ),
        onPressed: () {
          if (!isFav && isEnabled) {
            heartKey.currentState?.burst();
          }
          onToggle();
        },
      ),
    );
  }
}


class _HeartParticle {
  const _HeartParticle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.color,
  });

  final double dx;
  final double dy;
  final double size;
  final Color color;
}

// -----------------------------------------------------------------------------
// 6. PLAYFUL REWARD BADGE & SPARKLE ANIMATIONS
// -----------------------------------------------------------------------------

/// Playful bouncing reward badge with rotating sparkle halo.
class PlayfulRewardBadge extends StatefulWidget {
  const PlayfulRewardBadge({
    this.size = 48,
    this.amountText = '\u20b950',
    super.key,
  });

  final double size;
  final String amountText;

  @override
  State<PlayfulRewardBadge> createState() => _PlayfulRewardBadgeState();
}

class _PlayfulRewardBadgeState extends State<PlayfulRewardBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating sparkles
          RotationTransition(
            turns: _controller,
            child: SizedBox(
              width: s,
              height: s,
              child: const Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 6,
                    child: CuteSparkle(size: 10, color: AppColors.gold),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 6,
                    child: CuteSparkle(size: 8, color: AppColors.deepBlush),
                  ),
                ],
              ),
            ),
          ),
          // Bouncing gold coin badge
          CuteCoinBadge(size: s * 0.75),
        ],
      ),
    );
  }
}

/// Dynamic four-pointed star that gently pulses scale and opacity.
class TwinkleSparkle extends StatefulWidget {
  const TwinkleSparkle({
    this.size = 16,
    this.color = AppColors.gold,
    super.key,
  });

  final double size;
  final Color color;

  @override
  State<TwinkleSparkle> createState() => _TwinkleSparkleState();
}

class _TwinkleSparkleState extends State<TwinkleSparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.65, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: CuteSparkle(size: widget.size, color: widget.color),
    );
  }
}

/// Subtle four-pointed twinkle star / sparkle micro-element.
class CuteSparkle extends StatelessWidget {
  const CuteSparkle({
    this.size = 16,
    this.color = AppColors.gold,
    super.key,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _SparklePainter(color),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;

    final path = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx, cy, size.width, cy)
      ..quadraticBezierTo(cx, cy, cx, size.height)
      ..quadraticBezierTo(cx, cy, 0, cy)
      ..quadraticBezierTo(cx, cy, cx, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A subtle 3D-styled golden coin badge for rewards, cashback,
/// and wallet highlights.
class CuteCoinBadge extends StatelessWidget {
  const CuteCoinBadge({this.size = 28, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.3),
          radius: 0.9,
          colors: [
            Color(0xFFFFDF73),
            AppColors.gold,
            Color(0xFFB88E18),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '\u20b9',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.55,
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 7. WALLET CELEBRATION MODAL
// -----------------------------------------------------------------------------

/// Playful celebration dialog for wallet rewards, cashback, and top-ups.
class WalletCelebrationDialog extends StatelessWidget {
  const WalletCelebrationDialog({
    required this.title,
    required this.subtitle,
    this.amountText,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? amountText;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? amountText,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => WalletCelebrationDialog(
        title: title,
        subtitle: subtitle,
        amountText: amountText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CuteShoppingMascot(
              size: 88,
              mood: MascotMood.celebrating,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headline.copyWith(fontSize: 20),
            ),
            if (amountText != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                amountText!,
                style: AppTypography.price.copyWith(
                  fontSize: 28,
                  color: AppColors.success,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppColors.ash),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Awesome!',
              onPressed: () => Navigator.of(context).pop(),
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

