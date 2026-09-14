import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Customer Profile Screen featuring Unified Account identity,
/// Partner Switch, Saved Addresses, Favorite Shops, and Monthly Ration status.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final phone = client.auth.currentUser?.phone ?? 'Paasel User';
    final favShopIds = ref.watch(favoriteShopsProvider);
    final rationAsync = ref.watch(monthlyRationProvider);
    final walletAsync = ref.watch(walletDataProvider);
    final requests = ref.watch(productRequestProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);
    final personality = ref.watch(customerThemePersonalityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile', style: AppTypography.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // User Card
          _buildUserCard(phone, isPinkie),
          const SizedBox(height: AppSpacing.lg),

          // Unified Account / Rider Switch Card
          _buildRiderSwitchCard(context, isPinkie),
          const SizedBox(height: AppSpacing.xl),

          // Menu Sections
          const Text('Quick Access', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),

          // Theme Personality Tile
          _buildMenuTile(
            icon: isPinkie ? Icons.auto_awesome_rounded : Icons.palette_outlined,
            color: isPinkie ? AppColors.deepBlush : AppColors.gold,
            title: 'App Theme Personality',
            subtitle: isPinkie
                ? 'Pinkie Cute (For Girls) \u2014 Mascot & Micro-moments'
                : 'Classic Sleek (Default) \u2014 Apple-level Minimalist',
            trailing: isPinkie
                ? const TwinkleSparkle(size: 16, color: AppColors.deepBlush)
                : const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () => _showPersonalityDialog(context, ref, personality),
          ),

          // Wallet Tile
          _buildMenuTile(
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.gold,
            title: 'Paasel Wallet',
            subtitle: walletAsync.when(
              data: (w) =>
                  '\u20b9${w.balanceRupees.toStringAsFixed(2)} balance available',
              loading: () => 'Loading balance...',
              error: (_, __) => 'View balance & ledger',
            ),
            trailing: const CuteCoinBadge(size: 20),
            onTap: () => context.push('/wallet'),
          ),

          // Favorites Tile
          _buildMenuTile(
            icon: Icons.favorite_rounded,
            color: AppColors.deepBlush,
            title: 'Favorite Neighborhood Shops',
            subtitle: '${favShopIds.length} shops saved',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.deepBlush,
                  content: Text(
                    '${favShopIds.length} shops in your favorites! Filter them on Home.',
                  ),
                ),
              );
            },
          ),

          // Monthly Ration Tile
          _buildMenuTile(
            icon: Icons.inventory_2_rounded,
            color: AppColors.deepLavender,
            title: 'Monthly Ration Kit',
            subtitle: rationAsync.when(
              data: (r) => r.isConfigured
                  ? 'Active: ${r.items.length} recurring essentials'
                  : 'Not configured yet \u2014 tap to set up',
              loading: () => 'Checking schedule...',
              error: (_, __) => 'Configure recurring groceries',
            ),
            onTap: () => _showMonthlyRationDialog(context, ref),
          ),

          // Broadcasted Requests Tile
          _buildMenuTile(
            icon: Icons.chat_bubble_outline_rounded,
            color: AppColors.warmPeach,
            title: 'Product Requests',
            subtitle: '${requests.length} inquiries sent to nearby shops',
            onTap: () => _showRequestsSheet(context, requests),
          ),

          // Saved Addresses
          _buildMenuTile(
            icon: Icons.location_on_outlined,
            color: AppColors.mint,
            title: 'Saved Delivery Addresses',
            subtitle: 'Manage home, work, and neighbor drop-offs',
            onTap: () => context.push('/location-setup'),
          ),

          const SizedBox(height: AppSpacing.xl),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // Sign Out Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              padding: const EdgeInsets.all(AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Sign Out of Paasel'),
            onPressed: () async {
              await ref.read(supabaseClientProvider).auth.signOut();
              if (context.mounted) {
                context.go('/phone');
              }
            },
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildUserCard(String phone, bool isPinkie) {
    return AppGlassCard(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      backgroundColor: isPinkie
          ? AppColors.softPink.withValues(alpha: 0.3)
          : AppColors.cloud.withValues(alpha: 0.4),
      borderColor: isPinkie
          ? AppColors.deepBlush.withValues(alpha: 0.25)
          : AppColors.gold.withValues(alpha: 0.25),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPinkie ? AppColors.blush : AppColors.paper,
              border: Border.all(
                color: isPinkie ? AppColors.deepBlush.withValues(alpha: 0.3) : AppColors.gold.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: isPinkie
                  ? const CuteShoppingMascot(
                      size: 44,
                      animated: false,
                      showSparkles: false,
                    )
                  : const Icon(
                      Icons.person_rounded,
                      size: 32,
                      color: AppColors.gold,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phone, style: AppTypography.bodyStrong),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isPinkie ? AppColors.deepBlush : AppColors.gold)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isPinkie) ...[
                        const TwinkleSparkle(size: 10, color: AppColors.deepBlush),
                        const SizedBox(width: 4),
                      ] else ...[
                        const Icon(Icons.verified, size: 12, color: AppColors.gold),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'Unified Identity Member',
                        style: AppTypography.caption.copyWith(
                          color: isPinkie ? AppColors.deepBlush : AppColors.gold,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderSwitchCard(BuildContext context, bool isPinkie) {
    return Container(
      decoration: BoxDecoration(
        color: isPinkie
            ? AppColors.peach.withValues(alpha: 0.4)
            : AppColors.paper,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isPinkie
              ? AppColors.warmPeach.withValues(alpha: 0.3)
              : AppColors.gold.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          if (isPinkie)
            const CuteDeliveryScooter(size: 40)
          else
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cloud,
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.electric_moped_outlined,
                size: 22,
                color: AppColors.gold,
              ),
            ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Partner Mode', style: AppTypography.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'Switch to the Paasel Rider app with the same phone number.',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Rider Mode'),
                  content: const Text(
                    'You are registered under the Unified Identity. Open the Paasel Delivery Partner app on your device to accept nearby orders. Earnings credit directly to your customer wallet!',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Info', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.ash.withValues(alpha: 0.1)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: AppTypography.bodyMedium),
        subtitle: Text(
          subtitle,
          style: AppTypography.caption.copyWith(color: AppColors.ash),
        ),
        trailing:
            trailing ??
            const Icon(Icons.chevron_right, size: 18, color: AppColors.ash),
      ),
    );
  }

  void _showMonthlyRationDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            CuteBasketIllustration(size: 32),
            SizedBox(width: AppSpacing.sm),
            Text('Monthly Ration Kit', style: AppTypography.title),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Never run out of kitchen essentials. Schedule a curated basket of Atta, Rice, Dal, Milk, and Oil delivered on the 1st of every month with zero delivery fee.',
              style: AppTypography.bodyMedium,
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              '\u2022 Automatically batched from your favorite Kirana store\n\u2022 Full control: Pause, skip, or edit items anytime\n\u2022 Auto-deduct from Paasel Wallet with cashback',
              style: AppTypography.caption,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepBlush,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              ref.read(monthlyRationProvider.notifier).configureDefaults();
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppColors.deepBlush,
                  content: Text(
                    'Monthly Ration Kit activated for 1st of next month! \u2728',
                  ),
                ),
              );
            },
            child: const Text('Activate Kit'),
          ),
        ],
      ),
    );
  }

  void _showRequestsSheet(
    BuildContext context,
    List<ProductRequestItem> requests,
  ) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Broadcasted Requests', style: AppTypography.title),
            const SizedBox(height: AppSpacing.sm),
            if (requests.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No active product requests. Use the Explore tab to ask local shops for hard-to-find items!',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ),
              )
            else
              ...requests.map(
                (r) => ListTile(
                  title: Text(r.productName, style: AppTypography.bodyMedium),
                  subtitle: Text(
                    r.status,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPersonalityDialog(
    BuildContext context,
    WidgetRef ref,
    CustomerThemePersonality current,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('App Theme & Personality', style: AppTypography.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Option 1: Classic Sleek (Default)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                ref
                    .read(customerThemePersonalityProvider.notifier)
                    .setPersonality(CustomerThemePersonality.classic);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Switched to Classic Sleek theme mode.'),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: current == CustomerThemePersonality.classic
                        ? AppColors.gold
                        : AppColors.ash.withValues(alpha: 0.25),
                    width: current == CustomerThemePersonality.classic ? 2 : 1,
                  ),
                  color: current == CustomerThemePersonality.classic
                      ? AppColors.gold.withValues(alpha: 0.08)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.gold, size: 24),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Classic Sleek (Default)', style: AppTypography.bodyStrong),
                          const SizedBox(height: 2),
                          Text(
                            'Minimalist gold & slate styling, standard clean icons. Professional & focused for adults.',
                            style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (current == CustomerThemePersonality.classic)
                      const Icon(Icons.check_circle, color: AppColors.gold, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Option 2: Pinkie Cute (For Girls)
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                ref
                    .read(customerThemePersonalityProvider.notifier)
                    .setPersonality(CustomerThemePersonality.pinkie);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.deepBlush,
                    content: Text('Pinkie Cute mode enabled! Enjoy the cute moments ✨'),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: current == CustomerThemePersonality.pinkie
                        ? AppColors.deepBlush
                        : AppColors.ash.withValues(alpha: 0.25),
                    width: current == CustomerThemePersonality.pinkie ? 2 : 1,
                  ),
                  color: current == CustomerThemePersonality.pinkie
                      ? AppColors.softPink.withValues(alpha: 0.4)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    const CuteShoppingMascot(size: 28, animated: false, showSparkles: false),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Pinkie Cute', style: AppTypography.bodyStrong),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.deepBlush,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: const Text(
                                  'For Girls',
                                  style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Smiling mascot, floating hearts on favorites, cute empty cart & delivery scooter.',
                            style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (current == CustomerThemePersonality.pinkie)
                      const Icon(Icons.check_circle, color: AppColors.deepBlush, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

