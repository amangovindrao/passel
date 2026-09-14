import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Name entry after first-time OTP with optional vibe selection.
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
    final currentVibe = ref.watch(customerThemePersonalityProvider);

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
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Choose App Vibe',
                style: AppTypography.label.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        ref
                            .read(customerThemePersonalityProvider.notifier)
                            .setPersonality(CustomerThemePersonality.classic);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: currentVibe == CustomerThemePersonality.classic
                                ? AppColors.gold
                                : AppColors.ash.withValues(alpha: 0.25),
                            width: currentVibe == CustomerThemePersonality.classic ? 2 : 1,
                          ),
                          color: currentVibe == CustomerThemePersonality.classic
                              ? AppColors.gold.withValues(alpha: 0.1)
                              : Colors.transparent,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: AppColors.gold,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                'Classic Sleek',
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () {
                        ref
                            .read(customerThemePersonalityProvider.notifier)
                            .setPersonality(CustomerThemePersonality.pinkie);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: currentVibe == CustomerThemePersonality.pinkie
                                ? AppColors.deepBlush
                                : AppColors.ash.withValues(alpha: 0.25),
                            width: currentVibe == CustomerThemePersonality.pinkie ? 2 : 1,
                          ),
                          color: currentVibe == CustomerThemePersonality.pinkie
                              ? AppColors.softPink.withValues(alpha: 0.5)
                              : Colors.transparent,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CuteShoppingMascot(
                              size: 18,
                              animated: false,
                              showSparkles: false,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                'Pinkie Cute (Girls)',
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: currentVibe == CustomerThemePersonality.pinkie
                                      ? AppColors.deepBlush
                                      : AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
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
                  onPressed: () => context.go('/location-setup'),
                  child: Text(
                    'Continue in Offline / Demo Mode',
                    style: AppTypography.label.copyWith(color: AppColors.ink),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
