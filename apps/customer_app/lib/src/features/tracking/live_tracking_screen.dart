import 'dart:async';
import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Live tracking screen: ETA, Add More, 7-minute delivery verification, and OTP.
class LiveTrackingScreen extends ConsumerWidget {
  const LiveTrackingScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(trackingProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
      body: trackingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tracking) => _TrackingBody(orderId: orderId, tracking: tracking),
      ),
    );
  }
}

class _TrackingBody extends ConsumerStatefulWidget {
  const _TrackingBody({required this.orderId, required this.tracking});
  final String orderId;
  final TrackingData tracking;

  @override
  ConsumerState<_TrackingBody> createState() => _TrackingBodyState();
}

class _TrackingBodyState extends ConsumerState<_TrackingBody> {
  Timer? _timer;
  late int _remainingSeconds;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.tracking.remainingSeconds;
    if (_remainingSeconds > 0) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        // Auto-complete if expired
        ref.read(orderRepositoryProvider).verifyItems(
          orderId: widget.orderId,
          action: 'everything_correct',
        );
        ref.invalidate(trackingProvider(widget.orderId));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _TrackingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracking.remainingSeconds != widget.tracking.remainingSeconds) {
      _remainingSeconds = widget.tracking.remainingSeconds;
      if (_remainingSeconds > 0) {
        _startCountdown();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);
    final isHandoverPending = tracking.verificationStatus == 'PENDING_CHECK' || tracking.status == 'HANDOVER_READY';
    final isDelivered = tracking.status == 'DELIVERED' || tracking.status == 'COMPLETED' || tracking.verificationStatus == 'ALL_CORRECT';

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(trackingProvider(widget.orderId)),
      child: ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // 1. ETA & Arrival Hero Banner
        _buildEtaHero(context, tracking, isPinkie),
        const SizedBox(height: AppSpacing.md),

        // 2. Delivery Verification Interstitial (7-Minute Window)
        if (isHandoverPending && !isDelivered) ...[
          _buildVerificationCard(context, isPinkie),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 2b. Order Verified / Completed Banner
        if (isDelivered) ...[
          _buildDeliveredSuccessCard(context, isPinkie),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 3. "Add More to This Order" Action Card
        if (tracking.canAddMore) ...[
          _buildAddMoreCard(context, isPinkie),
          const SizedBox(height: AppSpacing.lg),
        ],

        // 4. Delivery OTP (when on the way or arriving)
        if (tracking.deliveryOtp != null && !isDelivered) ...[
          ScaleOnCard(
            child: Column(
              children: [
                Text('Delivery OTP', style: AppTypography.label),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tracking.deliveryOtp!,
                  style: AppTypography.otp.copyWith(
                    color: isPinkie ? AppColors.deepBlush : AppColors.gold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Share this with your delivery partner when they arrive',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // 5. Status timeline in human language
        Text('Order progress', style: AppTypography.title),
        const SizedBox(height: AppSpacing.lg),
        ...tracking.statusHistory.asMap().entries.map((entry) {
          final isLast = entry.key == tracking.statusHistory.length - 1;
          final isCurrent = entry.value.status == tracking.status;
          return OrderTimelineTile(
            icon: _iconForStatus(entry.value.status),
            label: _labelForStatus(entry.value.status),
            timestamp: _formatTime(entry.value.createdAt),
            state: isCurrent
                ? TimelineStepState.active
                : TimelineStepState.complete,
            isLast: isLast,
          );
        }),
      ],
      ),
    );
  }

  Widget _buildEtaHero(BuildContext context, TrackingData tracking, bool isPinkie) {
    String headline = 'Arriving Soon';
    String subtitle = '10–20 min delivery';

    if (tracking.status == 'PLACED' || tracking.status == 'ACCEPTED_BY_SHOP') {
      headline = 'Order Confirmed';
      subtitle = 'Shop is packing your items';
    } else if (tracking.status == 'PREPARING') {
      headline = 'Shop is Preparing';
      subtitle = 'Items being packed with care';
    } else if (tracking.status == 'PICKED_UP' || tracking.status == 'OUT_FOR_DELIVERY') {
      headline = 'On The Way 🛵';
      subtitle = 'Arriving in ~8–12 mins';
    } else if (tracking.status == 'HANDOVER_READY' || tracking.verificationStatus == 'PENDING_CHECK') {
      headline = 'Rider Arrived!';
      subtitle = 'Please inspect your packages';
    } else if (tracking.status == 'DELIVERED' || tracking.status == 'COMPLETED') {
      headline = 'Delivered 🎉';
      subtitle = 'Hope you enjoy your purchase!';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isPinkie ? AppColors.blush : AppColors.cloud,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isPinkie ? AppColors.deepBlush.withValues(alpha: 0.2) : AppColors.glassBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPinkie ? AppColors.deepBlush.withValues(alpha: 0.15) : AppColors.gold.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.electric_moped_rounded,
              color: isPinkie ? AppColors.deepBlush : AppColors.gold,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(BuildContext context, bool isPinkie) {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    final timerStr = '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return AppGlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderColor: isPinkie ? AppColors.deepBlush : AppColors.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, color: AppColors.gold, size: 22),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Check Your Items',
                style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '$timerStr left',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warning),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Please inspect your delivered items. If everything looks good, confirm to complete immediately.',
            style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),

          // ONE PRIMARY ACTION: Everything is correct
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isPinkie ? AppColors.deepBlush : AppColors.ink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: _isVerifying ? null : _confirmEverythingCorrect,
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                _isVerifying ? 'Confirming...' : 'Everything is correct',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // SECONDARY ACTION: Something is wrong
          Center(
            child: TextButton.icon(
              onPressed: () => _showReportIssueModal(context, isPinkie),
              icon: const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.ash),
              label: const Text(
                'Something is wrong',
                style: TextStyle(fontSize: 12, color: AppColors.ash, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredSuccessCard(BuildContext context, bool isPinkie) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.success, size: 28),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivered & Verified 🎉',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.success),
                ),
                Text(
                  'Your delivery is completed. Thank you for choosing Paasel!',
                  style: AppTypography.caption.copyWith(fontSize: 11, color: AppColors.ash),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMoreCard(BuildContext context, bool isPinkie) {
    return AppGlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderColor: AppColors.glassBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.add_shopping_cart_rounded, color: isPinkie ? AppColors.deepBlush : AppColors.gold, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Add More to This Order',
                style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Your order is still being prepared. Add items before your order is packed with zero extra delivery fee.',
            style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: isPinkie ? AppColors.deepBlush : AppColors.ink,
                side: BorderSide(color: isPinkie ? AppColors.deepBlush : AppColors.ink),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: () => _showAddMoreModal(context, isPinkie),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add More Items', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEverythingCorrect() async {
    setState(() => _isVerifying = true);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final res = await repo.verifyItems(orderId: widget.orderId, action: 'everything_correct');
      res.when(
        success: (_) {
          _timer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order verified! Delivered successfully.')),
          );
          ref.invalidate(trackingProvider(widget.orderId));
        },
        failure: (err) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err.message)),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _showReportIssueModal(BuildContext context, bool isPinkie) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (sheetContext) => _ReportIssueSheet(
        orderId: widget.orderId,
        isPinkie: isPinkie,
        onSubmitted: () {
          Navigator.of(sheetContext).pop();
          ref.invalidate(trackingProvider(widget.orderId));
        },
      ),
    );
  }

  void _showAddMoreModal(BuildContext context, bool isPinkie) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (sheetContext) => _AddMoreSheet(
        orderId: widget.orderId,
        isPinkie: isPinkie,
        onAdded: () {
          Navigator.of(sheetContext).pop();
          ref.invalidate(trackingProvider(widget.orderId));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Added to your order 🎉 Arriving together!')),
          );
        },
      ),
    );
  }

  IconData _iconForStatus(String status) => switch (status) {
    'PLACED' => Icons.receipt_long_outlined,
    'ACCEPTED_BY_SHOP' => Icons.check_circle_outline,
    'PREPARING' => Icons.restaurant_outlined,
    'READY_FOR_PICKUP' => Icons.inventory_2_outlined,
    'PARTNER_ASSIGNED' => Icons.delivery_dining_outlined,
    'PARTNER_ARRIVED_AT_SHOP' => Icons.store_outlined,
    'PICKED_UP' => Icons.local_shipping_outlined,
    'OUT_FOR_DELIVERY' => Icons.directions_bike_outlined,
    'DELIVERED' || 'COMPLETED' => Icons.done_all_outlined,
    _ => Icons.circle_outlined,
  };

  String _labelForStatus(String status) => switch (status) {
    'PLACED' => 'Order confirmed',
    'ACCEPTED_BY_SHOP' => 'Shop accepted',
    'PREPARING' => 'Shop preparing',
    'READY_FOR_PICKUP' => 'Packed & ready',
    'PARTNER_ASSIGNED' => 'Rider assigned',
    'PARTNER_ARRIVED_AT_SHOP' => 'Rider picking up',
    'PICKED_UP' => 'Rider picked up',
    'OUT_FOR_DELIVERY' => 'On the way',
    'HANDOVER_READY' => 'Arrived • Check items',
    'DELIVERED' => 'Delivered',
    'COMPLETED' => 'Completed',
    _ => status.replaceAll('_', ' ').toLowerCase(),
  };

  String? _formatTime(String? isoString) {
    if (isoString == null) return null;
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } on FormatException {
      return null;
    }
  }
}

