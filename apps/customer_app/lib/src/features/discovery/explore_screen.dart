import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Explore Screen: browse categories, discover local neighborhood stores,
/// and post "Can't find it?" requests to local shopkeepers.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchController = TextEditingController();
  String? _selectedCategory;

  final _categories = const [
    ('All', Icons.grid_view_rounded, AppColors.softPink),
    ('Kirana', Icons.storefront_rounded, AppColors.peach),
    ('Medical', Icons.local_pharmacy_rounded, AppColors.mint),
    ('Dairy & Bakery', Icons.cake_rounded, AppColors.lavender),
    ('Fresh Veggies', Icons.eco_rounded, AppColors.mint),
    ('Snacks', Icons.fastfood_rounded, AppColors.blush),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(nearbyShopsProvider);
    final favShopIds = ref.watch(favoriteShopsProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (isPinkie) ...[
              const TwinkleSparkle(size: 16, color: AppColors.deepBlush),
              const SizedBox(width: AppSpacing.sm),
            ] else ...[
              const Icon(Icons.explore_outlined, size: 20, color: AppColors.gold),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text('Explore Neighborhood', style: AppTypography.title),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(nearbyShopsProvider),
        child: CustomScrollView(
          slivers: [
            // Search Bar
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: AppTextField(
                  label: '',
                  controller: _searchController,
                  hintText: 'Search shops, groceries, medicines...',
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (val) {
                    ref.read(shopSearchQueryProvider.notifier).state =
                        val.isEmpty ? null : val;
                  },
                ),
              ),
            ),

            // Category Horizontal Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected =
                        (_selectedCategory == null && cat.$1 == 'All') ||
                        _selectedCategory == cat.$1;

                    return FilterChip(
                      avatar: Icon(
                        cat.$2,
                        size: 16,
                        color: isSelected ? Colors.white : AppColors.ink,
                      ),
                      label: Text(cat.$1),
                      selected: isSelected,
                      selectedColor: AppColors.deepBlush,
                      backgroundColor: cat.$3.withValues(alpha: 0.35),
                      labelStyle: AppTypography.caption.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.ink,
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.deepBlush
                            : AppColors.ash.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = cat.$1 == 'All' ? null : cat.$1;
                        });
                      },
                    );
                  },
                ),
              ),
            ),

            // "Can't find it? Ask nearby shops" Card
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: _buildProductRequestCard(context),
              ),
            ),

            // Shop Results Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  _selectedCategory == null
                      ? 'Local Stores Nearby'
                      : '$_selectedCategory Stores',
                  style: AppTypography.label,
                ),
              ),
            ),

            // Shops List
            shopsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  SliverFillRemaining(child: Center(child: Text('Error: $e'))),
              data: (shops) {
                var filtered = shops;
                if (_selectedCategory != null) {
                  filtered = filtered
                      .where(
                        (s) => s.category.toLowerCase().contains(
                          _selectedCategory!.toLowerCase(),
                        ),
                      )
                      .toList();
                }

                if (filtered.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPinkie)
                            const SmilingGroceryIllustration(size: 72)
                          else
                            const Icon(
                              Icons.storefront_outlined,
                              size: 48,
                              color: AppColors.ash,
                            ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'No stores match this category right now',
                            style: AppTypography.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Try clearing the filter or requesting an item below.',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.ash,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final shop = filtered[index];
                    final isFav = favShopIds.contains(shop.id);
                    final distanceKm = (shop.distanceM / 1000).toStringAsFixed(
                      1,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: ScaleOnCard(
                        onTap: () => context.push('/shop/${shop.id}'),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: AppColors.ash.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.softPink.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.storefront_rounded,
                                  color: AppColors.deepBlush,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      shop.name,
                                      style: AppTypography.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${shop.category} • $distanceKm km away',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.ash,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TinyFloatingHeartButton(
                                isFav: isFav,
                                isEnabled:
                                    ref.watch(isPinkieThemeActiveProvider),
                                onToggle: () {
                                  ref
                                      .read(favoriteShopsProvider.notifier)
                                      .toggleFavorite(shop.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: filtered.length),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRequestCard(BuildContext context) {
    return AppGlassCard(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      backgroundColor: AppColors.blush.withValues(alpha: 0.25),
      borderColor: AppColors.deepBlush.withValues(alpha: 0.3),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.softPink,
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: AppColors.deepBlush,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Can\'t find an item?',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const CuteSparkle(size: 10, color: AppColors.deepBlush),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Broadcast a custom request to 3 nearby shops.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ash,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepBlush,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            onPressed: () => _showProductRequestSheet(context),
            child: const Text(
              'Ask',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showProductRequestSheet(BuildContext context) {
    final itemController = TextEditingController();
    final noteController = TextEditingController();

    AppBottomSheet.show<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CuteSparkle(size: 16, color: AppColors.deepBlush),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Ask Nearby Shops', style: AppTypography.title),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your request goes to active local shopkeepers within 100m. If stocked, they will notify you!',
              style: AppTypography.caption.copyWith(color: AppColors.ash),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Product Name',
              controller: itemController,
              hintText: 'e.g. A2 Desi Cow Milk 500ml',
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Optional Note / Brand',
              controller: noteController,
              hintText: 'e.g. Any organic brand is fine',
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Broadcast Request',
              onPressed: () {
                final item = itemController.text.trim();
                if (item.isEmpty) return;

                ref
                    .read(productRequestProvider.notifier)
                    .addRequest(
                      ProductRequestItem(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        productName: item,
                        notes: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                        status: 'Broadcasted to 3 shops',
                        createdAt: DateTime.now(),
                      ),
                    );

                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.deepBlush,
                    content: Text(
                      'Request for "$item" broadcast to local shops! \u2728',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
