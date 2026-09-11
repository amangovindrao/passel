import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';
import 'package:ui_kit/src/widgets/gold_pulse_indicator.dart';

/// Visual state of one order timeline step.
enum TimelineStepState { active, complete, pending }

/// One vertical order-progress step with icon, label, and timestamp.
class OrderTimelineTile extends StatelessWidget {
  const OrderTimelineTile({
    required this.icon,
    required this.label,
    required this.state,
    this.timestamp,
    this.isLast = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? timestamp;
  final TimelineStepState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final activeColor = switch (state) {
      TimelineStepState.active => AppColors.gold,
      TimelineStepState.complete => AppColors.success,
      TimelineStepState.pending => AppColors.ash,
    };
    return Semantics(
      label: '$label, ${state.name}${timestamp == null ? '' : ', $timestamp'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                AnimatedSwitcher(
                  duration: reducedMotion ? Duration.zero : AppMotion.status,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.12),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _StepIcon(
                    key: ValueKey(state),
                    icon: icon,
                    state: state,
                    color: activeColor,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 44,
                    color: state == TimelineStepState.complete
                        ? AppColors.success
                        : AppColors.ash.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: isLast ? 0 : AppSpacing.xxl,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: state == TimelineStepState.pending
                            ? AppColors.ash
                            : foreground,
                      ),
                    ),
                  ),
                  if (timestamp != null)
                    Text(
                      timestamp!,
                      style: AppTypography.data.copyWith(color: AppColors.ash),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({
    required this.icon,
    required this.state,
    required this.color,
    super.key,
  });

  final IconData icon;
  final TimelineStepState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color),
            ),
            child: Icon(
              state == TimelineStepState.complete ? Icons.check_rounded : icon,
              size: 17,
              color: color,
            ),
          ),
          if (state == TimelineStepState.active)
            const Positioned(
              right: 0,
              top: 0,
              child: GoldPulseIndicator(size: 6),
            ),
        ],
      ),
    );
  }
}
