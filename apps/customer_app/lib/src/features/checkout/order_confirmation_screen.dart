import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Order confirmation — celebratory moment after successful placement.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
