import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
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

  Future<void> _submit() async {
    final phone = _controller.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(phoneAuthProvider).sendCode(phone);
      if (!mounted) return;
      context.go('/otp?phone=$phone');
    } on PhoneAuthFailure catch (e) {
      // Was `on AuthException`, which let a network error escape and leave the
      // button spinning with nothing on screen to explain it.
      if (!mounted) return;
      setState(() {
        _loading = false;
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
                'Start earning with Paasel',
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
                hintText: '10-digit number',
                keyboardType: TextInputType.phone,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.lg),
                  child: Center(child: Text('+91')),
                ),
                errorText: _error,
                onChanged: (_) => setState(() {}),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Send OTP',
                onPressed: _isValid ? _submit : null,
                loading: _loading,
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
