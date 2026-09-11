import 'package:customer_app/src/providers/checkout_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Checkout: address, bill breakdown, payment method, place order.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _notesController = TextEditingController();
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final paymentMethod = ref.watch(paymentMethodProvider);
    final quoteAsync = ref.watch(quoteProvider);
    final activeAddress = ref.watch(activeAddressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
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

          // Bill breakdown
          quoteAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (quote) => _BillBreakdown(
              itemTotal: cart.subtotalPaise,
              deliveryFee: quote?.deliveryFeePaise ?? 0,
              distanceKm: quote?.distanceKm ?? 0,
            ),
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
          Text('Payment method', style: AppTypography.label),
          const SizedBox(height: AppSpacing.md),
          _PaymentMethodCard(
            title: 'Pay Online',
            subtitle: 'UPI, cards, wallets',
            icon: Icons.credit_card_outlined,
            selected: paymentMethod == 'online',
            onTap: () =>
                ref.read(paymentMethodProvider.notifier).state = 'online',
          ),
          const SizedBox(height: AppSpacing.sm),
          _PaymentMethodCard(
            title: 'Cash on Delivery',
            subtitle: 'Pay when you receive',
            icon: Icons.money_outlined,
            selected: paymentMethod == 'cod',
            onTap: () => ref.read(paymentMethodProvider.notifier).state = 'cod',
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
            final total = cart.subtotalPaise + (quote?.deliveryFeePaise ?? 0);
            final label = paymentMethod == 'cod'
                ? 'Place Order'
                : 'Pay \u20b9${(total / 100).toStringAsFixed(0)}';
            return PrimaryButton(
              label: label,
              loading: _placing,
              onPressed: _placing ? null : () => _placeOrder(total),
              expand: true,
            );
          },
        ),
      ),
    );
  }

  Future<void> _placeOrder(int totalPaise) async {
    if (_placing) return; // Double-tap guard
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
      builder: (_) => const Text('Address selector'),
    );
  }
}

class _BillBreakdown extends StatelessWidget {
  const _BillBreakdown({
    required this.itemTotal,
    required this.deliveryFee,
    required this.distanceKm,
  });
  final int itemTotal;
  final int deliveryFee;
  final double distanceKm;

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
                        'May be reduced if your order '
                        'ships with a nearby one',
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
          const Divider(height: AppSpacing.xl),
          _BillRow(label: 'Total', amount: itemTotal + deliveryFee, bold: true),
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
