import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Cart screen with multi-shop grouping, anchor indicators, 100m bundling,
/// quantity steppers and minimum order validation.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  static const _minOrderPaise = 9900;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cart')),
        body: EmptyStateView(
          icon: isPinkie
              ? const CuteEmptyCartIllustration(size: 96)
              : const Icon(
                  Icons.shopping_bag_outlined,
                  size: 56,
                  color: AppColors.gold,
                ),
          title:
              isPinkie ? 'Your cart is feeling lonely!' : 'Your cart is empty',
          subtitle: isPinkie
              ? 'Fill me up with tasty snacks and goodies ✨'
              : 'Add items from a shop to get started.',
        ),
      );
    }

    final shortfall = _minOrderPaise - cart.subtotalPaise;
    final belowMinimum = shortfall > 0;
    final anchorId = cart.anchorShopId;
    final bundleShopsAsync = anchorId != null
        ? ref.watch(eligibleBundleShopsProvider(anchorId))
        : const AsyncValue.data(<NearbyShop>[]);

    final itemsByShop = cart.itemsByShop;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          cart.isMultiShop
              ? 'Multi-Shop Cart (${itemsByShop.length} shops)'
              : 'Cart',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Items grouped by shop
          ...itemsByShop.entries.map((entry) {
            final shopId = entry.key;
            final items = entry.value;
            final isAnchor = shopId == cart.anchorShopId;
            final shopName =
                cart.shopNames[shopId] ??
                (isAnchor ? 'Anchor Shop' : 'Nearby Partner Shop');

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isAnchor
                      ? AppColors.gold.withValues(alpha: 0.4)
                      : AppColors.ash.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
                color: isAnchor
                    ? AppColors.gold.withValues(alpha: 0.03)
                    : Colors.transparent,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.storefront,
                        size: 18,
                        color: isAnchor ? AppColors.gold : AppColors.ash,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          shopName,
                          style: AppTypography.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isAnchor
                              ? AppColors.gold.withValues(alpha: 0.15)
                              : AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          isAnchor ? 'Anchor Shop' : 'Within 100m',
                          style: AppTypography.caption.copyWith(
                            color: isAnchor
                                ? AppColors.gold
                                : AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: AppSpacing.md),
                  ...items.map((item) => _CartRow(item: item, shopId: shopId)),
                ],
              ),
            );
          }),

          // Eligible bundle shops within 100m
          bundleShopsAsync.when(
            data: (bundleShops) {
              // Filter out shops already in cart
              final unadded = bundleShops
                  .where((s) => !cart.allShopIds.contains(s.id))
                  .toList();
              if (unadded.isEmpty) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.lg,
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 18,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Bundle & Save Delivery!',
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'These shops are within 100m of your anchor shop. Add items for a single delivery fee!',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ash,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: unadded.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final shop = unadded[index];
                          return ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text('${shop.name} (${shop.category})'),
                            onPressed: () => context.push('/shop/${shop.id}'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const Divider(height: AppSpacing.xl),
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
                onPressed: () => notifier.addProduct(
                  shopId,
                  item.product,
                  shopName: item.shopName,
                  isBundled: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
