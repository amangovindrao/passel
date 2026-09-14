import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Screen for Paasel Group Order featuring Private Cart Privacy Mode.
class GroupOrderScreen extends ConsumerWidget {
  const GroupOrderScreen({super.key, this.sessionId});

  final String? sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupState = ref.watch(groupOrderStateProvider);
    final session = groupState.session;
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (session == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.ink : AppColors.paper,
        appBar: AppBar(title: const Text('Group Order')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isPrivate = session.privateCartMode;
    final isLocked = session.isLocked;

    return Scaffold(
      backgroundColor: isDark ? AppColors.ink : AppColors.paper,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.societyName,
              style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              session.progress.statusText,
              style: AppTypography.caption.copyWith(
                fontSize: 11,
                color: isPinkie ? AppColors.deepBlush : AppColors.gold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: isLocked ? AppColors.gold : AppColors.ash,
              size: 20,
            ),
            tooltip: isLocked ? 'Session Locked' : 'Session Open',
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        children: [
          // 1. Private Cart Privacy Mode Toggle Card
          _buildPrivacyToggleCard(context, ref, isPrivate, isLocked, isPinkie),
          const SizedBox(height: AppSpacing.md),

          // 2. Aggregate Progress & Savings Bar
          _buildAggregateProgressBar(context, session, isPinkie),
          const SizedBox(height: AppSpacing.md),

          // 2b. Group Payment Gate Status Banner
          _buildPaymentGateBanner(context, session, isPinkie),
          const SizedBox(height: AppSpacing.lg),

          // 3. User's Personal Cart ("My Cart" - always visible to user)
          _buildMyCartSection(context, ref, session, isPinkie),
          const SizedBox(height: AppSpacing.md),

          // 3b. Captain: Pay for Everyone Card
          _buildCaptainPayCard(context, ref, session, isPinkie),
          const SizedBox(height: AppSpacing.lg),

          // 4. Group Members & Activity Section
          _buildGroupActivitySection(context, session, isPrivate, isPinkie),
          const SizedBox(height: AppSpacing.lg),

          // 5. Group Delivery Packages & Handover Section
          _buildPackagesSection(context, session, isPinkie),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _buildPrivacyToggleCard(
    BuildContext context,
    WidgetRef ref,
    bool isPrivate,
    bool isLocked,
    bool isPinkie,
  ) {
    final borderColor = isPrivate
        ? (isPinkie ? AppColors.deepBlush : AppColors.gold)
        : AppColors.glassBorder;

    return AppGlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPrivate
                      ? (isPinkie ? AppColors.blush : AppColors.gold.withValues(alpha: 0.15))
                      : AppColors.cloud,
                ),
                child: Icon(
                  isPrivate ? Icons.lock_rounded : Icons.lock_outline_rounded,
                  color: isPrivate
                      ? (isPinkie ? AppColors.deepBlush : AppColors.gold)
                      : AppColors.ash,
                  size: 22,
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
                          isPrivate ? '🔒 Private' : '🔒 Private Cart',
                          style: AppTypography.title.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isPrivate
                                ? (isPinkie ? AppColors.deepBlush : AppColors.gold)
                                : AppColors.ink,
                          ),
                        ),
                        if (isPrivate) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isPinkie ? AppColors.deepBlush : AppColors.gold,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPrivate
                          ? 'Your items and shop choices are hidden from other members.'
                          : 'Keep your shopping private from the group.',
                      style: AppTypography.caption.copyWith(
                        fontSize: 12,
                        color: AppColors.ash,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isPrivate,
                activeColor: isPinkie ? AppColors.deepBlush : AppColors.gold,
                onChanged: isLocked
                    ? null
                    : (value) => _handleToggle(context, ref, value, isPrivate),
              ),
            ],
          ),
          if (isLocked) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.ash),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Privacy settings are locked once order processing begins.',
                  style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.ash),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _handleToggle(BuildContext context, WidgetRef ref, bool newValue, bool currentlyPrivate) {
    if (newValue) {
      ref.read(groupOrderStateProvider.notifier).togglePrivacy(enable: true);
      _showEnabledSnackbar(context);
    } else {
      _showDisableConfirmationDialog(context, ref);
    }
  }

  void _showEnabledSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.white, size: 18),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Private Cart Enabled 🔒\nOther members can see you joined, but cannot see what you bought or where.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        action: SnackBarAction(
          label: 'Got it',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  void _showDisableConfirmationDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: const Row(
            children: [
              Icon(Icons.lock_open_rounded, color: AppColors.warning),
              SizedBox(width: AppSpacing.sm),
              Text('Disable Private Cart?'),
            ],
          ),
          content: const Text(
            'Private Cart is currently ON.\n\nTurning it OFF will allow participating members to see item-level Group Order information and your chosen shop.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Keep Private'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                ref.read(groupOrderStateProvider.notifier).togglePrivacy(
                      enable: false,
                      confirmDisable: true,
                    );
              },
              child: const Text('Disable Privacy'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAggregateProgressBar(
    BuildContext context,
    GroupOrderSessionModel session,
    bool isPinkie,
  ) {
    final progress = session.progress;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isPinkie ? AppColors.blush.withValues(alpha: 0.6) : AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildProgressStat(
                context,
                icon: Icons.people_alt_rounded,
                count: '${progress.memberCount}',
                label: 'joined',
                color: isPinkie ? AppColors.deepBlush : AppColors.gold,
              ),
              _buildProgressStat(
                context,
                icon: Icons.store_rounded,
                count: '${progress.shopCount}',
                label: 'shops',
                color: isPinkie ? AppColors.warmPeach : AppColors.ink,
              ),
              _buildProgressStat(
                context,
                icon: Icons.check_circle_rounded,
                count: '${progress.paymentsCompletedCount}/${progress.memberCount}',
                label: 'paid',
                color: AppColors.success,
              ),
              _buildProgressStat(
                context,
                icon: Icons.electric_moped_rounded,
                count: 'FREE',
                label: 'delivery',
                color: AppColors.success,
              ),
            ],
          ),
          if (progress.groupTotalPaise != null) ...[
            const Divider(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Combined Group Total',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
                Text(
                  '₹${progress.groupTotalRupees?.toStringAsFixed(0) ?? '0'}',
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressStat(
    BuildContext context, {
    required IconData icon,
    required String count,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          count,
          style: AppTypography.title.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: AppColors.ink,
          ),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(fontSize: 10, color: AppColors.ash),
        ),
      ],
    );
  }

  Widget _buildPaymentGateBanner(
    BuildContext context,
    GroupOrderSessionModel session,
    bool isPinkie,
  ) {
    final isComplete = session.paymentComplete;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isComplete
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isComplete ? AppColors.success : AppColors.warning,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.verified_rounded : Icons.pending_actions_rounded,
            color: isComplete ? AppColors.success : AppColors.warning,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isComplete ? 'Group Payment Gate: Cleared' : 'Waiting for Group Payment',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isComplete ? AppColors.success : AppColors.warning,
                  ),
                ),
                Text(
                  isComplete
                      ? 'All active orders paid. Delivery handover authorized.'
                      : 'Rider cannot complete handover until all member carts are paid.',
                  style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.ash),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyCartSection(
    BuildContext context,
    WidgetRef ref,
    GroupOrderSessionModel session,
    bool isPinkie,
  ) {
    final myCart = session.myCart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'My Items',
              style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '₹${session.mySubtotalRupees.toStringAsFixed(0)}',
              style: AppTypography.title.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isPinkie ? AppColors.deepBlush : AppColors.gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (myCart.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Center(
              child: Text(
                'Your cart is currently empty in this group order.',
                style: AppTypography.caption.copyWith(color: AppColors.ash),
              ),
            ),
          )
        else ...[
          ...myCart.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ash.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '${item.qty}x',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName ?? 'Product',
                          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (item.shopName != null)
                          Text(
                            item.shopName!,
                            style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.ash),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${item.subtotalRupees.toStringAsFixed(0)}',
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPinkie ? AppColors.deepBlush : AppColors.gold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: () {
                ref.read(groupOrderStateProvider.notifier).payMyCart();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment processed for your group items!')),
                );
              },
              icon: const Icon(Icons.payment_rounded, size: 18),
              label: Text('Pay My Share (₹${session.mySubtotalRupees.toStringAsFixed(0)})'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGroupActivitySection(
    BuildContext context,
    GroupOrderSessionModel session,
    bool isPrivate,
    bool isPinkie,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Group Members',
              style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (isPrivate)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.ash.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 10, color: AppColors.ash),
                    SizedBox(width: 3),
                    Text(
                      'Carts Protected',
                      style: TextStyle(fontSize: 9, color: AppColors.ash, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...session.members.map((member) {
          final isCaller = member.isCreator && member.name.contains('You');
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isPinkie ? AppColors.warmPeach : AppColors.gold,
                  child: Text(
                    member.name.isNotEmpty ? member.name.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: AppTypography.body.copyWith(
                          fontSize: 13,
                          fontWeight: isCaller ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      Text(
                        isPrivate && !isCaller
                            ? 'Cart protected 🔒'
                            : (member.items.isNotEmpty
                                ? '${member.items.length} items'
                                : 'Building cart...'),
                        style: AppTypography.caption.copyWith(
                          fontSize: 11,
                          color: isPrivate && !isCaller ? AppColors.ash : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isPrivate || isCaller)
                  if (member.subtotalRupees != null)
                    Text(
                      '₹${member.subtotalRupees!.toStringAsFixed(0)}',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCaptainPayCard(
    BuildContext context,
    WidgetRef ref,
    GroupOrderSessionModel session,
    bool isPinkie,
  ) {
    // Find unpaid members
    final unpaidMembers = session.members.where((m) => m.paymentStatus != 'completed').toList();
    if (unpaidMembers.isEmpty) return const SizedBox.shrink();

    return AppGlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderColor: AppColors.gold.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: AppColors.gold, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Group Captain Option',
                style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${unpaidMembers.length} Unpaid',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.gold),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'You can pay the remaining balance on behalf of all members to immediately authorize group delivery. Individual cart privacy is 100% preserved.',
            style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: () {
                ref.read(groupOrderStateProvider.notifier).captainPayAll();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Remaining group balance paid by Captain! Handover unlocked.')),
                );
              },
              icon: const Icon(Icons.verified_user_rounded, size: 18),
              label: const Text('Pay for Everyone & Unlock Handover'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesSection(
    BuildContext context,
    GroupOrderSessionModel session,
    bool isPinkie,
  ) {
    final packages = session.packages;
    if (packages.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Group Delivery Packages',
          style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...packages.map((pkg) {
          final isDelivered = pkg.deliveryStatus == 'DELIVERED';
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.xs),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                Icon(
                  isDelivered ? Icons.check_circle_rounded : Icons.inventory_2_rounded,
                  color: isDelivered ? AppColors.success : AppColors.ash,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Package #${pkg.id.length >= 8 ? pkg.id.substring(0, 8).toUpperCase() : pkg.id}',
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        'Status: ${pkg.deliveryStatus} • Handover: ${pkg.handoverStatus}',
                        style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.ash),
                      ),
                    ],
                  ),
                ),
                if (pkg.handoverOtp != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.ink.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      'OTP: ${pkg.handoverOtp}',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
