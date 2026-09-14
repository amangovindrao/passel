import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Smart product catalog generator that automatically suggests popular products
/// matching the shop category with editable pricing before launch.
class CatalogSetupScreen extends ConsumerStatefulWidget {
  const CatalogSetupScreen({
    required this.shopId,
    required this.shopName,
    required this.category,
    required this.shopCode,
    super.key,
  });

  final String shopId;
  final String shopName;
  final String category;
  final String shopCode;

  @override
  ConsumerState<CatalogSetupScreen> createState() => _CatalogSetupScreenState();
}

class _CatalogSetupScreenState extends ConsumerState<CatalogSetupScreen> {
  late List<CatalogTemplateItem> _items;
  final Map<int, TextEditingController> _priceControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(CatalogTemplates.getSuggestionsForCategory(widget.category));
    for (var i = 0; i < _items.length; i++) {
      _priceControllers[i] = TextEditingController(
        text: _items[i].priceRupees.toInt().toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleItem(int index) {
    setState(() {
      _items[index] = _items[index].copyWith(
        isSelected: !_items[index].isSelected,
      );
    });
  }

  void _updatePrice(int index, String val) {
    final parsed = double.tryParse(val);
    if (parsed != null && parsed >= 0) {
      _items[index] = _items[index].copyWith(priceRupees: parsed);
    }
  }

  void _addCustomProduct() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '50');
    final unitCtrl = TextEditingController(text: 'piece');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.xl,
          top: AppSpacing.xl,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Custom Product',
              style: AppTypography.headlineSmall.copyWith(color: AppColors.paper),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Product Name',
              controller: nameCtrl,
              hintText: 'e.g. Special Homemade Cookies',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Price (₹)',
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppTextField(
                    label: 'Unit',
                    controller: unitCtrl,
                    hintText: 'e.g. piece, kg',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Add to List',
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  final price = double.tryParse(priceCtrl.text) ?? 50;
                  final newIndex = _items.length;
                  setState(() {
                    _items.add(
                      CatalogTemplateItem(
                        name: nameCtrl.text.trim(),
                        priceRupees: price,
                        unit: unitCtrl.text.trim().isEmpty ? 'piece' : unitCtrl.text.trim(),
                        category: widget.category,
                        description: 'Custom added item',
                        isSelected: true,
                      ),
                    );
                    _priceControllers[newIndex] = TextEditingController(
                      text: price.toInt().toString(),
                    );
                  });
                  Navigator.pop(ctx);
                }
              },
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _commitCatalog() async {
    setState(() => _saving = true);
    final client = ref.read(apiClientProvider);

    final selected = _items.where((it) => it.isSelected).toList();
    for (final item in selected) {
      try {
        await client.post<Map<String, dynamic>>(
          '/api/v1/shops/${widget.shopId}/products',
          data: {
            'name': item.name,
            'price_paise': (item.priceRupees * 100).toInt(),
            'unit': item.unit,
            'description': item.description,
            'category': item.category,
          },
          fromJson: (d) => d as Map<String, dynamic>,
        );
      } catch (_) {
        // Continue even if an item fails
      }
    }

    if (!mounted) return;
    ref.invalidate(productsProvider(widget.shopId));
    ref.invalidate(shopDataProvider);
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _items.where((i) => i.isSelected).length;

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
        title: Text(
          'Setup Catalog (${widget.category})',
          style: AppTypography.title.copyWith(color: AppColors.paper),
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/dashboard'),
            child: Text(
              'Skip',
              style: AppTypography.label.copyWith(color: AppColors.ash),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Shop ID banner & instructions
            Container(
              margin: const EdgeInsets.all(AppSpacing.lg),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.gold, size: 24),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recommended products for ${widget.category}',
                          style: AppTypography.label.copyWith(color: AppColors.gold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Uncheck any you don’t sell or edit prices to match your store.',
                          style: AppTypography.caption.copyWith(color: AppColors.ash),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Products checklist
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (ctx, i) {
                  final item = _items[i];
                  final priceCtrl = _priceControllers[i];

                  return Container(
                    decoration: BoxDecoration(
                      color: item.isSelected
                          ? AppColors.graphite
                          : AppColors.graphite.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: item.isSelected
                            ? AppColors.gold.withValues(alpha: 0.4)
                            : Colors.transparent,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: item.isSelected,
                          activeColor: AppColors.gold,
                          checkColor: AppColors.ink,
                          onChanged: (_) => _toggleItem(i),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: item.isSelected
                                      ? AppColors.paper
                                      : AppColors.ash,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${item.category} • ${item.unit}',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.ash,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // Price Editor
                        Container(
                          width: 80,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.ink,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: AppColors.mist),
                          ),
                          child: Row(
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Text(
                                  '₹',
                                  style: TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: priceCtrl,
                                  keyboardType: TextInputType.number,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.paper,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  onChanged: (v) => _updatePrice(i, v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Action footer
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      side: BorderSide(color: AppColors.ash.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: _addCustomProduct,
                    icon: const Icon(Icons.add, color: AppColors.paper),
                    label: Text(
                      '+ Add Custom Product',
                      style: AppTypography.label.copyWith(color: AppColors.paper),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: 'Finalize & Launch ($selectedCount items)',
                    onPressed: selectedCount > 0 && !_saving ? _commitCatalog : null,
                    loading: _saving,
                    expand: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
