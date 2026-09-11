import 'dart:async';

import 'package:customer_app/src/providers/order_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Full-screen interstitial for missing-item decisions.
class MissingItemInterstitial extends ConsumerStatefulWidget {
  const MissingItemInterstitial({required this.payload, super.key});
  final MissingItemPayload payload;

  @override
  ConsumerState<MissingItemInterstitial> createState() =>
      _MissingItemInterstitialState();
}

class _MissingItemInterstitialState
    extends ConsumerState<MissingItemInterstitial> {
  late int _secondsLeft;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.payload.timeoutSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
        // Auto-proceed handled server-side
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _decide(String decision) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final client = ref.read(apiClientProvider);
    await client.post<Map<String, dynamic>>(
      '/api/v1/orders/${widget.payload.orderId}/customer-decision',
      data: {'decision': decision},
      fromJson: (d) => d as Map<String, dynamic>,
    );

    if (mounted) {
      AppSnackbar.show(
        context,
        message: switch (decision) {
          'proceed' => 'Continuing with available items',
          'hold' => 'Order on hold for now',
          _ => 'Order cancelled',
        },
        variant: AppSnackbarVariant.success,
      );
      _dismiss();
    }
  }

  void _dismiss() {
    ref.read(missingItemInterstitialProvider.notifier).state = null;
    Navigator.of(context).pop();
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 56,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Item unavailable', style: AppTypography.headline),
              const SizedBox(height: AppSpacing.md),
              Text(
                '"${p.itemName}" is not available: ${p.reason}',
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xxl),
              // Price comparison
              ScaleOnCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        Text('Original', style: AppTypography.caption),
                        PriceText(amount: p.originalTotalPaise / 100),
                      ],
                    ),
                    const Icon(Icons.arrow_forward, color: AppColors.ash),
                    Column(
                      children: [
                        Text('Revised', style: AppTypography.caption),
                        PriceText(amount: p.revisedTotalPaise / 100),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Auto-continuing in ${_formatTime(_secondsLeft)}'
                ' if no response',
                style: AppTypography.caption.copyWith(color: AppColors.ash),
              ),
              const SizedBox(height: AppSpacing.xxl),
              // Actions
              PrimaryButton(
                label: 'Proceed without it',
                onPressed: _submitting ? null : () => _decide('proceed'),
                loading: _submitting,
                expand: true,
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Hold my order',
                onPressed: _submitting ? null : () => _decide('hold'),
                expand: true,
              ),
              const SizedBox(height: AppSpacing.md),
              TextActionButton(
                label: 'Cancel order',
                onPressed: _submitting ? null : () => _decide('cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
