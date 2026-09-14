import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Phone entry for shop owners.
class ShopPhoneScreen extends ConsumerStatefulWidget {
  const ShopPhoneScreen({super.key});

  @override
  ConsumerState<ShopPhoneScreen> createState() => _ShopPhoneScreenState();
}

class _ShopPhoneScreenState extends ConsumerState<ShopPhoneScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  String get _phone => _controller.text.trim();
  bool get _isValid => _phone.length == 10;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _quickTestLogin() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(phoneAuthProvider).verifyCode(
        tenDigitPhone: '9876543210',
        code: '123456',
      );
    } catch (_) {}
    if (!mounted) return;
    context.go('/dashboard');
  }

  Future<void> _sendOtp([String? overridePhone]) async {
    final phone = (overridePhone ?? _phone).trim();
    if (overridePhone != null) {
      _controller.text = overridePhone;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(phoneAuthProvider).sendCode(phone).timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
      if (!mounted) return;
      context.go('/otp?phone=$phone');
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send code. Check connection and try again.';
      });
    }
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
                'Register your shop',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'We will text you a 6-digit code to verify this number.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Phone number',
                controller: _controller,
                hintText: '10-digit mobile number',
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🇮🇳', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '+91',
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: 1,
                        height: 22,
                        color: Theme.of(context).dividerColor,
                      ),
                    ],
                  ),
                ),
                errorText: _error,
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                key: const ValueKey('send-otp'),
                label: 'Send OTP',
                onPressed: _isValid && !_sending ? () => _sendOtp() : null,
                loading: _sending,
                expand: true,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: _sending ? null : _quickTestLogin,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bolt, color: AppColors.gold, size: 20),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Quick Test Login (Demo Bypass)',
                      style: AppTypography.label.copyWith(color: AppColors.gold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.go('/shop-details'),
                  icon: const Icon(Icons.storefront_outlined, color: AppColors.gold),
                  label: Text(
                    'Want to create a new shop? Register here',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
