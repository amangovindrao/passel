import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Name entry — creates the delivery partner profile.
class RiderNameScreen extends ConsumerStatefulWidget {
  const RiderNameScreen({super.key});

  @override
  ConsumerState<RiderNameScreen> createState() => _RiderNameScreenState();
}

class _RiderNameScreenState extends ConsumerState<RiderNameScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _isValid => _controller.text.trim().length >= 2;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Registration is what creates the backend account behind the Supabase
    // login, and it creates the partner profile too — so there is no separate
    // profile call to make afterwards.
    final result = await AuthRepository(
      ref.read(apiClientProvider),
    ).register(name: _controller.text.trim(), role: PaaselRole.deliveryPartner);

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
                "What's your name?",
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Shops and customers will see this.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Full name',
                controller: _controller,
                hintText: 'As it appears on your ID',
                errorText: _error,
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Continue',
                onPressed: _isValid ? _submit : null,
                loading: _loading,
                expand: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: BorderSide(
                      color: AppColors.gold.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  onPressed: () => context.go('/kyc'),
                  child: Text(
                    'Continue in Offline / Demo Mode',
                    style: AppTypography.label.copyWith(color: AppColors.gold),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
