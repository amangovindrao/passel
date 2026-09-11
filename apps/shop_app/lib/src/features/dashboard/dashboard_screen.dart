import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Shop dashboard: subscription banner, stats, open toggle, nav.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(shopDataProvider);

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: shopAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Error: $e',
              style: const TextStyle(color: AppColors.paper),
            ),
          ),
          data: (shop) => _DashboardBody(shop: shop),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.shop});
  final ShopData shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `isOpen` is nullable on the wire (absent until a shop exists); treat a
    // missing value as closed.
    final isOpen = shop.isOpen ?? false;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        // Header
        Text(
          shop.name ?? 'Your Shop',
          style: AppTypography.headline.copyWith(color: AppColors.paper),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Subscription banner
        if (shop.subscriptionStatus == 'trial') ...[
          ScaleOnCard(
            onTap: () => context.push('/subscription'),
            child: Row(
              children: [
                const Icon(Icons.star_outline, color: AppColors.gold),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Free trial active', style: AppTypography.label),
                      if (shop.trialEndDate != null)
                        Text(
                          'Ends ${shop.trialEndDate!.substring(0, 10)}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'Choose plan',
                  style: AppTypography.label.copyWith(color: AppColors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // Open toggle
        ScaleOnCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOpen) const GoldPulseIndicator(),
                  if (isOpen) const SizedBox(width: AppSpacing.sm),
                  Text(
                    isOpen ? 'Shop is Open' : 'Shop is Closed',
                    style: AppTypography.bodyMedium,
                  ),
                ],
              ),
              Switch(
                value: shop.isOpen ?? false,
                activeColor: AppColors.gold,
                onChanged: (v) => _toggleOpen(ref, v),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // Navigation tiles
        _NavTile(
          icon: Icons.inventory_2_outlined,
          label: 'Catalog',
          onTap: () {
            if (shop.shopId != null) {
              context.push('/catalog/${shop.shopId}');
            }
          },
        ),
        _NavTile(
          icon: Icons.receipt_long_outlined,
          label: 'Orders',
          onTap: () {
            if (shop.shopId != null) {
              context.push('/orders/${shop.shopId}');
            }
          },
        ),
        _NavTile(
          icon: Icons.credit_card_outlined,
          label: 'Subscription',
          onTap: () => context.push('/subscription'),
        ),
        _NavTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap: () {}, // Phase later
        ),
      ],
    );
  }

  Future<void> _toggleOpen(WidgetRef ref, bool value) async {
    if (shop.shopId == null) return;
    final client = ref.read(apiClientProvider);
    await client.post<Map<String, dynamic>>(
      '/api/v1/shops/${shop.shopId}/toggle-open',
      data: {'is_open': value},
      fromJson: (d) => d as Map<String, dynamic>,
    );
    ref.invalidate(shopDataProvider);
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ScaleOnCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold),
            const SizedBox(width: AppSpacing.lg),
            Text(label, style: AppTypography.bodyMedium),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.ash),
          ],
        ),
      ),
    );
  }
}
