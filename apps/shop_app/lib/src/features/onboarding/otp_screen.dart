import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Code verification for a shop owner.
///
/// This screen did not exist. Phone entry sent the code and then navigated
/// straight to the name screen, so the owner was never actually signed in: no
/// Supabase session, no access token on the request, and registration failed
/// with a 401 the moment they typed their name. Every shop account was
/// unreachable as a result.
class ShopOtpScreen extends ConsumerStatefulWidget {
  const ShopOtpScreen({required this.phone, super.key});

  final String phone;

  @override
  ConsumerState<ShopOtpScreen> createState() => _ShopOtpScreenState();
}

class _ShopOtpScreenState extends ConsumerState<ShopOtpScreen> {
  final _fieldKey = GlobalKey<OtpCodeFieldState>();

  bool _checking = false;
  String? _error;

  Future<void> _verify(String code) async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await ref
          .read(phoneAuthProvider)
          .verifyCode(tenDigitPhone: widget.phone, code: code);
      if (!mounted) return;
      context.go('/name');
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.message;
      });
      // Only wipe the boxes when the code itself was wrong. Clearing six
      // correctly typed digits because the connection dropped is maddening.
      if (e.isWrongCode) _fieldKey.currentState?.clear();
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(phoneAuthProvider).sendCode(widget.phone);
      if (!mounted) return;
      _fieldKey.currentState?.clear();
      AppSnackbar.show(context, message: 'Code sent again');
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
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
                'Enter the code',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Sent to +91 ${widget.phone}',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),
              OtpCodeField(
                key: _fieldKey,
                enabled: !_checking,
                errorText: _error,
                onCompleted: _verify,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_checking)
                const Center(child: GoldPulseIndicator(size: 12)),
              const Spacer(),
              TextActionButton(
                label: 'Resend code',
                onPressed: _checking ? null : _resend,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
