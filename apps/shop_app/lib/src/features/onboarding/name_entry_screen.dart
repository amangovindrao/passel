import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Name entry for shop owner.
class ShopNameScreen extends ConsumerStatefulWidget {
  const ShopNameScreen({super.key});

  @override
  ConsumerState<ShopNameScreen> createState() => _ShopNameScreenState();
}

class _ShopNameScreenState extends ConsumerState<ShopNameScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Creates the backend account behind the Supabase login, plus the shop
    // owner profile — so no separate profile call is needed.
    final result = await AuthRepository(
      ref.read(apiClientProvider),
    ).register(name: _controller.text.trim(), role: PaaselRole.shopOwner);

    if (!mounted) return;
    result.when(
      success: (Registration _) => context.go('/kyc'),
      failure: (AppError e) => setState(() {
        _loading = false;
        _error = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.huge),
              Text(
                'Your name',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Full name',
                controller: _controller,
                hintText: 'As on your ID',
                errorText: _error,
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                onPressed: _controller.text.trim().length >= 2 ? _submit : null,
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
