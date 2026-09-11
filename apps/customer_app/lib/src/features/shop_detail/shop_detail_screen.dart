import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Shop detail: product list grouped by category, local cart state.
class ShopDetailScreen extends ConsumerWidget {
  const ShopDetailScreen({required this.shopId, super.key});
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(shopDetailProvider(shopId));
    final cart = ref.watch(cartProvider);

    return detailAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('Error loading shop: $e'))),
      data: (shop) => Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(shop.name, style: AppTypography.label),
                background: Container(color: AppColors.cloud),
              ),
            ),
            // Shop info
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    StatusBadge(
                      status: shop.isOpen
                          ? StatusBadgeState.readyForPickup
                          : StatusBadgeState.cancelled,
                      label: shop.isOpen ? 'Open' : 'Closed',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(shop.category, style: AppTypography.caption),
                  ],
                ),
              ),
            ),
            if (!shop.isOpen)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Closed right now — browse the menu for later',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ),
            // Products grouped by category
            ...shop.products.entries.map(
              (entry) => SliverToBoxAdapter(
                child: _ProductCategory(
                  category: entry.key,
                  products: entry.value,
                  shopId: shopId,
                  shopOpen: shop.isOpen,
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
        // Sticky cart bar
        bottomNavigationBar: cart.shopId == shopId && !cart.isEmpty
            ? _CartBar(cart: cart)
            : null,
      ),
    );
  }
}

class _ProductCategory extends ConsumerWidget {
  const _ProductCategory({
    required this.category,
    required this.products,
    required this.shopId,
    required this.shopOpen,
  });
  final String category;
  final List<ShopProduct> products;
  final String shopId;
  final bool shopOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text(category, style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          ...products.map(
            (p) => _ProductRow(
              product: p,
              shopId: shopId,
              enabled: shopOpen && p.isAvailable,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends ConsumerWidget {
  const _ProductRow({
    required this.product,
    required this.shopId,
    required this.enabled,
  });
  final ShopProduct product;
  final String shopId;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final cartItem = cart.items[product.id];
    final qty = cartItem?.quantity ?? 0;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: AppTypography.bodyMedium),
                  if (!product.isAvailable)
                    Text(
                      'Out of stock',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                ],
              ),
            ),
            PriceText(amount: product.pricePaise / 100),
            const SizedBox(width: AppSpacing.md),
            if (enabled)
              qty == 0
                  ? _AddButton(onTap: () => _addToCart(ref))
                  : _QuantityStepper(
                      qty: qty,
                      onAdd: () => _addToCart(ref),
                      onRemove: () => ref
                          .read(cartProvider.notifier)
                          .removeProduct(product.id),
                    ),
          ],
        ),
      ),
    );
  }

  void _addToCart(WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    if (notifier.wouldConflict(shopId)) {
      // Show confirmation dialog
      _showConflictDialog(ref);
    } else {
      notifier.addProduct(shopId, product);
    }
  }

  void _showConflictDialog(WidgetRef ref) {
    // In a real implementation, this would use showDialog
    // For now, just clear and add
    ref.read(cartProvider.notifier).clearAndAdd(shopId, product);
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.gold),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          'Add',
          style: AppTypography.label.copyWith(color: AppColors.gold),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gold),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(Icons.remove, size: 16, color: AppColors.gold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text('$qty', style: AppTypography.data),
          ),
          InkWell(
            onTap: onAdd,
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(Icons.add, size: 16, color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});
  final CartState cart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cart.itemCount} item${cart.itemCount > 1 ? 's' : ''}',
                    style: AppTypography.label.copyWith(color: AppColors.ink),
                  ),
                  PriceText(amount: cart.subtotalPaise / 100),
                ],
              ),
            ),
            PrimaryButton(
              label: 'View Cart',
              onPressed: () {}, // Phase 6
            ),
          ],
        ),
      ),
    );
  }
}
