import 'dart:async';

import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

/// "Under review" — waits for the KYC decision.
///
/// Subscribes to Realtime on the partner's own profile row so an approval lands
/// immediately, with a slow poll as a backstop in case the socket drops.
class UnderReviewScreen extends ConsumerStatefulWidget {
  const UnderReviewScreen({super.key});

  @override
  ConsumerState<UnderReviewScreen> createState() => _UnderReviewScreenState();
}

class _UnderReviewScreenState extends ConsumerState<UnderReviewScreen> {
  RealtimeChannel? _channel;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    final channel = _channel;
    if (channel != null) {
      try {
        ref.read(supabaseProvider).removeChannel(channel);
      } on Object {
        // Nothing useful to do while tearing down.
      }
    }
    super.dispose();
  }

  void _subscribe() {
    // Realtime is the fast path, not the only one — the 15s poll below is the
    // backstop. So if a channel cannot be opened at all, degrade to polling
    // rather than leaving the rider staring at a screen that failed to build.
    try {
      _openChannel();
    } on Object {
      _channel = null;
    }
  }

  void _openChannel() {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    _channel = client
        .channel('rider-kyc-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_partner_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _check(),
        )
        .subscribe();
  }

  Future<void> _check() async {
    ref.invalidate(riderDataProvider);
    final RiderData rider;
    try {
      rider = await ref.read(riderDataProvider.future);
    } on Exception {
      return; // Transient failure; the next tick will retry.
    }
    if (!mounted) return;

    if (rider.isApproved) {
      context.go('/home');
    } else if (rider.isRejected) {
      context.go('/kyc');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = ref.watch(riderDataProvider).valueOrNull;
    final rejected = rider?.isRejected ?? false;
    final reason = rider?.kycRejectionReason?.trim();

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rejected)
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.danger,
                  size: 48,
                )
              else
                const GoldPulseIndicator(size: 16),
              const SizedBox(height: AppSpacing.xl),
              Text(
                rejected ? 'We could not verify you' : 'Under review',
                style: AppTypography.headline.copyWith(color: AppColors.paper),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                rejected
                    ? 'You can fix this and submit again.'
                    : 'We are verifying your documents. '
                          'This usually takes a few hours.',
                style: AppTypography.body.copyWith(color: AppColors.ash),
                textAlign: TextAlign.center,
              ),
              if (rejected) ...[
                const SizedBox(height: AppSpacing.xl),
                // The reviewer's actual words. Without this the rider is told
                // "no" and left to guess which document was the problem.
                ScaleOnCard(
                  key: const ValueKey('kyc-rejection-reason'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.danger,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          reason == null || reason.isEmpty
                              ? 'Something in your documents did not check out.'
                              : reason,
                          style: AppTypography.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                PrimaryButton(
                  label: 'Update documents',
                  onPressed: () => context.go('/kyc'),
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
