import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Colour for a countdown, escalating as time runs out.
///
/// Shared so every deadline in the app escalates identically: the shop's
/// 5-minute accept SLA, the rider's 35-second offer, the 20-second detour. Same
/// principle, different windows — calm, then warning, then danger.
Color urgencyColor(double fractionRemaining) {
  if (fractionRemaining > 0.5) return AppColors.gold;
  if (fractionRemaining > 0.25) return AppColors.warning;
  return AppColors.danger;
}

/// True once a countdown has crossed into its final, clearly-urgent phase.
bool isUrgent(double fractionRemaining) => fractionRemaining <= 0.25;

/// A ring that drains as the window closes, seconds left in the middle.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    required this.secondsRemaining,
    required this.totalSeconds,
    this.diameter = 96,
    super.key,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final double diameter;

  double get _fraction =>
      totalSeconds <= 0 ? 0 : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(_fraction);

    return Semantics(
      label: '$secondsRemaining seconds left to decide',
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: _fraction),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 5,
                  backgroundColor: AppColors.ash.withValues(alpha: 0.22),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            Text(
              '$secondsRemaining',
              key: const ValueKey('countdown-seconds'),
              style: AppTypography.price.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
