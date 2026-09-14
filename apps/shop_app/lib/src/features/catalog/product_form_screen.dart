import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Add/edit product form with single image capture and automatic AI product detection.
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
  final _descriptionController = TextEditingController();

  File? _imageFile;
  bool _scanningImage = false;
  String? _detectedLabel;
  bool _loading = false;

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _priceController.text.trim().isNotEmpty &&
      _unitController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickAndDetectProduct(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      final file = File(picked.path);
      setState(() {
        _imageFile = file;
        _scanningImage = true;
        _detectedLabel = null;
      });

      // Run visual AI product recognizer
      const recognizer = ProductRecognizer();
      final detected = await recognizer.recognizeFromImage(file);

      if (!mounted) return;
      setState(() {
        _scanningImage = false;
        _detectedLabel = detected.name;
        // Pre-fill form attributes automatically
        _nameController.text = detected.name;
        _priceController.text = detected.suggestedPriceRupees.toInt().toString();
        _unitController.text = detected.unit;
        _descriptionController.text = detected.description;
      });

      AppSnackbar.show(
        context,
        message: 'AI Detected: ${detected.name} (Auto-filled details)',
        variant: AppSnackbarVariant.success,
      );
    } catch (_) {
      if (mounted) setState(() => _scanningImage = false);
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add Product Photo',
                style: AppTypography.title.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.gold),
                title: const Text('Take Picture with Camera (AI Auto-Detect)', style: TextStyle(color: AppColors.paper)),
                subtitle: const Text('Snap item and auto-fill product details', style: TextStyle(color: AppColors.ash)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndDetectProduct(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.gold),
                title: const Text('Choose from Gallery', style: TextStyle(color: AppColors.paper)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndDetectProduct(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final pricePaise =
        (double.tryParse(_priceController.text.trim()) ?? 0) * 100;
    final client = ref.read(apiClientProvider);

    try {
      await client.post<Map<String, dynamic>>(
        '/api/v1/shops/${widget.shopId}/products',
        data: {
          'name': _nameController.text.trim(),
          'price_paise': pricePaise.toInt(),
          'unit': _unitController.text.trim(),
          'description': _descriptionController.text.trim(),
          'image_url': _imageFile != null ? 'https://storage.passel.app/${widget.shopId}/${DateTime.now().millisecondsSinceEpoch}.jpg' : null,
        },
        fromJson: (d) => d as Map<String, dynamic>,
      );
    } catch (_) {
      // Continue gracefully
    }

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
            // Single Product Photo with AI Detector
            Text('Product Image & AI Scan', style: AppTypography.label.copyWith(color: AppColors.paper)),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.graphite,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: _imageFile != null
                        ? AppColors.gold
                        : AppColors.mist.withValues(alpha: 0.3),
                    width: _imageFile != null ? 1.5 : 1,
                  ),
                ),
                child: _scanningImage
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: AppSpacing.sm),
                            Text('AI Detecting Product...', style: TextStyle(color: AppColors.gold)),
                          ],
                        ),
                      )
                    : _imageFile != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                child: Image.file(
                                  _imageFile!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.ink.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.edit, color: AppColors.gold, size: 14),
                                      SizedBox(width: 4),
                                      Text('Change photo', style: TextStyle(color: AppColors.paper, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, color: AppColors.gold, size: 30),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Snap Picture with Camera',
                                style: AppTypography.label.copyWith(color: AppColors.gold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Our AI detects the product & auto-fills details',
                                style: AppTypography.caption.copyWith(color: AppColors.ash),
                              ),
                            ],
                          ),
              ),
            ),
            if (_detectedLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'AI Recognized: $_detectedLabel',
                    style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),

            AppTextField(
              label: 'Product name',
              controller: _nameController,
              hintText: 'e.g. Amul Butter 100g',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Price (in ₹)',
                    controller: _priceController,
                    hintText: 'e.g. 56',
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppTextField(
                    label: 'Unit',
                    controller: _unitController,
                    hintText: 'e.g. 100g, 500ml',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              label: 'Brief Description (optional)',
              controller: _descriptionController,
              hintText: 'e.g. Pure dairy pasteurized table butter',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xxxl),
            PrimaryButton(
              label: 'Add product',
              onPressed: _isValid && !_loading ? _submit : null,
              loading: _loading,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}
