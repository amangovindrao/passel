import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Pending KYC approval screen.
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    // Poll every 10 seconds for status change
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (!mounted) return;
      ref.invalidate(shopDataProvider);
      final data = await ref.read(shopDataProvider.future);
      if (!mounted) return;
      if (data.isApproved) {
        context.go('/dashboard');
        return;
      }
      if (data.isRejected) {
        context.go('/kyc');
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GoldPulseIndicator(size: 16),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Under review',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'We are verifying your documents. '
                'This usually takes a few hours.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
