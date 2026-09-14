import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Order history: Active / Past segmented with 1-tap reorder & monthly ration banner.
class OrderHistoryScreen extends ConsumerStatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  ConsumerState<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends ConsumerState<OrderHistoryScreen> {
  bool _showActive = true;

  @override
  Widget build(BuildContext context) {
    final ordersAsync = _showActive
        ? ref.watch(activeOrdersProvider)
        : ref.watch(pastOrdersProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: Column(
        children: [
          // Segmented control
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Active')),
                ButtonSegment(value: false, label: Text('Past')),
              ],
              selected: {_showActive},
              onSelectionChanged: (s) => setState(() => _showActive = s.first),
            ),
          ),

          // Monthly Ration Banner (shown in Past tab)
          if (!_showActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.lavender.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.deepLavender.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_rounded,
                      color: AppColors.deepLavender,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monthly Ration Delivery',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.deepLavender,
                            ),
                          ),
                          Text(
                            'Auto-repeat your kitchen staples every month with zero delivery fee.',
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.ash,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Order list
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (orders) {
                if (orders.isEmpty) {
                  return EmptyStateView(
                    icon: isPinkie
                        ? const SmilingGroceryIllustration(size: 88)
                        : const Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: AppColors.ash,
                          ),
                    title: _showActive
                        ? (isPinkie ? 'Nothing cooking right now!' : 'No active orders')
                        : (isPinkie ? 'No past goodies yet' : 'No past orders yet'),
                    subtitle: _showActive
                        ? (isPinkie
                            ? 'Order from your favorite shops and track delivery live ✨'
                            : 'Place an order to see it here.')
                        : (isPinkie
                            ? 'Your delivered delights and ration orders will appear here!'
                            : 'Your completed orders will show here.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: orders.length,
                  itemBuilder: (_, i) =>
                      _OrderCard(order: orders[i], isActive: _showActive),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, required this.isActive});
  final OrderSummary order;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ScaleOnCard(
        onTap: () {
          if (isActive) {
            context.push('/tracking/${order.id}');
          } else {
            context.push('/order-detail/${order.id}');
          }
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PriceText(amount: order.totalPaise / 100),
                ],
              ),
            ),
            if (!isActive) ...[
              Consumer(
                builder: (context, ref, _) {
                  final isPinkie = ref.watch(isPinkieThemeActiveProvider);
                  return ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentFor(isPinkie: isPinkie),
                      foregroundColor: AppColors.primaryFor(isPinkie: isPinkie),
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                    icon: const Icon(Icons.repeat_rounded, size: 14),
                    label: const Text(
                      'Reorder',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => triggerOneTapReorder(
                      context: context,
                      ref: ref,
                      orderId: order.id,
                      shopId: order.shopId,
                    ),
                  );
                },
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            StatusBadge(
              status: _mapStatus(order.status),
              label: order.status.replaceAll('_', ' ').toLowerCase(),
            ),
          ],
        ),
      ),
    );
  }

  StatusBadgeState _mapStatus(String status) => switch (status) {
    'PREPARING' => StatusBadgeState.preparing,
    'READY_FOR_PICKUP' ||
    'PARTNER_ASSIGNED' ||
    'PARTNER_ARRIVED_AT_SHOP' => StatusBadgeState.readyForPickup,
    'PICKED_UP' || 'OUT_FOR_DELIVERY' => StatusBadgeState.outForDelivery,
    'DELIVERED' || 'COMPLETED' => StatusBadgeState.delivered,
    _ => StatusBadgeState.preparing,
  };
}
