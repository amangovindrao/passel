import 'dart:math';

import 'package:customer_app/src/providers/checkout_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Checkout: address, multi-shop bundling, wallet deduction, bill breakdown, payment method, place order.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _notesController = TextEditingController();
  bool _placing = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final paymentMethod = ref.watch(paymentMethodProvider);
    final useWallet = ref.watch(useWalletProvider);
    final quoteAsync = ref.watch(quoteProvider);
    final activeAddress = ref.watch(activeAddressProvider);
    final walletAsync = ref.watch(walletDataProvider);

    final walletBalancePaise = walletAsync.valueOrNull?.balancePaise ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Multi-shop banner if applicable
          if (cart.isMultiShop) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hub_outlined,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Multi-Shop Bundle (${cart.itemsByShop.length} shops within 100m)',
                          style: AppTypography.bodyStrong.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                        Text(
                          'Single consolidated delivery by one rider.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Address card
          ScaleOnCard(
            onTap: () => _changeAddress(context),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.gold, size: 20),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeAddress?.label ?? 'Select address',
                        style: AppTypography.label,
                      ),
                      if (activeAddress != null)
                        Text(
                          activeAddress.addressText,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Text(
                  'Change',
                  style: AppTypography.label.copyWith(color: AppColors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Shared Paasel Wallet card
          if (walletBalancePaise > 0) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    color: AppColors.gold,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Paasel Wallet', style: AppTypography.bodyStrong),
                        Text(
                          'Available: \u20b9${(walletBalancePaise / 100).toStringAsFixed(2)}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: useWallet,
                    activeColor: AppColors.gold,
                    onChanged: (val) {
                      ref.read(useWalletProvider.notifier).state = val;
                      if (val &&
                          paymentMethod != 'online' &&
                          paymentMethod != 'cod') {
                        ref.read(paymentMethodProvider.notifier).state =
                            'online';
                      }
                    },
                  ),
                ],
              ),
            ),
            if (useWallet) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    CuteSparkle(size: 14, color: AppColors.success),
                    SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Paasel Wallet applied! You saved on this order \u{1F389}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
          ],

          // Bill breakdown
          quoteAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (quote) {
              final grossTotal =
                  cart.subtotalPaise + (quote?.deliveryFeePaise ?? 0);
              final walletDeduction = useWallet
                  ? min(walletBalancePaise, grossTotal)
                  : 0;
              final netPayable = grossTotal - walletDeduction;

              return _BillBreakdown(
                itemTotal: cart.subtotalPaise,
                deliveryFee: quote?.deliveryFeePaise ?? 0,
                distanceKm: quote?.distanceKm ?? 0,
                walletDeduction: walletDeduction,
                netPayable: netPayable,
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // Notes
          AppTextField(
            label: 'Delivery notes (optional)',
            controller: _notesController,
            hintText: 'Leave at door, floor number...',
          ),
          const SizedBox(height: AppSpacing.xl),

          // Payment method
          ..._buildPaymentMethodsSection(
            quoteAsync.valueOrNull,
            cart.subtotalPaise,
            walletBalancePaise,
            useWallet,
            paymentMethod,
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: quoteAsync.when(
          loading: () => const PrimaryButton(
            label: 'Loading...',
            onPressed: null,
            expand: true,
          ),
          error: (_, __) => const PrimaryButton(
            label: 'Retry',
            onPressed: null,
            expand: true,
          ),
          data: (quote) {
            final grossTotal =
                cart.subtotalPaise + (quote?.deliveryFeePaise ?? 0);
            final walletDeduction = useWallet
                ? min(walletBalancePaise, grossTotal)
                : 0;
            final netPayable = grossTotal - walletDeduction;

            String label;
            if (netPayable == 0) {
              label =
                  'Pay with Wallet (\u20b9${(grossTotal / 100).toStringAsFixed(0)})';
            } else if (paymentMethod == 'cod') {
              label = walletDeduction > 0
                  ? 'Place Order (COD \u20b9${(netPayable / 100).toStringAsFixed(0)})'
                  : 'Place Order';
            } else {
              label = 'Pay \u20b9${(netPayable / 100).toStringAsFixed(0)}';
            }

            return PrimaryButton(
              label: label,
              loading: _placing,
              onPressed: _placing ? null : () => _placeOrder(netPayable),
              expand: true,
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildPaymentMethodsSection(
    QuoteResult? quote,
    int subtotalPaise,
    int walletBalancePaise,
    bool useWallet,
    String paymentMethod,
  ) {
    final grossTotal = subtotalPaise + (quote?.deliveryFeePaise ?? 0);
    final walletDeduction = useWallet ? min(walletBalancePaise, grossTotal) : 0;
    final netPayable = grossTotal - walletDeduction;

    if (netPayable == 0 && useWallet) {
      return [
        Text('Payment method', style: AppTypography.label),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.success),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Fully covered by Paasel Wallet. No external payment needed!',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      Text('Payment method for remaining amount', style: AppTypography.label),
      const SizedBox(height: AppSpacing.md),
      _PaymentMethodCard(
        title: 'Pay Online',
        subtitle: 'UPI, cards, wallets via Razorpay',
        icon: Icons.credit_card_outlined,
        selected: paymentMethod == 'online',
        onTap: () => ref.read(paymentMethodProvider.notifier).state = 'online',
      ),
      const SizedBox(height: AppSpacing.sm),
      _PaymentMethodCard(
        title: 'Cash on Delivery',
        subtitle: 'Pay when you receive',
        icon: Icons.money_outlined,
        selected: paymentMethod == 'cod',
        onTap: () => ref.read(paymentMethodProvider.notifier).state = 'cod',
      ),
    ];
  }

  Future<void> _placeOrder(int totalPaise) async {
    if (_placing) return;
    setState(() => _placing = true);
    try {
      final notes = _notesController.text.isEmpty
          ? null
          : _notesController.text;
      final result = await ref.read(orderPlacementProvider(notes).future);
      if (mounted && result != null) {
        context.go('/order-confirmation/${result.orderId}');
      }
    } on Exception {
      if (mounted) {
        AppSnackbar.show(
          context,
          message: 'Failed to place order. Try again.',
          variant: AppSnackbarVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _changeAddress(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final addresses = ref.watch(addressListProvider);
          return addresses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (list) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Deliver to', style: AppTypography.title),
                const SizedBox(height: AppSpacing.lg),
                ...list.map(
                  (a) => ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(a.label),
                    subtitle: Text(
                      a.addressText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      ref.read(activeAddressProvider.notifier).state = a;
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextActionButton(
                  label: '+ Add new address',
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go('/location-setup');
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BillBreakdown extends StatelessWidget {
  const _BillBreakdown({
    required this.itemTotal,
    required this.deliveryFee,
    required this.distanceKm,
    this.walletDeduction = 0,
    required this.netPayable,
  });

  final int itemTotal;
  final int deliveryFee;
  final double distanceKm;
  final int walletDeduction;
  final int netPayable;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      child: Column(
        children: [
          _BillRow(label: 'Item total', amount: itemTotal),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Delivery fee', style: AppTypography.body),
                  const SizedBox(width: AppSpacing.xs),
                  const Tooltip(
                    message:
                        'Single delivery fee applies even for multi-shop orders within 100m!',
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppColors.ash,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PriceText(amount: deliveryFee / 100),
                  Text(
                    '\u20b920 \u00d7 $distanceKm km',
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ],
              ),
            ],
          ),
          if (walletDeduction > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Paasel Wallet Applied',
                      style: AppTypography.body.copyWith(color: AppColors.gold),
                    ),
                  ],
                ),
                Text(
                  '- \u20b9${(walletDeduction / 100).toStringAsFixed(2)}',
                  style: AppTypography.bodyStrong.copyWith(
                    color: AppColors.gold,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.xl),
          _BillRow(
            label: walletDeduction > 0 ? 'To Pay' : 'Total',
            amount: netPayable,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });
  final String label;
  final int amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? AppTypography.bodyStrong : AppTypography.body;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        PriceText(amount: amount / 100, large: bold),
      ],
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.08)
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? AppColors.gold
                : AppColors.ash.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.gold : AppColors.ash),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyMedium),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AppColors.gold, size: 20),
          ],
        ),
      ),
    );
  }
}
