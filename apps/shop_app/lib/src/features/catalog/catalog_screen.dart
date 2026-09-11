import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Product catalog management: list, toggle stock, add/edit.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({required this.shopId, super.key});
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider(shopId));

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        title: const Text('Catalog'),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (products) {
          if (products.isEmpty) {
            return EmptyStateView(
              icon: const Icon(Icons.inventory_2_outlined),
              title: 'No products yet',
              subtitle: 'Add your first item to start selling.',
              actionLabel: 'Add product',
              onAction: () => context.push('/product/new/$shopId'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: products.length,
            itemBuilder: (_, i) =>
                _ProductTile(product: products[i], shopId: shopId),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.gold,
        onPressed: () => context.push('/product/new/$shopId'),
        child: const Icon(Icons.add, color: AppColors.ink),
      ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product, required this.shopId});
  final ProductItem product;
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ScaleOnCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: AppTypography.bodyMedium),
                  PriceText(amount: product.pricePaise / 100),
                ],
              ),
            ),
            // Stock toggle
            Switch(
              value: product.isAvailable,
              activeColor: AppColors.gold,
              onChanged: (v) => _toggleStock(ref, v),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStock(WidgetRef ref, bool available) async {
    final client = ref.read(apiClientProvider);
    await client.patch<Map<String, dynamic>>(
      '/api/v1/products/${product.id}',
      data: {'stock_status': available ? 'available' : 'unavailable'},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    ref.invalidate(productsProvider(shopId));
  }
}
