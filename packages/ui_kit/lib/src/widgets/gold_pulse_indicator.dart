import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Paasel's consistent live-state indicator.
class GoldPulseIndicator extends StatefulWidget {
  const GoldPulseIndicator({
    this.size = 8,
    this.color = AppColors.gold,
    super.key,
  });

  final double size;
  final Color color;

  @override
  State<GoldPulseIndicator> createState() => _GoldPulseIndicatorState();
}

class _GoldPulseIndicatorState extends State<GoldPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.pulse);
    _scale = Tween<double>(
      begin: 1,
      end: 1.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween<double>(
      begin: 0.6,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced == _reducedMotion && _controller.isAnimating) return;
    _reducedMotion = reduced;
    if (reduced) {
      _controller
        ..stop()
        ..value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live',
      child: SizedBox.square(
        dimension: widget.size * 1.8,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (!_reducedMotion)
              FadeTransition(
                key: const ValueKey('gold-pulse-ring'),
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: widget.color),
                    ),
                    child: SizedBox.square(dimension: widget.size),
                  ),
                ),
              ),
            DecoratedBox(
              key: const ValueKey('gold-pulse-dot'),
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: widget.size),
            ),
          ],
        ),
      ),
    );
  }
}
