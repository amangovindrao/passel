import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Home screen: address selector, search, category filter, shop list.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(nearbyShopsProvider);
    final activeAddress = ref.watch(activeAddressProvider);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showAddressSheet,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 18, color: AppColors.gold),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  activeAddress?.addressText ?? 'Select address',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {}, // Phase 13
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(nearbyShopsProvider),
        child: CustomScrollView(
          slivers: [
            // Search field
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: AppTextField(
                  label: '',
                  controller: _searchController,
                  hintText: 'Search shops, categories...',
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (value) {
                    ref.read(shopSearchQueryProvider.notifier).state =
                        value.isEmpty ? null : value;
                  },
                ),
              ),
            ),
            // Shop list
            shopsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  SliverFillRemaining(child: Center(child: Text('Error: $e'))),
              data: (shops) {
                if (shops.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyStateView(
                      icon: Icon(Icons.storefront_outlined),
                      title: 'No shops here yet',
                      subtitle:
                          'Check back soon \u2014 we\u2019re expanding fast.',
                    ),
                  );
                }
                final open = shops.where((s) => s.isOpen).toList();
                final closed = shops.where((s) => !s.isOpen).toList();
                return SliverList(
                  delegate: SliverChildListDelegate([
                    if (open.isNotEmpty) ...[
                      _sectionHeader('Open now'),
                      ...open.map((s) => _ShopCard(shop: s)),
                    ],
                    if (closed.isNotEmpty) ...[
                      _sectionHeader('Currently closed'),
                      ...closed.map((s) => _ShopCard(shop: s, muted: true)),
                    ],
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.sm,
    ),
    child: Text(title, style: AppTypography.label),
  );

  void _showAddressSheet() {
    AppBottomSheet.show<void>(
      context: context,
      builder: (_) => const _AddressSelector(),
    );
  }
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop, this.muted = false});
  final NearbyShop shop;
  final bool muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distanceKm = (shop.distanceM / 1000).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: ScaleOnCard(
        onTap: () => context.push('/shop/${shop.id}'),
        child: Opacity(
          opacity: muted ? 0.55 : 1.0,
          child: Row(
            children: [
              // Placeholder icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.storefront, color: AppColors.gold),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: AppTypography.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      shop.category,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ash,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$distanceKm km',
                    style: AppTypography.data.copyWith(color: AppColors.ash),
                  ),
                  const SizedBox(height: 4),
                  if (shop.isOpen)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GoldPulseIndicator(size: 6),
                        SizedBox(width: 4),
                        StatusBadge(status: StatusBadgeState.readyForPickup),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressSelector extends ConsumerWidget {
  const _AddressSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressListProvider);
    return addresses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (list) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deliver to', style: AppTypography.title),
          const SizedBox(height: AppSpacing.lg),
          ...list.map(
            (a) => ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(a.label),
              subtitle: Text(
                a.addressText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                ref.read(activeAddressProvider.notifier).state = a;
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextActionButton(
            label: '+ Add new address',
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/location-setup');
            },
          ),
        ],
      ),
    );
  }
}
