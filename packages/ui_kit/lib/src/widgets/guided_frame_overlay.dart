import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Border treatment for the guided capture frame.
enum GuidedFrameStyle { dashed, solid }

/// Camera-agnostic visual guidance for a later photo-capture flow.
class GuidedFrameOverlay extends StatelessWidget {
  const GuidedFrameOverlay({
    required this.instruction,
    this.child,
    this.style = GuidedFrameStyle.dashed,
    this.frameAspectRatio = 4 / 3,
    this.frameColor = AppColors.gold,
    this.scrimColor = const Color(0x99000000),
    super.key,
  });

  final String instruction;
  final Widget? child;
  final GuidedFrameStyle style;
  final double frameAspectRatio;
  final Color frameColor;
  final Color scrimColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (child != null) child!,
        IgnorePointer(
          child: CustomPaint(
            painter: _FramePainter(
              style: style,
              aspectRatio: frameAspectRatio,
              frameColor: frameColor,
              scrimColor: scrimColor,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.82),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Text(
                  instruction,
                  textAlign: TextAlign.center,
                  style: AppTypography.label.copyWith(color: AppColors.paper),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.style,
    required this.aspectRatio,
    required this.frameColor,
    required this.scrimColor,
  });

  final GuidedFrameStyle style;
  final double aspectRatio;
  final Color frameColor;
  final Color scrimColor;

  @override
  void paint(Canvas canvas, Size size) {
    const margin = AppSpacing.xl;
    final maxWidth = size.width - margin * 2;
    final maxHeight = size.height * 0.58;
    var width = maxWidth;
    var height = width / aspectRatio;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspectRatio;
    }
    final frame = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: width,
      height: height,
    );
    final rounded = RRect.fromRectAndRadius(
      frame,
      const Radius.circular(AppRadius.lg),
    );

    final cutout = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(rounded);
    canvas.drawPath(cutout, Paint()..color = scrimColor);

    final borderPaint = Paint()
      ..color = frameColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final borderPath = Path()..addRRect(rounded);
    if (style == GuidedFrameStyle.dashed) {
      _drawDashedPath(canvas, borderPath, borderPaint);
    } else {
      canvas.drawPath(borderPath, borderPaint);
    }
    _drawCorners(canvas, frame);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, (distance + 8).clamp(0, metric.length)),
          paint,
        );
        distance += 14;
      }
    }
  }

  void _drawCorners(Canvas canvas, Rect rect) {
    const length = 24.0;
    final paint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(rect.left, rect.top + length)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.left + length, rect.top)
      ..moveTo(rect.right - length, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right, rect.top + length)
      ..moveTo(rect.right, rect.bottom - length)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right - length, rect.bottom)
      ..moveTo(rect.left + length, rect.bottom)
      ..lineTo(rect.left, rect.bottom)
      ..lineTo(rect.left, rect.bottom - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) {
    return style != oldDelegate.style ||
        aspectRatio != oldDelegate.aspectRatio ||
        frameColor != oldDelegate.frameColor ||
        scrimColor != oldDelegate.scrimColor;
  }
}
