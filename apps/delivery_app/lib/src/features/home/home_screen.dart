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
          rider.valueOrNull?.name ?? 'Passel Rider',
          style: AppTypography.title.copyWith(color: AppColors.paper),
        ),
        actions: [
          IconButton(
            key: const ValueKey('rider-wallet-button'),
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.gold,
            ),
            tooltip: 'Paasel Wallet',
            onPressed: () {
              AppBottomSheet.show<void>(
                context: context,
                builder: (_) => const _RiderLedgerSheet(),
              );
            },
          ),
        ],
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
            const _DedicatedShopDeliveryCard(),
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

class _DedicatedShopDeliveryCard extends ConsumerStatefulWidget {
  const _DedicatedShopDeliveryCard();

  @override
  ConsumerState<_DedicatedShopDeliveryCard> createState() =>
      _DedicatedShopDeliveryCardState();
}

class _DedicatedShopDeliveryCardState
    extends ConsumerState<_DedicatedShopDeliveryCard> {
  final _controller = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dedicatedCode = ref.watch(dedicatedShopCodeProvider);

    return ScaleOnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront,
                    color: AppColors.gold, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dedicated Shop Delivery',
                      style: AppTypography.bodyStrong
                          .copyWith(color: AppColors.paper),
                    ),
                    Text(
                      dedicatedCode == null
                          ? 'Deliver orders for any nearby shop'
                          : 'Locked to deliver ONLY for $dedicatedCode',
                      style: AppTypography.caption.copyWith(
                        color: dedicatedCode == null
                            ? AppColors.ash
                            : AppColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
              if (dedicatedCode != null)
                IconButton(
                  icon:
                      const Icon(Icons.close, color: AppColors.ash, size: 20),
                  tooltip: 'Deliver for all shops',
                  onPressed: () {
                    ref.read(dedicatedShopCodeProvider.notifier).state = null;
                    AppSnackbar.show(
                      context,
                      message:
                          'Cleared: You are now accepting orders from all shops',
                    );
                  },
                ),
            ],
          ),
          if (dedicatedCode == null && !_isEditing) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Set Dedicated Shop ID (PSL-XXXX)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.gold,
                side: const BorderSide(color: AppColors.gold),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else if (_isEditing) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    style: AppTypography.body.copyWith(color: AppColors.paper),
                    decoration: InputDecoration(
                      hintText: 'e.g. PSL-1001',
                      hintStyle:
                          AppTypography.body.copyWith(color: AppColors.ash),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.graphite,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.graphite),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: () {
                    final code = _controller.text.trim().toUpperCase();
                    if (code.isEmpty) return;
                    ref.read(dedicatedShopCodeProvider.notifier).state = code;
                    setState(() => _isEditing = false);
                    _controller.clear();
                    AppSnackbar.show(
                      context,
                      message: 'Locked to deliver only for $code',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.ink,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Lock'),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon:
                      const Icon(Icons.cancel, color: AppColors.ash, size: 20),
                  onPressed: () => setState(() => _isEditing = false),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RiderWalletCard extends ConsumerWidget {
  const _RiderWalletCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletDataProvider);
    final balanceRupees = walletAsync.valueOrNull?.balanceRupees ?? 0.0;

    return ScaleOnCard(
      onTap: () {
        AppBottomSheet.show<void>(
          context: context,
          builder: (_) => const _RiderLedgerSheet(),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Paasel Wallet', style: AppTypography.bodyStrong),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Unified',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.gold,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Tap to view immutable ledger',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ash,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '\u20b9${balanceRupees.toStringAsFixed(2)}',
                style: AppTypography.title.copyWith(color: AppColors.gold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Delivery earnings settle immediately here. Can be withdrawn or used to order food/groceries as a customer.',
            style: AppTypography.caption.copyWith(color: AppColors.ash),
          ),
        ],
      ),
    );
  }
}

class _RiderLedgerSheet extends ConsumerWidget {
  const _RiderLedgerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletDataProvider);

    return walletAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Failed to load wallet: $e'),
      ),
      data: (wallet) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      color: AppColors.gold,
                      size: 24,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Paasel Wallet Ledger', style: AppTypography.title),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Balance: \u20b9${wallet.balanceRupees.toStringAsFixed(2)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unified account ledger (delivery partner + customer roles). All transactions are immutable.',
              style: AppTypography.caption.copyWith(color: AppColors.ash),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Transactions', style: AppTypography.bodyStrong),
            const SizedBox(height: AppSpacing.sm),
            if (wallet.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No wallet transactions yet.',
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: wallet.transactions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final tx = wallet.transactions[index];
                    final isCredit = tx.isCredit;
                    final prefix = isCredit ? '+' : '-';
                    final color = isCredit ? AppColors.success : AppColors.danger;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(
                          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 16,
                          color: color,
                        ),
                      ),
                      title: Text(
                        _txTitle(tx.type),
                        style: AppTypography.bodyMedium,
                      ),
                      subtitle: Text(
                        tx.description ?? tx.id,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ash,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$prefix\u20b9${tx.amountRupees.toStringAsFixed(2)}',
                            style: AppTypography.bodyStrong.copyWith(color: color),
                          ),
                          Text(
                            tx.status,
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.ash,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  String _txTitle(String type) {
    switch (type.toLowerCase()) {
      case 'rider_earning':
        return 'Delivery Earning';
      case 'order_wallet_payment':
        return 'Order Payment';
      case 'order_refund':
        return 'Order Refund';
      case 'admin_adjustment':
        return 'Admin Adjustment';
      case 'transaction_reversal':
        return 'Reversal';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }
}

