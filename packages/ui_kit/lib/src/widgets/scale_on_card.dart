import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// A flat, rounded Paasel surface container.
class ScaleOnCard extends StatelessWidget {
  const ScaleOnCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.elevation = 0,
    super.key,
  }) : assert(elevation >= 0 && elevation <= 2, 'Use elevation 0, 1, or 2.');

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final int elevation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadows = switch (elevation) {
      1 => AppShadows.level1,
      2 => AppShadows.level2,
      _ => const <BoxShadow>[],
    };
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? AppColors.graphite : AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: shadows,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
