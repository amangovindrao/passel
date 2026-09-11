import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';
import 'package:ui_kit/src/widgets/gold_pulse_indicator.dart';

/// The first thing any of the three apps shows.
///
/// It animates for one reason worth having: the native window behind it is a
/// static drawable, and a static drawable replaced by an identical static
/// Flutter screen is indistinguishable from a frozen app. Movement is the only
/// signal that the process is alive while the session and profile checks run.
///
/// Deliberately short. This is not a brand film — the animation is 520ms and
/// the routing decision runs concurrently, so on a warm start the screen is
/// gone before the sequence finishes. Nothing here gates navigation.
class BrandSplash extends StatefulWidget {
  const BrandSplash({
    required this.wordmark,
    this.background = AppColors.ink,
    this.foreground = AppColors.paper,
    super.key,
  });

  /// e.g. 'Paasel', 'Paasel Shop', 'Paasel Rider'.
  final String wordmark;

  final Color background;
  final Color foreground;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A slice of the timeline, eased. Staggering the mark and the wordmark reads
  /// as one deliberate movement rather than two things appearing at once.
  Animation<double> _slice(double begin, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: AppMotion.easeOut),
  );

  @override
  Widget build(BuildContext context) {
    final mark = _slice(0, 0.7);
    final word = _slice(0.25, 1);

    return Scaffold(
      backgroundColor: widget.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: mark,
              child: ScaleTransition(
                // From slightly under, never over: an overshoot on a launch
                // screen looks like a bounce nobody asked for.
                scale: Tween<double>(begin: 0.86, end: 1).animate(mark),
                child: const _Monogram(colour: AppColors.gold),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FadeTransition(
              opacity: word,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(word),
                child: Text(
                  widget.wordmark,
                  style: AppTypography.displayMedium.copyWith(
                    color: widget.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FadeTransition(
              opacity: _slice(0.6, 1),
              child: const GoldPulseIndicator(size: 10),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ringed P, drawn rather than shipped as an asset so it scales cleanly and
/// stays in step with the launcher icon without a second file to keep in sync.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: CustomPaint(painter: _MonogramPainter(colour)),
    );
  }
}

class _MonogramPainter extends CustomPainter {
  const _MonogramPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    canvas.drawCircle(
      centre,
      r * 0.96,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = colour.withValues(alpha: 0.35),
    );

    final stroke = r * 0.17;
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = colour;

    final stemX = centre.dx - r * 0.24;
    final top = centre.dy - r * 0.52;
    final bottom = centre.dy + r * 0.52;

    canvas
      ..drawLine(Offset(stemX, top), Offset(stemX, bottom), pen)
      ..drawArc(
        Rect.fromLTRB(stemX, top, stemX + r * 0.68, centre.dy + r * 0.02),
        -1.5708, // straight up
        3.1416, // half turn, so the bowl closes back on the stem
        false,
        pen,
      );
  }

  @override
  bool shouldRepaint(_MonogramPainter oldDelegate) =>
      oldDelegate.colour != colour;
}
