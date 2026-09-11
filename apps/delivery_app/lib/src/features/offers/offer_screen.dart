import 'dart:async';

import 'package:core/core.dart';
import 'package:delivery_app/src/features/offers/widgets/countdown_ring.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// The offer surface, for both a fresh delivery and a Tier 2 detour.
///
/// One component, two clearly different faces. A rider glancing at this
/// mid-route needs to know instantly whether they are being handed a new job or
/// asked to bend their current route, so the header, accent and headline number
/// all change — not just a label somewhere in the body.
class OfferScreen extends ConsumerStatefulWidget {
  const OfferScreen({required this.offer, super.key});

  final RiderOffer offer;

  @override
  ConsumerState<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends ConsumerState<OfferScreen> {
  late int _secondsLeft;
  Timer? _timer;
  bool _submitting = false;

  RiderOffer get _offer => widget.offer;

  Color get _accent =>
      _offer.isBatchDetour ? AppColors.warning : AppColors.gold;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _offer.windowSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        setState(() => _secondsLeft = 0);
        _expire();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The window closed. The server has already moved on to the next partner, so
  /// this screen just gets out of the way — the rider is still online.
  void _expire() {
    _timer?.cancel();
    _dismiss();
  }

  void _dismiss() {
    ref.read(alertCenterProvider).acknowledge().ignore();
    ref.read(currentOfferProvider.notifier).state = null;
  }

  Future<void> _accept() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _timer?.cancel();

    final path = _offer.isBatchDetour
        ? '/api/v1/orders/assignments/${_offer.assignmentId}/batch-accept'
        : '/api/v1/orders/assignments/${_offer.assignmentId}/accept';

    final result = await ref
        .read(apiClientProvider)
        .post<Map<String, dynamic>>(
          path,
          fromJson: (d) => d as Map<String, dynamic>,
        );

    if (!mounted) return;
    result.when(
      success: (Map<String, dynamic> _) {
        if (_offer.isBatchDetour) {
          // A detour joins the trip they are already running, so they stay
          // exactly where they are — only the stop count changes.
          final current = ref.read(activeAssignmentProvider);
          if (current != null) {
            ref.read(activeAssignmentProvider.notifier).state = current
                .copyWith(ordersOnTrip: current.ordersOnTrip + 1);
          }
          AppSnackbar.show(
            context,
            message: 'Stop added to your trip',
            variant: AppSnackbarVariant.success,
          );
        } else {
          ref.read(activeAssignmentProvider.notifier).state = ActiveAssignment(
            assignmentId: _offer.assignmentId,
            orderId: _offer.orderId,
            shopName: _offer.shopName,
            orderStatus: 'PARTNER_ASSIGNED',
          );
        }
        _dismiss();
      },
      failure: (AppError e) {
        AppSnackbar.show(
          context,
          message: e.message,
          variant: AppSnackbarVariant.error,
        );
        _dismiss();
      },
    );
  }

  Future<void> _decline() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    _timer?.cancel();

    final path = _offer.isBatchDetour
        ? '/api/v1/orders/assignments/${_offer.assignmentId}/batch-decline'
        : '/api/v1/orders/assignments/${_offer.assignmentId}/decline';

    await ref
        .read(apiClientProvider)
        .post<Map<String, dynamic>>(
          path,
          fromJson: (d) => d as Map<String, dynamic>,
        );

    if (!mounted) return;
    // Nothing more to say: the server hands the order to the next partner and
    // will not offer it here again.
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              // Scrollable body, pinned actions. A rider on a short phone must
              // never have Accept pushed off the bottom of the screen.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.lg),
                      _Header(
                        isBatchDetour: _offer.isBatchDetour,
                        accent: _accent,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      CountdownRing(
                        secondsRemaining: _secondsLeft,
                        totalSeconds: _offer.windowSeconds,
                      ),
                      const SizedBox(height: AppSpacing.xxl),

                      ScaleOnCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _ShopAvatar(
                                  photoUrl: _offer.shopPhotoUrl,
                                  accent: _accent,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    _offer.shopName,
                                    style: AppTypography.title,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // The headline metric differs by kind: a fresh job
                            // is "how far to the shop", a detour is "how much
                            // longer will this make my trip".
                            if (_offer.isBatchDetour)
                              _MetricRow(
                                key: const ValueKey('offer-detour-metric'),
                                icon: Icons.alt_route,
                                label: 'Extra distance',
                                value: _formatDetour(_offer.detourMeters),
                                accent: _accent,
                              )
                            else
                              _MetricRow(
                                key: const ValueKey('offer-distance-metric'),
                                icon: Icons.storefront_outlined,
                                label: 'Distance to shop',
                                value: _formatDistance(
                                  _offer.distanceToShopMeters,
                                ),
                                accent: _accent,
                              ),
                            const SizedBox(height: AppSpacing.md),
                            _MetricRow(
                              icon: Icons.shopping_bag_outlined,
                              label: 'Items',
                              value: '${_offer.itemCount}',
                              accent: _accent,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl),
                      Text('You earn', style: AppTypography.caption),
                      const SizedBox(height: AppSpacing.xs),
                      PriceText(amount: _offer.earningPaise / 100, large: true),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
              PrimaryButton(
                label: _offer.isBatchDetour ? 'Add this stop' : 'Accept',
                onPressed: _submitting ? null : _accept,
                loading: _submitting,
                expand: true,
              ),
              const SizedBox(height: AppSpacing.md),
              TextActionButton(
                label: _offer.isBatchDetour ? 'No thanks' : 'Decline',
                onPressed: _submitting ? null : _decline,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatDistance(int? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _formatDetour(int? meters) {
    if (meters == null) return '—';
    if (meters < 1000) return '+$meters m detour';
    return '+${(meters / 1000).toStringAsFixed(1)} km detour';
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isBatchDetour, required this.accent});

  final bool isBatchDetour;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isBatchDetour ? Icons.alt_route : Icons.local_shipping_outlined,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isBatchDetour ? 'Route change' : 'New job',
                style: AppTypography.caption.copyWith(color: accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          isBatchDetour ? 'Add a stop?' : 'New delivery',
          key: ValueKey(
            isBatchDetour ? 'offer-title-batch' : 'offer-title-fresh',
          ),
          style: AppTypography.headline.copyWith(color: AppColors.paper),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.photoUrl, required this.accent});

  final String? photoUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.md),
        image: photoUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
              ),
      ),
      child: photoUrl == null
          ? Icon(Icons.storefront, color: accent, size: 22)
          : null,
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: AppTypography.body.copyWith(color: AppColors.ash)),
        const Spacer(),
        Text(value, style: AppTypography.data),
      ],
    );
  }
}
