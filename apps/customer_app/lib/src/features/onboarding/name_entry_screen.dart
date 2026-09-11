import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Name entry after first-time OTP.
class NameEntryScreen extends ConsumerStatefulWidget {
  const NameEntryScreen({super.key});

  @override
  ConsumerState<NameEntryScreen> createState() => _NameEntryScreenState();
}

class _NameEntryScreenState extends ConsumerState<NameEntryScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  bool get _isValid => _controller.text.trim().length >= 2;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Creates the backend account behind the Supabase login, plus the customer
    // profile. Until this succeeds every other endpoint answers 401.
    final result = await AuthRepository(
      ref.read(apiClientProvider),
    ).register(name: _controller.text.trim(), role: PaaselRole.customer);

    if (!mounted) return;
    result.when(
      success: (Registration _) => context.go('/location-setup'),
      failure: (AppError e) => setState(() {
        _loading = false;
        _error = e.message;
      }),
    );
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
              Text('What should we call you?', style: AppTypography.headline),
              const SizedBox(height: AppSpacing.xxl),
              AppTextField(
                label: 'Your name',
                controller: _controller,
                hintText: 'Enter your name',
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
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
