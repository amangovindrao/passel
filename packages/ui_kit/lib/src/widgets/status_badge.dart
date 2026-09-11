import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';
import 'package:ui_kit/src/widgets/gold_pulse_indicator.dart';

/// Visual states supported by [StatusBadge].
enum StatusBadgeState {
  preparing,
  readyForPickup,
  outForDelivery,
  delivered,
  cancelled,
}

/// Compact, color-coded order-state pill.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, this.label, super.key});

  final StatusBadgeState status;
  final String? label;

  String get _defaultLabel => switch (status) {
    StatusBadgeState.preparing => 'Preparing',
    StatusBadgeState.readyForPickup => 'Ready for pickup',
    StatusBadgeState.outForDelivery => 'Out for delivery',
    StatusBadgeState.delivered => 'Delivered',
    StatusBadgeState.cancelled => 'Cancelled',
  };

  Color get _color => switch (status) {
    StatusBadgeState.preparing => AppColors.warning,
    StatusBadgeState.readyForPickup ||
    StatusBadgeState.outForDelivery => AppColors.gold,
    StatusBadgeState.delivered => AppColors.success,
    StatusBadgeState.cancelled => AppColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final color = _color;
    final content = Container(
      key: ValueKey(status),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == StatusBadgeState.outForDelivery) ...[
            const GoldPulseIndicator(size: 6),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            label ?? _defaultLabel,
            style: AppTypography.caption.copyWith(color: color),
          ),
        ],
      ),
    );

    return Semantics(
      label: 'Order status: ${label ?? _defaultLabel}',
      child: AnimatedSwitcher(
        duration: reducedMotion ? Duration.zero : AppMotion.status,
        switchInCurve: AppMotion.easeOut,
        switchOutCurve: AppMotion.easeOut,
        transitionBuilder: (child, animation) {
          if (reducedMotion) return child;
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: content,
      ),
    );
  }
}
