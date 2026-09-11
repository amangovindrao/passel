import 'package:core/core.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Order history: Active / Past segmented.
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

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
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
          // Order list
          Expanded(
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (orders) {
                if (orders.isEmpty) {
                  return EmptyStateView(
                    icon: const Icon(Icons.receipt_long_outlined),
                    title: _showActive
                        ? 'No active orders'
                        : 'No past orders yet',
                    subtitle: _showActive
                        ? 'Place an order to see it here.'
                        : 'Your completed orders will show here.',
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

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.isActive});
  final OrderSummary order;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
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
                    'Order #${order.id.substring(0, 8)}',
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  PriceText(amount: order.totalPaise / 100),
                ],
              ),
            ),
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
