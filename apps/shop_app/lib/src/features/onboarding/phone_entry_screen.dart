import 'package:core/core.dart';
import 'package:flutter/material.dart';
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

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(phoneAuthProvider).sendCode(_phone);
      if (!mounted) return;
      // To the code screen, not straight to /name. Skipping verification left
      // the owner with no session at all, and registration then failed with a
      // 401 they had no way to interpret.
      context.go('/otp?phone=$_phone');
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
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
                hintText: '10-digit mobile',
                keyboardType: TextInputType.phone,
                errorText: _error,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.lg),
                  child: Center(child: Text('+91')),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                key: const ValueKey('send-otp'),
                label: 'Send OTP',
                onPressed: _isValid && !_sending ? _sendOtp : null,
                loading: _sending,
                expand: true,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
