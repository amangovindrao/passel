import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Cart screen with quantity steppers and minimum order validation.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  static const _minOrderPaise = 9900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: const EmptyStateView(
          icon: Icon(Icons.shopping_bag_outlined),
          title: 'Your cart is empty',
          subtitle: 'Add items from a shop to get started.',
        ),
      );
    }

    final shortfall = _minOrderPaise - cart.subtotalPaise;
    final belowMinimum = shortfall > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          ...cart.items.values.map(
            (item) => _CartRow(item: item, shopId: cart.shopId!),
          ),
          const Divider(height: AppSpacing.xxl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: AppTypography.bodyMedium),
              PriceText(amount: cart.subtotalPaise / 100),
            ],
          ),
          if (belowMinimum) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'Add ${(shortfall / 100).toStringAsFixed(0)}'
                ' more to meet the minimum order',
                style: AppTypography.caption.copyWith(color: AppColors.warning),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          TextActionButton(
            label: 'Add more items',
            onPressed: () => context.pop(),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: PrimaryButton(
          label: 'Proceed to Checkout',
          onPressed: belowMinimum ? null : () => context.push('/checkout'),
          expand: true,
        ),
      ),
    );
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.item, required this.shopId});
  final CartItem item;
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name, style: AppTypography.bodyMedium),
                PriceText(amount: item.product.pricePaise / 100),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => notifier.removeProduct(item.product.id),
              ),
              Text('${item.quantity}', style: AppTypography.data),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => notifier.addProduct(shopId, item.product),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
