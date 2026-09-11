import 'package:delivery_app/src/features/home/widgets/go_online_toggle.dart';
import 'package:delivery_app/src/features/home/widgets/location_permission_card.dart';
import 'package:delivery_app/src/features/home/widgets/on_delivery_card.dart';
import 'package:delivery_app/src/features/home/widgets/position_card.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// The rider's home base: availability, today's count, and the live position
/// readout that proves location is actually being read.
class RiderHomeScreen extends ConsumerStatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  ConsumerState<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends ConsumerState<RiderHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationAccessProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // The grant can change in Settings while we are backgrounded, and a stale
    // "always" would let the rider go online with nothing actually tracking.
    if (lifecycleState == AppLifecycleState.resumed) {
      ref.read(locationAccessProvider.notifier).refresh();
      ref.invalidate(riderDataProvider);
      // An offer may have been made while we were backgrounded, and on a build
      // without push that notification never arrived. Ask now rather than let
      // the rider wait out the poll interval on a screen they just opened.
      ref.read(offerPollerProvider).poll().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = ref.watch(riderDataProvider);
    final online = ref.watch(onlineStatusProvider);
    final access = ref.watch(locationAccessProvider);
    final assignment = ref.watch(activeAssignmentProvider);

    ref
      // Surface a server refusal (the 409 raised while a delivery is running)
      // without ever letting the toggle drift from what the server believes.
      ..listen<OnlineState>(onlineStatusProvider, (previous, next) {
        final reason = next.blockedReason;
        if (reason == null || reason == previous?.blockedReason) return;
        AppSnackbar.show(
          context,
          message: reason,
          variant: AppSnackbarVariant.error,
        );
        ref.read(onlineStatusProvider.notifier).clearBlockedReason();
      })
      // Tier 1 additions are consent-free, so they get a passing mention
      // rather than anything that interrupts what the rider is doing.
      ..listen<String?>(batchAddedNoticeProvider, (_, next) {
        if (next == null) return;
        AppSnackbar.show(context, message: next);
        ref.read(batchAddedNoticeProvider.notifier).state = null;
      });

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        title: Text(
          rider.valueOrNull?.name ?? 'Paasel Rider',
          style: AppTypography.title.copyWith(color: AppColors.paper),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            if (assignment != null)
              OnDeliveryCard(
                assignment: assignment,
                onTap: () => context.push('/active-delivery'),
              )
            else ...[
              LocationPermissionCard(
                access: access,
                onRequest: () =>
                    ref.read(locationAccessProvider.notifier).request(),
                onOpenSettings: () =>
                    ref.read(locationAccessProvider.notifier).openSettings(),
              ),
              if (!access.canGoOnline) const SizedBox(height: AppSpacing.xl),
              Center(
                child: GoOnlineToggle(
                  isOnline: online.isOnline,
                  busy: online.busy,
                  onPressed: _toggleTarget(access, rider.valueOrNull),
                ),
              ),
              if (!access.canGoOnline) ...[
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    'Allow background location to go online',
                    key: const ValueKey('toggle-disabled-reason'),
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ),
              ],
            ],

            const SizedBox(height: AppSpacing.xxl),
            _TodaySnapshot(count: rider.valueOrNull?.completedToday ?? 0),
            const SizedBox(height: AppSpacing.lg),
            PositionCard(
              isOnline: online.isOnline,
              position: ref.watch(locationReporterProvider).lastPosition,
            ),
          ],
        ),
      ),
    );
  }

  /// Returns null — a disabled toggle — unless everything needed is in place.
  ///
  /// The route guard already keeps unapproved partners off this screen; the KYC
  /// re-check here is a cheap second opinion, not a substitute for it.
  VoidCallback? _toggleTarget(LocationAccess access, RiderData? rider) {
    if (rider != null && !rider.isApproved) return null;
    if (!access.canGoOnline) return null;

    final notifier = ref.read(onlineStatusProvider.notifier);
    return ref.read(onlineStatusProvider).isOnline
        ? notifier.goOffline
        : notifier.goOnline;
  }
}

class _TodaySnapshot extends StatelessWidget {
  const _TodaySnapshot({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.xs),
              Text(
                count == 1 ? '1 delivery done' : '$count deliveries done',
                style: AppTypography.bodyStrong,
              ),
            ],
          ),
          Text(
            '$count',
            style: AppTypography.price.copyWith(color: AppColors.gold),
          ),
        ],
      ),
    );
  }
}
