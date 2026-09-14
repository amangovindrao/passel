import 'dart:async';

import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// OTP entry, with a resend cooldown.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.phone, super.key});
  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _cooldown = 30;

  final _fieldKey = GlobalKey<OtpCodeFieldState>();

  bool _checking = false;
  String? _error;
  int _resendSeconds = _cooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendSeconds = _cooldown;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

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
      // Only when the code itself was rejected. A dropped connection must not
      // throw away six digits the user typed correctly.
      if (e.isWrongCode) _fieldKey.currentState?.clear();
    }
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await ref.read(phoneAuthProvider).sendCode(widget.phone);
      if (!mounted) return;
      _fieldKey.currentState?.clear();
      _startResendTimer();
      AppSnackbar.show(
        context,
        message: 'OTP sent again',
        variant: AppSnackbarVariant.success,
      );
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.huge),
              Text('Enter OTP', style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Sent to +91 ${widget.phone}',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxxl),
              Center(
                child: InkWell(
                  onTap: _checking ? null : () => _verify('123456'),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, size: 16, color: AppColors.gold),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Test mode: Tap to auto-fill 123456',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              OtpCodeField(
                key: _fieldKey,
                enabled: !_checking,
                errorText: _error,
                onCompleted: _verify,
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (_checking) const Center(child: CircularProgressIndicator()),
              const Spacer(),
              Center(
                child: TextActionButton(
                  label: _resendSeconds > 0
                      ? 'Resend OTP in ${_resendSeconds}s'
                      : 'Resend OTP',
                  onPressed: _resendSeconds <= 0 && !_checking ? _resend : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
