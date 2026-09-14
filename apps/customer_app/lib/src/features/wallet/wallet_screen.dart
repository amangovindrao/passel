import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Full-screen Paasel Wallet with Hero 3D Glass balance card,
/// "Earn with Paasel" delivery partner loop, cashback tracker, and ledger.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletDataProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CuteCoinBadge(size: 24),
            const SizedBox(width: AppSpacing.sm),
            Text('Paasel Wallet', style: AppTypography.title),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(walletDataProvider),
        child: walletAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Failed to load wallet: $e',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: () => ref.invalidate(walletDataProvider),
                  ),
                ],
              ),
            ),
          ),
          data: (wallet) {
            final transactions = wallet.transactions;
            final filteredTx = _filterTransactions(transactions);

            return ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              children: [
                // Hero 3D Glass Wallet Card
                _buildHeroCard(wallet, isPinkie),
                const SizedBox(height: AppSpacing.lg),

                // Earn with Paasel (Delivery Partner Loop) Card
                _buildRiderLoopCard(context, isPinkie),
                const SizedBox(height: AppSpacing.lg),

                // Cashback & Rewards Banner
                _buildCashbackBanner(context, isPinkie),
                const SizedBox(height: AppSpacing.xl),

                // Ledger Header & Filter Chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transaction Ledger',
                      style: AppTypography.title,
                    ),
                    Text(
                      '${filteredTx.length} records',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.ash,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _buildFilterRow(),
                const SizedBox(height: AppSpacing.md),

                // Transaction Items
                if (filteredTx.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxl,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isPinkie)
                            const CuteShoppingMascot(
                              size: 64,
                              mood: MascotMood.sleepy,
                              showSparkles: true,
                            )
                          else
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: AppColors.ash,
                            ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _selectedFilter == 'All'
                                ? (isPinkie
                                    ? 'No transactions yet! Ready for your first order ✨'
                                    : 'No transactions yet')
                                : 'No $_selectedFilter transactions found',
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.ash,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...filteredTx.map(_buildTransactionTile),
                const SizedBox(height: AppSpacing.xxl),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroCard(WalletData wallet, bool isPinkie) {
    return AppGlassCard(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(AppSpacing.xl),
      backgroundColor: isPinkie
          ? AppColors.lavender.withValues(alpha: 0.25)
          : AppColors.cloud.withValues(alpha: 0.35),
      borderColor: isPinkie
          ? AppColors.deepLavender.withValues(alpha: 0.35)
          : AppColors.gold.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (isPinkie ? AppColors.deepLavender : AppColors.gold)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: (isPinkie ? AppColors.deepLavender : AppColors.gold)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPinkie)
                          const TwinkleSparkle(
                            size: 12,
                            color: AppColors.deepLavender,
                          )
                        else
                          const Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: AppColors.gold,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          'Unified Paasel Balance',
                          style: AppTypography.caption.copyWith(
                            color: isPinkie ? AppColors.deepLavender : AppColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mint.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ready to spend',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '\u20b9${wallet.balanceRupees.toStringAsFixed(2)}',
            style: AppTypography.price.copyWith(
              fontSize: 36,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Earned as rider or loaded as customer \u2014 spendable seamlessly at any shop.',
            style: AppTypography.caption.copyWith(
              color: AppColors.ash,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Available vs Pending breakdown
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cloud.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('Available', style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        '\u20b9${wallet.balanceRupees.toStringAsFixed(0)}',
                        style: AppTypography.bodyStrong.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: AppColors.ash.withValues(alpha: 0.2)),
                Expanded(
                  child: Column(
                    children: [
                      Text('Pending', style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        '\u20b90',
                        style: AppTypography.bodyStrong.copyWith(color: AppColors.warning),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildFeaturePill(Icons.bolt, 'Earn'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 12, color: AppColors.ash),
              ),
              _buildFeaturePill(Icons.savings_outlined, 'Save'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 12, color: AppColors.ash),
              ),
              _buildFeaturePill(Icons.shopping_bag_outlined, 'Shop'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(IconData icon, String text) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderLoopCard(BuildContext context, bool isPinkie) {
    return Container(
      decoration: BoxDecoration(
        gradient: isPinkie
            ? LinearGradient(
                colors: [
                  AppColors.peach.withValues(alpha: 0.6),
                  AppColors.blush.withValues(alpha: 0.5),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [
                  AppColors.cloud.withValues(alpha: 0.5),
                  AppColors.paper,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isPinkie
              ? AppColors.warmPeach.withValues(alpha: 0.4)
              : AppColors.gold.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          if (isPinkie)
            const CuteDeliveryScooter(size: 52)
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cloud,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.electric_moped_outlined,
                size: 26,
                color: AppColors.gold,
              ),
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Earn with Paasel',
                      style: AppTypography.bodyStrong.copyWith(
                        color: AppColors.ink,
                      ),
                    ),
                    if (isPinkie) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const TwinkleSparkle(size: 12, color: AppColors.warmPeach),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Deliver for nearby shops whenever free. Earnings deposit instantly here!',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.ash,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isPinkie ? AppColors.warmPeach : AppColors.gold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            onPressed: () => _showRiderPartnerDialog(context, isPinkie),
            child: const Text(
              'Partner',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showRiderPartnerDialog(BuildContext context, bool isPinkie) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: [
            if (isPinkie)
              const CuteDeliveryScooter(size: 36)
            else
              const Icon(Icons.electric_moped_outlined, size: 28, color: AppColors.gold),
            const SizedBox(width: AppSpacing.sm),
            Text('Unified Partner Hub', style: AppTypography.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your phone number is linked as a verified Delivery Partner and Customer under a single Paasel Identity.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 20, color: AppColors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Rider earnings reflect directly into your Paasel Wallet balance with zero withdrawal delay.',
                      style: AppTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildCashbackBanner(BuildContext context, bool isPinkie) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () {
        if (isPinkie) {
          WalletCelebrationDialog.show(
            context,
            title: 'Cashback Celebration! ✨',
            subtitle:
                'You earn instant cash rewards deposited right into your Paasel Wallet whenever you order from multiple neighborhood shops!',
            amountText: '\u20b950 Active Benefit',
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isPinkie
              ? AppColors.softPink.withValues(alpha: 0.5)
              : AppColors.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isPinkie
                ? AppColors.deepBlush.withValues(alpha: 0.3)
                : AppColors.gold.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            if (isPinkie)
              const PlayfulRewardBadge(size: 28)
            else
              const CuteCoinBadge(size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Pay with Paasel Wallet to unlock up to 5% instant cashback on multi-shop orders.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isPinkie) ...[
              const SizedBox(width: 4),
              const TwinkleSparkle(size: 14, color: AppColors.deepBlush),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = ['All', 'Earnings', 'Payments', 'Refunds'];
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);
    final accentColor = AppColors.primaryFor(isPinkie: isPinkie);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(f),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = f);
              },
              selectedColor: accentColor.withValues(alpha: 0.2),
              side: BorderSide(
                color: isSelected
                    ? accentColor
                    : AppColors.ash.withValues(alpha: 0.2),
              ),
              labelStyle: AppTypography.caption.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? accentColor : AppColors.ink,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<WalletTransactionItem> _filterTransactions(List<WalletTransactionItem> list) {
    if (_selectedFilter == 'All') return list;
    if (_selectedFilter == 'Earnings') {
      return list.where((t) => t.type == 'rider_earning').toList();
    }
    if (_selectedFilter == 'Payments') {
      return list.where((t) => t.type == 'order_wallet_payment').toList();
    }
    if (_selectedFilter == 'Refunds') {
      return list.where((t) => t.type == 'order_refund').toList();
    }
    return list;
  }

  Widget _buildTransactionTile(WalletTransactionItem tx) {
    final isCredit = tx.isCredit;
    final prefix = isCredit ? '+' : '-';
    final color = isCredit ? AppColors.success : AppColors.danger;
    final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.ash.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(_txTitle(tx.type), style: AppTypography.bodyMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tx.description != null && tx.description!.isNotEmpty)
              Text(
                tx.description!,
                style: AppTypography.caption.copyWith(color: AppColors.ash),
              ),
            Text(
              tx.createdAt != null
                  ? tx.createdAt!.split('T').first
                  : '—',
              style: AppTypography.caption.copyWith(
                fontSize: 10,
                color: AppColors.ash.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$prefix\u20b9${tx.amountRupees.toStringAsFixed(2)}',
              style: AppTypography.bodyStrong.copyWith(color: color),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.ash.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                tx.status.toUpperCase(),
                style: AppTypography.caption.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.ash,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _txTitle(String type) {
    switch (type.toLowerCase()) {
      case 'rider_earning':
        return 'Delivery Earning';
      case 'order_wallet_payment':
        return 'Grocery Payment';
      case 'order_refund':
        return 'Order Refund';
      case 'admin_adjustment':
        return 'Wallet Adjustment';
      case 'transaction_reversal':
        return 'Transaction Reversal';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }
}
