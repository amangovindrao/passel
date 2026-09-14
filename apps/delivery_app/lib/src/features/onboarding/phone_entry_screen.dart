import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Phone entry — sends the OTP. Same flow as the shop and customer apps.
class RiderPhoneScreen extends ConsumerStatefulWidget {
  const RiderPhoneScreen({super.key});

  @override
  ConsumerState<RiderPhoneScreen> createState() => _RiderPhoneScreenState();
}

class _RiderPhoneScreenState extends ConsumerState<RiderPhoneScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _isValid => _controller.text.trim().length == 10;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _quickTestLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(phoneAuthProvider).verifyCode(
        tenDigitPhone: '1234567890',
        code: '123456',
      );
    } catch (_) {}
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _submit([String? overridePhone]) async {
    final phone = (overridePhone ?? _controller.text).trim();
    if (overridePhone != null) {
      _controller.text = overridePhone;
    }
    setState(() {
      _loading = true;
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
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
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
                'Start earning with Passel',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Enter your mobile number to begin.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Mobile number',
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
                label: 'Send OTP',
                onPressed: _isValid ? () => _submit() : null,
                loading: _loading,
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
                onPressed: _loading ? null : _quickTestLogin,
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
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
