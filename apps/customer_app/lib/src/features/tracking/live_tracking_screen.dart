import 'package:core/core.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Live tracking screen: map placeholder, timeline, OTP, partner card.
class LiveTrackingScreen extends ConsumerWidget {
  const LiveTrackingScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(trackingProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
      body: trackingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracking) => _TrackingBody(tracking: tracking),
      ),
    );
  }
}

class _TrackingBody extends StatelessWidget {
  const _TrackingBody({required this.tracking});
  final TrackingData tracking;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Map placeholder
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, size: 48, color: AppColors.ash),
                SizedBox(height: AppSpacing.sm),
                Text('Live map tracking'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Delivery OTP (only when OUT_FOR_DELIVERY+)
        if (tracking.deliveryOtp != null) ...[
          ScaleOnCard(
            child: Column(
              children: [
                Text('Delivery OTP', style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tracking.deliveryOtp!,
                  style: AppTypography.otp.copyWith(color: AppColors.gold),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Share this with your delivery partner '
                  'when they arrive',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // Status timeline
        Text('Order progress', style: AppTypography.title),
        const SizedBox(height: AppSpacing.lg),
        ...tracking.statusHistory.asMap().entries.map((entry) {
          final isLast = entry.key == tracking.statusHistory.length - 1;
          final isCurrent = entry.value.status == tracking.status;
          return OrderTimelineTile(
            icon: _iconForStatus(entry.value.status),
            label: _labelForStatus(entry.value.status),
            timestamp: _formatTime(entry.value.createdAt),
            state: isCurrent
                ? TimelineStepState.active
                : TimelineStepState.complete,
            isLast: isLast,
          );
        }),
      ],
    );
  }

  IconData _iconForStatus(String status) => switch (status) {
    'PLACED' => Icons.receipt_long_outlined,
    'ACCEPTED_BY_SHOP' => Icons.check_circle_outline,
    'PREPARING' => Icons.restaurant_outlined,
    'READY_FOR_PICKUP' => Icons.inventory_2_outlined,
    'PARTNER_ASSIGNED' => Icons.delivery_dining_outlined,
    'PARTNER_ARRIVED_AT_SHOP' => Icons.store_outlined,
    'PICKED_UP' => Icons.local_shipping_outlined,
    'OUT_FOR_DELIVERY' => Icons.directions_bike_outlined,
    'DELIVERED' => Icons.done_all_outlined,
    _ => Icons.circle_outlined,
  };

  String _labelForStatus(String status) => switch (status) {
    'PLACED' => 'Order placed',
    'ACCEPTED_BY_SHOP' => 'Shop accepted',
    'PREPARING' => 'Preparing',
    'READY_FOR_PICKUP' => 'Ready for pickup',
    'PARTNER_ASSIGNED' => 'Partner assigned',
    'PARTNER_ARRIVED_AT_SHOP' => 'Partner at shop',
    'PICKED_UP' => 'Picked up',
    'OUT_FOR_DELIVERY' => 'On the way',
    'DELIVERED' => 'Delivered',
    'COMPLETED' => 'Completed',
    _ => status.replaceAll('_', ' ').toLowerCase(),
  };

  String? _formatTime(String? isoString) {
    if (isoString == null) return null;
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } on FormatException {
      return null;
    }
  }
}
