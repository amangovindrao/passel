import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Order confirmation — celebratory moment after successful placement.
class OrderConfirmationScreen extends ConsumerWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isPinkie) ...[
                const CuteShoppingMascot(
                  size: 110,
                  mood: MascotMood.celebrating,
                  showSparkles: true,
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const TwinkleSparkle(size: 16, color: AppColors.deepBlush),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Hooray! Order placed! 🎉',
                      style: AppTypography.headline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const TwinkleSparkle(size: 16, color: AppColors.deepBlush),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Your delicious neighborhood goodies are getting packed right now! ✨',
                  style: AppTypography.body.copyWith(color: AppColors.ash),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const GoldPulseIndicator(size: 24),
                const SizedBox(height: AppSpacing.xl),
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.gold,
                  size: 64,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('Order placed!', style: AppTypography.headline),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Your order is being prepared.',
                  style: AppTypography.body.copyWith(color: AppColors.ash),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: AppSpacing.xxxl),
              PrimaryButton(
                label: 'Track Order',
                onPressed: () => context.go('/tracking/$orderId'),
                expand: true,
              ),
              const SizedBox(height: AppSpacing.md),
              TextActionButton(
                label: 'Back to Home',
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

