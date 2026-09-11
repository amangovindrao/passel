import 'package:flutter/material.dart';
import 'package:ui_kit/src/theme/app_colors.dart';
import 'package:ui_kit/src/theme/app_typography.dart';
import 'package:ui_kit/src/theme/design_tokens.dart';

/// Rupee price display using the load-bearing data face.
class PriceText extends StatelessWidget {
  const PriceText({
    required this.amount,
    this.originalAmount,
    this.large = false,
    this.zeroLabel = 'Free delivery',
    super.key,
  });

  final num amount;
  final num? originalAmount;
  final bool large;
  final String zeroLabel;

  String _format(num value) {
    final number = value % 1 == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
    return '₹$number';
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final style = (large ? AppTypography.priceLarge : AppTypography.price)
        .copyWith(color: color);
    final current = amount == 0 ? zeroLabel : _format(amount);
    return Semantics(
      label: amount == 0 ? zeroLabel : '$amount rupees',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          ExcludeSemantics(child: Text(current, style: style)),
          if (originalAmount case final original?) ...[
            const SizedBox(width: AppSpacing.sm),
            ExcludeSemantics(
              child: Text(
                _format(original),
                style: AppTypography.data.copyWith(
                  color: AppColors.ash,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
