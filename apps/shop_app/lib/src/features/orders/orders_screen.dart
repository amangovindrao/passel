import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// The shop's order queue.
///
/// New orders are grouped and pinned to the top rather than left in date order
/// among everything else. A shop reads this screen while doing three other
/// things, and the only question that matters on opening it is "is there
/// anything I have not looked at yet".
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({required this.shopId, super.key});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(shopOrdersProvider(shopId));

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        title: const Text('Orders'),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(shopOrdersProvider(shopId)),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Unlike the catalog screen, a failure here offers a way out. This is
        // the screen a shop sits on all day; a dead end with a raw exception on
        // it is not good enough.
        error: (e, _) => _LoadFailed(
          message: e is AppError ? e.message : 'Something went wrong.',
          onRetry: () => ref.invalidate(shopOrdersProvider(shopId)),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const EmptyStateView(
              icon: Icon(Icons.receipt_long_outlined),
              title: 'No orders right now',
              subtitle:
                  'New orders appear here as soon as a customer places one.',
            );
          }

          final fresh = orders.where((o) => o.isNew).toList();
          final working = orders.where((o) => !o.isNew).toList();

          return RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.graphite,
            onRefresh: () async => ref.invalidate(shopOrdersProvider(shopId)),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (fresh.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Needs your attention',
                    count: fresh.length,
                  ),
                  for (final order in fresh)
                    _OrderRow(order: order, shopId: shopId),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (working.isNotEmpty) ...[
                  _SectionHeader(label: 'In progress', count: working.length),
                  for (final order in working)
                    _OrderRow(order: order, shopId: shopId),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.label.copyWith(color: AppColors.ash),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '$count',
              style: AppTypography.caption.copyWith(color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order, required this.shopId});

  final ShopOrderSummary order;
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ScaleOnCard(
        key: ValueKey('order-row-${order.id}'),
        onTap: () => context.push('/order/$shopId/${order.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${order.shortRef}',
                    style: AppTypography.bodyMedium,
                  ),
                ),
                StatusBadge(
                  status: shopStatusBadge(order.status),
                  label: shopStatusLabel(order.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  order.itemCount == 1 ? '1 item' : '${order.itemCount} items',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
                const SizedBox(width: AppSpacing.md),
                // COD is worth stating plainly: it is money the shop hands to
                // the rider, so it changes what happens at the counter.
                Text(
                  order.isCod ? 'Cash on delivery' : 'Paid online',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
                const Spacer(),
                PriceText(amount: order.totalPaise / 100, zeroLabel: '\u20b90'),
              ],
            ),
            if (order.awaitingPayment) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.hourglass_empty,
                    size: 14,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Waiting for payment',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.ash,
              size: 40,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Couldn't load your orders",
              style: AppTypography.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.caption.copyWith(color: AppColors.ash),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SecondaryButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
