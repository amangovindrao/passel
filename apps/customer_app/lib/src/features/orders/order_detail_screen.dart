import 'package:core/core.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// Past order detail: items, photos, ratings, disputes.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({required this.orderId, super.key});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (detail) => _DetailBody(detail: detail, ref: ref),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.ref});
  final OrderDetail detail;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Pricing
        ScaleOnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bill', style: AppTypography.title),
              const SizedBox(height: AppSpacing.md),
              _Row('Item total', detail.itemTotalPaise),
              _Row('Delivery fee', detail.deliveryFeePaise),
              if (detail.batchingRefundPaise != null)
                _Row(
                  'Batching discount (delivered together)',
                  -detail.batchingRefundPaise!,
                ),
              const Divider(height: AppSpacing.xl),
              _Row(
                'Total',
                detail.itemTotalPaise +
                    detail.deliveryFeePaise -
                    (detail.batchingRefundPaise ?? 0),
                bold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Verification photos
        if (detail.photos.isNotEmpty) ...[
          Text('Verification photos', style: AppTypography.title),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: detail.photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, i) {
                final photo = detail.photos[i];
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        width: 90,
                        height: 90,
                        color: AppColors.cloud,
                        child: const Icon(Icons.photo, color: AppColors.ash),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(photo.stage, style: AppTypography.caption),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],

        // Timeline (completed)
        Text('Order timeline', style: AppTypography.title),
        const SizedBox(height: AppSpacing.md),
        ...detail.statusHistory.asMap().entries.map((entry) {
          final isLast = entry.key == detail.statusHistory.length - 1;
          return OrderTimelineTile(
            icon: Icons.check_circle_outlined,
            label: entry.value.status.replaceAll('_', ' ').toLowerCase(),
            timestamp: _formatTime(entry.value.createdAt),
            state: TimelineStepState.complete,
            isLast: isLast,
          );
        }),
        const SizedBox(height: AppSpacing.xl),

        // Dispute button (within 48h)
        SecondaryButton(
          label: 'Raise a dispute',
          onPressed: () => _showDisputeDialog(context),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  void _showDisputeDialog(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Raise a dispute', style: AppTypography.title),
          const SizedBox(height: AppSpacing.lg),
          const AppTextField(label: 'Reason', hintText: 'What went wrong?'),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Submit',
            onPressed: () => Navigator.of(context).pop(),
            expand: true,
          ),
        ],
      ),
    );
  }

  String? _formatTime(String? iso) {
    if (iso == null) return null;
    try {
      final dt = DateTime.parse(iso);
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } on FormatException {
      return null;
    }
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.paise, {this.bold = false});
  final String label;
  final int paise;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? AppTypography.bodyStrong : AppTypography.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          PriceText(amount: paise / 100, large: bold),
        ],
      ),
    );
  }
}
