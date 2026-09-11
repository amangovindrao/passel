import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Shop details: name, category, location pin, operating hours.
class ShopDetailsScreen extends ConsumerStatefulWidget {
  const ShopDetailsScreen({super.key});

  @override
  ConsumerState<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends ConsumerState<ShopDetailsScreen> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  double _lat = 12.9716;
  double _lng = 77.5946;
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    final client = ref.read(apiClientProvider);
    await client.post<Map<String, dynamic>>(
      '/api/v1/shops',
      data: {
        'name': _nameController.text.trim(),
        'category': _categoryController.text.trim(),
        'lat': _lat,
        'lng': _lng,
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    if (mounted) context.go('/pending');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ListView(
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Your shop',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Shop name',
                controller: _nameController,
                hintText: 'What customers will see',
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'Category',
                controller: _categoryController,
                hintText: 'e.g. Grocery, Pharmacy, Food',
              ),
              const SizedBox(height: AppSpacing.xl),
              // Map pin placeholder
              Text(
                'Shop location',
                style: AppTypography.label.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.sm),
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _lat += details.delta.dy * 0.0001;
                    _lng += details.delta.dx * 0.0001;
                  });
                },
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: AppColors.graphite,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_pin,
                          color: AppColors.gold,
                          size: 36,
                        ),
                        Text(
                          '${_lat.toStringAsFixed(4)}, '
                          '${_lng.toStringAsFixed(4)}',
                          style: AppTypography.data.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Drag to adjust',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              PrimaryButton(
                label: 'Create shop',
                onPressed: _nameController.text.trim().isNotEmpty
                    ? _submit
                    : null,
                loading: _loading,
                expand: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
