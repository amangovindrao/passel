import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// A premium glassmorphic container with frosted blur, subtle gradient,
/// soft borders, and gentle 3D elevation.
class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.gradient,
    this.blur = 12.0,
    this.elevation = 1,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final Gradient? gradient;
  final double blur;
  final int elevation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    final defaultBg = isDark
        ? AppColors.glassCardDark
        : AppColors.glassSurface;

    final defaultBorder = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.07));

    final shadows = switch (elevation) {
      1 => [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      2 => [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      _ => const <BoxShadow>[],
    };

    Widget content = Padding(
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: r,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          splashColor: Colors.black.withValues(alpha: 0.06),
          highlightColor: Colors.black.withValues(alpha: 0.04),
          child: content,
        ),
      );
    }


    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            decoration: BoxDecoration(
              color: gradient == null ? (backgroundColor ?? defaultBg) : null,
              gradient: gradient,
              borderRadius: r,
              border: Border.all(
                color: defaultBorder,
                width: 1.2,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
