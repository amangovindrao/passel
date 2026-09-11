import 'package:delivery_app/src/features/home/widgets/on_delivery_card.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Active delivery — deliberately minimal for now.
///
/// Navigation, the pickup and delivery photo chain, the pickup code entry and
/// the delivery OTP all belong to Phase 11. This screen has two jobs today:
/// somewhere to land after accepting an offer, and somewhere that keeps hosting
/// the Tier 1 banner and Tier 2 offer listeners for the rest of the trip, since
/// either can fire right up until the final drop-off.
class ActiveDeliveryScreen extends ConsumerWidget {
  const ActiveDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref.watch(activeAssignmentProvider);

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        title: Text(
          'Current delivery',
          style: AppTypography.title.copyWith(color: AppColors.paper),
        ),
      ),
      body: SafeArea(
        child: assignment == null
            ? const Center(
                child: EmptyStateView(
                  icon: Icon(Icons.local_shipping_outlined),
                  title: 'Nothing in progress',
                  subtitle: 'Accepted deliveries show up here.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                children: [
                  ScaleOnCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const GoldPulseIndicator(),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                assignment.shopName,
                                style: AppTypography.title,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          assignment.progressLabel,
                          key: const ValueKey('active-progress-label'),
                          style: AppTypography.body.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TripStopsLine(ordersOnTrip: assignment.ordersOnTrip),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  ScaleOnCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.ash,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Navigation, photos and the pickup code arrive in '
                            'the next release.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.ash,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
