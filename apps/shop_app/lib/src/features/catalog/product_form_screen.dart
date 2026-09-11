import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Add/edit product form.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({required this.shopId, super.key});
  final String shopId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _unitController = TextEditingController();
  bool _loading = false;

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _priceController.text.trim().isNotEmpty &&
      _unitController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _loading = true);
    final pricePaise =
        (double.tryParse(_priceController.text.trim()) ?? 0) * 100;
    final client = ref.read(apiClientProvider);
    await client.post<Map<String, dynamic>>(
      '/api/v1/shops/${widget.shopId}/products',
      data: {
        'name': _nameController.text.trim(),
        'price_paise': pricePaise.toInt(),
        'unit': _unitController.text.trim(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    if (mounted) {
      ref.invalidate(productsProvider(widget.shopId));
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        title: const Text('Add Product'),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ListView(
          children: [
            AppTextField(
              label: 'Product name',
              controller: _nameController,
              hintText: 'e.g. Paneer 200g',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Price (in rupees)',
              controller: _priceController,
              hintText: 'e.g. 120',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Unit',
              controller: _unitController,
              hintText: 'e.g. piece, kg, 500ml',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            PrimaryButton(
              label: 'Add product',
              onPressed: _isValid ? _submit : null,
              loading: _loading,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}
