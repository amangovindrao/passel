import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// Subscription plans: Starter/Growth/Pro with authorize CTA.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        title: const Text('Subscription'),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your plan',
              style: AppTypography.headline.copyWith(color: AppColors.paper),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _PlanCard(
              name: 'Starter',
              price: 149,
              features: ['Basic visibility', 'Standard support'],
              highlighted: false,
            ),
            const SizedBox(height: AppSpacing.md),
            const _PlanCard(
              name: 'Growth',
              price: 249,
              features: [
                'Better visibility',
                'Priority support',
                'Analytics',
              ],
              highlighted: true,
            ),
            const SizedBox(height: AppSpacing.md),
            const _PlanCard(
              name: 'Pro',
              price: 349,
              features: [
                'Top visibility',
                'Dedicated support',
                'Full analytics',
                'Priority matching',
              ],
              highlighted: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.features,
    required this.highlighted,
  });
  final String name;
  final int price;
  final List<String> features;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: highlighted
            ? Border.all(color: AppColors.gold, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: AppTypography.title),
              PriceText(amount: price),
            ],
          ),
          Text(
            '/month',
            style: AppTypography.caption.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.md),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.check, color: AppColors.gold, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Text(f, style: AppTypography.caption),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: highlighted ? 'Choose Growth' : 'Select',
            onPressed: () {}, // Opens Razorpay mandate URL
            expand: true,
          ),
        ],
      ),
    );
  }
}
