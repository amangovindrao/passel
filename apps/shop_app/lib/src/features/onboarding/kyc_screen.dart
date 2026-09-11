import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// KYC: ID proof upload + bank details.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final _bankController = TextEditingController();
  final _ifscController = TextEditingController();
  bool _loading = false;
  bool _uploaded = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    final client = ref.read(apiClientProvider);
    await client.post<Map<String, dynamic>>(
      '/api/v1/shop-owners/kyc',
      data: {
        'id_proof_url': 'https://storage.example.com/id_proof.jpg',
        'bank_account_number': _bankController.text.trim(),
        'bank_ifsc': _ifscController.text.trim(),
      },
      fromJson: (d) => d as Map<String, dynamic>,
    );
    if (mounted) context.go('/shop-details');
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
                'Verify your identity',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.xxl),
              // ID upload
              ScaleOnCard(
                onTap: () => setState(() => _uploaded = true),
                child: Row(
                  children: [
                    Icon(
                      _uploaded ? Icons.check_circle : Icons.upload_file,
                      color: _uploaded ? AppColors.success : AppColors.gold,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      _uploaded ? 'ID uploaded' : 'Upload ID proof',
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(
                label: 'Bank account number',
                controller: _bankController,
                hintText: 'Your settlement account',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(
                label: 'IFSC code',
                controller: _ifscController,
                hintText: 'e.g. SBIN0001234',
              ),
              const SizedBox(height: AppSpacing.xxxl),
              PrimaryButton(
                label: 'Submit for review',
                onPressed: _uploaded ? _submit : null,
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