/// Simple issue reporting sheet with expired item safety guarantee.
class _ReportIssueSheet extends ConsumerStatefulWidget {
  const _ReportIssueSheet({
    required this.orderId,
    required this.isPinkie,
    required this.onSubmitted,
  });
  final String orderId;
  final bool isPinkie;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_ReportIssueSheet> createState() => _ReportIssueSheetState();
}

class _ReportIssueSheetState extends ConsumerState<_ReportIssueSheet> {
  String _selectedIssue = 'EXPIRED_ITEM';
  bool _isSubmitting = false;

  final issues = const [
    {'key': 'EXPIRED_ITEM', 'label': 'Expired item', 'icon': Icons.security_rounded},
    {'key': 'MISSING_ITEM', 'label': 'Missing item', 'icon': Icons.remove_circle_outline_rounded},
    {'key': 'WRONG_ITEM', 'label': 'Wrong item', 'icon': Icons.swap_horiz_rounded},
    {'key': 'DAMAGED_ITEM', 'label': 'Damaged item', 'icon': Icons.broken_image_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(orderDetailProvider(widget.orderId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Report an Issue', style: AppTypography.title.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Issue pills
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: issues.map((iss) {
            final isSelected = _selectedIssue == iss['key'];
            return ChoiceChip(
              selected: isSelected,
              avatar: Icon(iss['icon'] as IconData, size: 16),
              label: Text(iss['label'] as String),
              selectedColor: widget.isPinkie ? AppColors.blush : AppColors.gold.withValues(alpha: 0.2),
              onSelected: (_) => setState(() => _selectedIssue = iss['key'] as String),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Expired Item Safety Guarantee Banner
        if (_selectedIssue == 'EXPIRED_ITEM') ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.success),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppColors.success, size: 20),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Product Safety Guarantee: The shop bears all return costs. 100% instant refund.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // Items list
        Text('Select affected item:', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.xs),
        detailAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('Could not load items'),
          data: (detail) {
            if (detail.items.isEmpty) {
              return const Text('No items in order');
            }
            final item = detail.items.first;
            return Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.cloud,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_box, color: AppColors.gold, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Item #${item.id.length > 8 ? item.id.substring(0, 8) : item.id} (${item.qty}x)',
                      style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '₹${(item.pricePaise * item.qty / 100).toStringAsFixed(0)}',
                    style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        // Submit Button (ONE PRIMARY ACTION)
        PrimaryButton(
          label: _isSubmitting ? 'Submitting...' : 'Report Issue',
          expand: true,
          onPressed: _isSubmitting ? null : () => _submitIssue(detailAsync.value),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Future<void> _submitIssue(OrderDetail? detail) async {
    if (detail == null || detail.items.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final item = detail.items.first;
      final res = await repo.reportIssue(
        orderId: widget.orderId,
        issueType: _selectedIssue,
        orderItemId: item.id,
        customerNotes: 'Reported via 7-minute verification flow',
      );
      res.when(
        success: (data) {
          widget.onSubmitted();
        },
        failure: (err) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
        },
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

/// Simple Add More Sheet allowing instant incremental item additions.
class _AddMoreSheet extends ConsumerStatefulWidget {
  const _AddMoreSheet({
    required this.orderId,
    required this.isPinkie,
    required this.onAdded,
  });
  final String orderId;
  final bool isPinkie;
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddMoreSheet> createState() => _AddMoreSheetState();
}

class _AddMoreSheetState extends ConsumerState<_AddMoreSheet> {
  bool _isPaying = false;
  int _extraQty = 1;
  static const int _unitPricePaise = 4500; // ₹45 item example

  @override
  Widget build(BuildContext context) {
    final extraTotal = (_unitPricePaise * _extraQty) / 100;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Add More Items', style: AppTypography.title.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Adding to your arriving delivery • No extra delivery fee',
          style: AppTypography.caption.copyWith(color: AppColors.ash, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),

        // Item addition card
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cloud,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, color: AppColors.gold, size: 24),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Amul Taaza Milk 500ml', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('Dairy & Fresh', style: TextStyle(color: AppColors.ash, fontSize: 11)),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: _extraQty > 1 ? () => setState(() => _extraQty--) : null,
                  ),
                  Text('$_extraQty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: () => setState(() => _extraQty++),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Total addition amount summary
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Additional amount to pay:'),
            Text(
              '₹${extraTotal.toStringAsFixed(0)}',
              style: AppTypography.title.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ONE PRIMARY ACTION: Pay additional amount
        PrimaryButton(
          label: _isPaying ? 'Processing...' : 'Pay ₹${extraTotal.toStringAsFixed(0)} & Add to Delivery',
          expand: true,
          onPressed: _isPaying ? null : _payAndAdd,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Future<void> _payAndAdd() async {
    setState(() => _isPaying = true);
    try {
      final repo = ref.read(orderRepositoryProvider);
      final res = await repo.createAddition(
        orderId: widget.orderId,
        items: [
          {
            'product_id': '00000000-0000-0000-0000-000000000001',
            'qty': _extraQty,
          },
        ],
      );
      // Even if mock product ID triggers 422, let's gracefully notify or complete
      res.when(
        success: (_) => widget.onAdded(),
        failure: (err) {
          // If server rejects with invalid product (mock env), show message
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
        },
      );
    } finally {
      if (mounted) setState(() => _isPaying = false);
    }
  }
}

