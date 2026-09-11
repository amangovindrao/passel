import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Replaces the toggle entirely while a delivery is in progress.
///
/// Deliberately not a disabled toggle. A greyed-out circle still invites a tap
/// and leaves the rider wondering whether it did anything. A different widget
/// says what is true: right now the only thing to do is finish the delivery.
class OnDeliveryCard extends StatelessWidget {
  const OnDeliveryCard({
    required this.assignment,
    required this.onTap,
    super.key,
  });

  final ActiveAssignment assignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      key: const ValueKey('on-a-delivery-card'),
      onTap: onTap,
      elevation: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GoldPulseIndicator(),
              const SizedBox(width: AppSpacing.md),
              Text('On a delivery', style: AppTypography.title),
              const Spacer(),
              const Icon(Icons.chevron_right, color: AppColors.ash),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(assignment.shopName, style: AppTypography.bodyStrong),
          const SizedBox(height: AppSpacing.xs),
          Text(
            assignment.progressLabel,
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          if (assignment.ordersOnTrip > 1) ...[
            const SizedBox(height: AppSpacing.md),
            TripStopsLine(ordersOnTrip: assignment.ordersOnTrip),
          ],
        ],
      ),
    );
  }
}

/// "X orders on this trip" — grows as Tier 1 and Tier 2 additions land.
class TripStopsLine extends StatelessWidget {
  const TripStopsLine({required this.ordersOnTrip, super.key});

  final int ordersOnTrip;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('trip-stops-line'),
      children: [
        const Icon(Icons.layers_outlined, size: 16, color: AppColors.gold),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$ordersOnTrip orders on this trip',
          style: AppTypography.data.copyWith(color: AppColors.gold),
        ),
      ],
    );
  }
}
