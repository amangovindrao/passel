import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Semantic snackbar variants.
enum AppSnackbarVariant { success, error, info }

/// Paasel snackbar content and presentation helper.
class AppSnackbar extends StatelessWidget {
  const AppSnackbar({
    required this.message,
    this.variant = AppSnackbarVariant.info,
    super.key,
  });

  final String message;
  final AppSnackbarVariant variant;

  Color get _color => switch (variant) {
    AppSnackbarVariant.success => AppColors.success,
    AppSnackbarVariant.error => AppColors.danger,
    AppSnackbarVariant.info => AppColors.gold,
  };

  IconData get _icon => switch (variant) {
    AppSnackbarVariant.success => Icons.check_circle_outline_rounded,
    AppSnackbarVariant.error => Icons.error_outline_rounded,
    AppSnackbarVariant.info => Icons.info_outline_rounded,
  };

  static void show(
    BuildContext context, {
    required String message,
    AppSnackbarVariant variant = AppSnackbarVariant.info,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: AppSnackbar(message: message, variant: variant),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(_icon, color: _color, size: 20),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(message, style: AppTypography.bodyMedium)),
      ],
    );
  }
}
