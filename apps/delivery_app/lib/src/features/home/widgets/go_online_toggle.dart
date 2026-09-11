import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// The large circular availability control — the dashboard's centrepiece.
///
/// Off: outline only, sitting quietly on the ink canvas. On: solid gold with a
/// [GoldPulseIndicator] layered over it. That pulse is the fourth and final
/// canonical use of the indicator from the design system, and it means here
/// what it means everywhere else — something live is happening right now.
class GoOnlineToggle extends StatelessWidget {
  const GoOnlineToggle({
    required this.isOnline,
    required this.onPressed,
    this.busy = false,
    this.diameter = 200,
    super.key,
  });

  final bool isOnline;

  /// Null disables the control, e.g. while location permission is insufficient.
  final VoidCallback? onPressed;
  final bool busy;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final foreground = isOnline ? AppColors.ink : AppColors.gold;

    return Semantics(
      button: true,
      enabled: enabled,
      label: isOnline ? 'Go offline' : 'Go online',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          key: const ValueKey('go-online-toggle'),
          duration: AppMotion.status,
          curve: AppMotion.easeOut,
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? AppColors.gold : Colors.transparent,
            border: Border.all(
              color: enabled
                  ? (isOnline ? AppColors.gold : AppColors.gold)
                  : AppColors.ash.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isOnline) ...[
                        const GoldPulseIndicator(
                          size: 12,
                          color: AppColors.ink,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        isOnline ? "You're online" : 'Go online',
                        style: AppTypography.title.copyWith(
                          color: enabled
                              ? foreground
                              : AppColors.ash.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isOnline ? 'Tap to stop' : 'Tap to start',
                        style: AppTypography.caption.copyWith(
                          color: isOnline
                              ? AppColors.ink.withValues(alpha: 0.7)
                              : AppColors.ash,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
