import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:shop_app/src/services/packing_photo_uploader.dart';
import 'package:ui_kit/ui_kit.dart';

/// One order, and everything the shop does to it.
///
/// The whole flow lives on one screen because it is one continuous physical
/// task: read the list, accept it, pack the bag, photograph the bag, hand it
/// over. Splitting that across routes would mean navigating with one hand full
/// of groceries.
class ShopOrderDetailScreen extends ConsumerStatefulWidget {
  const ShopOrderDetailScreen({
    required this.shopId,
    required this.orderId,
    super.key,
  });

  final String shopId;
  final String orderId;

  @override
  ConsumerState<ShopOrderDetailScreen> createState() =>
      _ShopOrderDetailScreenState();
}

class _ShopOrderDetailScreenState extends ConsumerState<ShopOrderDetailScreen> {
  /// Which action is in flight, so exactly one spinner shows and the rest of
  /// the buttons go inert.
  String? _busy;

  ShopOrderRef get _ref => (shopId: widget.shopId, orderId: widget.orderId);

  bool get _isBusy => _busy != null;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(shopOrderDetailProvider(_ref));

    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        title: detailAsync.maybeWhen(
          data: (detail) => Text('Order #${detail.summary.shortRef}'),
          orElse: () => const Text('Order'),
        ),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              e is AppError ? e.message : 'Could not load this order.',
              style: AppTypography.body.copyWith(color: AppColors.ash),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(ShopOrderDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _StatusCard(detail: detail),
        const SizedBox(height: AppSpacing.lg),

        Text('Items', style: AppTypography.label),
        const SizedBox(height: AppSpacing.md),
        for (final line in detail.lines)
          _LineRow(
            line: line,
            // Only while the shop is still packing. Once it is out the door,
            // an item cannot be un-packed.
            onMarkUnavailable: detail.isPreparing && !line.isUnavailable
                ? () => _askUnavailableReason(line)
                : null,
          ),

        const SizedBox(height: AppSpacing.lg),
        _Totals(detail: detail),

        if (detail.pickupCode != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _PickupCodeCard(code: detail.pickupCode!),
        ],

        const SizedBox(height: AppSpacing.xl),
        ..._actions(detail),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  List<Widget> _actions(ShopOrderDetail detail) {
    if (detail.status == 'PLACED') {
      return [
        if (detail.summary.awaitingPayment)
          const _Notice(
            icon: Icons.hourglass_empty,
            message:
                'This order is paid online and the payment has not arrived '
                'yet. You can accept it once it has.',
          )
        else
          PrimaryButton(
            key: const ValueKey('accept-order'),
            label: 'Accept order',
            loading: _busy == 'accept',
            onPressed: _isBusy || !detail.canAccept ? null : _accept,
            expand: true,
          ),
        const SizedBox(height: AppSpacing.md),
        TextActionButton(
          key: const ValueKey('reject-order'),
          label: 'Reject',
          onPressed: _isBusy ? null : _confirmReject,
        ),
      ];
    }

    if (detail.isPreparing) {
      return [
        _PackingPhotoTile(
          hasPhoto: detail.hasPackingPhoto,
          busy: _busy == 'photo',
          onPick: _isBusy ? null : _attachPhoto,
        ),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          key: const ValueKey('mark-ready'),
          label: 'Ready for pickup',
          loading: _busy == 'ready',
          // The server refuses this without a photo, so the button must not
          // pretend otherwise. A disabled control with a reason beside it beats
          // one that fails when tapped.
          onPressed: _isBusy || !detail.canMarkReady ? null : _markReady,
          expand: true,
        ),
        if (!detail.hasPackingPhoto) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Add a photo of the packed bag to hand this over.',
            style: AppTypography.caption.copyWith(color: AppColors.ash),
            textAlign: TextAlign.center,
          ),
        ],
      ];
    }

    return [
      _Notice(
        icon: Icons.check_circle_outline,
        message: switch (detail.status) {
          'READY_FOR_PICKUP' =>
            'Packed and waiting. We are finding a rider for this order.',
          'PARTNER_ASSIGNED' =>
            'A rider is on the way. Keep the bag ready at the counter.',
          'PARTNER_ARRIVED_AT_SHOP' =>
            'The rider is here. Check their pickup code above before handing '
                'the bag over.',
          'AWAITING_CUSTOMER_DECISION' =>
            'The customer is deciding what to do about the missing item.',
          'ON_HOLD' => 'On hold at the customer\u2019s request.',
          _ => 'Nothing more to do on this order.',
        },
      ),
    ];
  }

  // --- Actions ---

  Future<void> _accept() => _run('accept', () async {
    final result = await ref
        .read(apiClientProvider)
        .post<Map<String, dynamic>>(
          '/api/v1/orders/${widget.orderId}/accept',
          fromJson: (d) => d as Map<String, dynamic>,
        );
    return result.when(
      success: (Map<String, dynamic> _) => 'Order accepted. Start packing.',
      failure: (AppError e) => throw e,
    );
  });

  Future<void> _confirmReject() async {
    final confirmed = await AppBottomSheet.show<bool>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reject this order?', style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The customer is told straight away and refunded if they have '
            'already paid. This cannot be undone.',
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            key: const ValueKey('confirm-reject'),
            label: 'Reject order',
            onPressed: () => Navigator.of(sheetContext).pop(true),
            expand: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextActionButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _run('reject', () async {
      final result = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/api/v1/orders/${widget.orderId}/reject',
            fromJson: (d) => d as Map<String, dynamic>,
          );
      return result.when(
        success: (Map<String, dynamic> _) => 'Order rejected.',
        failure: (AppError e) => throw e,
      );
    });
  }

  Future<void> _askUnavailableReason(ShopOrderLine line) async {
    final controller = TextEditingController();
    final reason = await AppBottomSheet.show<String>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${line.name} unavailable', style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The customer is asked whether to continue without it. Tell them '
            'why so they can decide.',
            style: AppTypography.body.copyWith(color: AppColors.ash),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Reason',
            controller: controller,
            hintText: 'Out of stock',
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            key: const ValueKey('confirm-unavailable'),
            label: 'Mark unavailable',
            onPressed: () => Navigator.of(sheetContext).pop(
              controller.text.trim().isEmpty
                  ? 'Out of stock'
                  : controller.text.trim(),
            ),
            expand: true,
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;

    await _run('item-${line.id}', () async {
      final result = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/api/v1/orders/${widget.orderId}/items/${line.id}'
            '/mark-unavailable',
            data: {'reason': reason},
            fromJson: (d) => d as Map<String, dynamic>,
          );
      return result.when(
        success: (Map<String, dynamic> _) =>
            'Customer asked about ${line.name}.',
        failure: (AppError e) => throw e,
      );
    });
  }

  Future<void> _attachPhoto() async {
    setState(() => _busy = 'photo');
    try {
      final url = await ref
          .read(packingPhotoUploaderProvider)
          .pickAndUpload(orderId: widget.orderId);
      // Backed out of the camera. Not a failure, and not worth a message.
      if (url == null) return;

      final result = await ref
          .read(apiClientProvider)
          .post<Map<String, dynamic>>(
            '/api/v1/orders/${widget.orderId}/packing-photo',
            data: {'photo_url': url},
            fromJson: (d) => d as Map<String, dynamic>,
          );
      if (!mounted) return;
      result.when(
        success: (Map<String, dynamic> _) {
          ref.invalidate(shopOrderDetailProvider(_ref));
          AppSnackbar.show(
            context,
            message: 'Photo added.',
            variant: AppSnackbarVariant.success,
          );
        },
        failure: (AppError e) => AppSnackbar.show(
          context,
          message: e.message,
          variant: AppSnackbarVariant.error,
        ),
      );
    } on PackingPhotoFailure catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        message: e.message,
        variant: AppSnackbarVariant.error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _markReady() => _run('ready', () async {
    final result = await ref
        .read(apiClientProvider)
        .post<Map<String, dynamic>>(
          '/api/v1/orders/${widget.orderId}/mark-ready',
          fromJson: (d) => d as Map<String, dynamic>,
        );
    return result.when(
      success: (Map<String, dynamic> data) => data['assignment_id'] == null
          ? 'Marked ready. Looking for a rider.'
          : 'Marked ready. A rider is on the way.',
      failure: (AppError e) => throw e,
    );
  });

  /// Runs one action: single in-flight spinner, refresh on success, and the
  /// server's own message on failure rather than a generic one.
  Future<void> _run(String tag, Future<String> Function() action) async {
    setState(() => _busy = tag);
    try {
      final message = await action();
      if (!mounted) return;
      ref
        ..invalidate(shopOrderDetailProvider(_ref))
        ..invalidate(shopOrdersProvider(widget.shopId));
      AppSnackbar.show(
        context,
        message: message,
        variant: AppSnackbarVariant.success,
      );
    } on AppError catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        message: e.message,
        variant: AppSnackbarVariant.error,
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}

// --- Pieces ---

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detail});

  final ShopOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.summary.isCod ? 'Cash on delivery' : 'Paid online',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  detail.summary.itemCount == 1
                      ? '1 item'
                      : '${detail.summary.itemCount} items',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
              ],
            ),
          ),
          StatusBadge(
            status: shopStatusBadge(detail.status),
            label: shopStatusLabel(detail.status),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, this.onMarkUnavailable});

  final ShopOrderLine line;
  final VoidCallback? onMarkUnavailable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ScaleOnCard(
        key: ValueKey('order-line-${line.id}'),
        child: Row(
          children: [
            Text(
              '${line.qty}\u00d7',
              style: AppTypography.data.copyWith(
                color: line.isUnavailable ? AppColors.ash : AppColors.gold,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    style: AppTypography.bodyMedium.copyWith(
                      color: line.isUnavailable
                          ? AppColors.ash
                          : AppColors.paper,
                      decoration: line.isUnavailable
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (line.isUnavailable) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      line.unavailableReason ?? 'Unavailable',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PriceText(amount: line.lineTotalPaise / 100, zeroLabel: '\u20b90'),
            if (onMarkUnavailable != null)
              IconButton(
                key: ValueKey('mark-unavailable-${line.id}'),
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.ash,
                tooltip: 'Mark unavailable',
                onPressed: onMarkUnavailable,
              ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.detail});

  final ShopOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final dropped =
        detail.availableItemTotalPaise != detail.summary.itemTotalPaise;

    return ScaleOnCard(
      child: Column(
        children: [
          _TotalRow(label: 'Items', amountPaise: detail.summary.itemTotalPaise),
          if (dropped) ...[
            const SizedBox(height: AppSpacing.sm),
            _TotalRow(
              label: 'After unavailable items',
              amountPaise: detail.availableItemTotalPaise,
              highlight: true,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _TotalRow(
            label: 'Delivery',
            amountPaise: detail.summary.deliveryFeePaise,
          ),
          const Divider(color: AppColors.ash, height: AppSpacing.xl),
          _TotalRow(
            label: 'Total',
            amountPaise: detail.summary.totalPaise,
            emphasise: true,
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amountPaise,
    this.emphasise = false,
    this.highlight = false,
  });

  final String label;
  final int amountPaise;
  final bool emphasise;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: emphasise
              ? AppTypography.bodyMedium
              : AppTypography.caption.copyWith(
                  color: highlight ? AppColors.warning : AppColors.ash,
                ),
        ),
        const Spacer(),
        PriceText(amount: amountPaise / 100, zeroLabel: '\u20b90'),
      ],
    );
  }
}

class _PickupCodeCard extends StatelessWidget {
  const _PickupCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      child: Row(
        children: [
          const Icon(Icons.pin_outlined, color: AppColors.gold),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rider pickup code', style: AppTypography.label),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Only hand the bag over if it matches',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
              ],
            ),
          ),
          Text(
            code,
            key: const ValueKey('pickup-code'),
            style: AppTypography.data.copyWith(
              color: AppColors.gold,
              fontSize: 22,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PackingPhotoTile extends StatelessWidget {
  const _PackingPhotoTile({
    required this.hasPhoto,
    required this.busy,
    this.onPick,
  });

  final bool hasPhoto;
  final bool busy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      key: const ValueKey('packing-photo-tile'),
      onTap: busy ? null : onPick,
      child: Row(
        children: [
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              hasPhoto ? Icons.check_circle : Icons.photo_camera_outlined,
              color: hasPhoto ? AppColors.success : AppColors.gold,
            ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPhoto ? 'Packing photo added' : 'Photo of the packed bag',
                  style: AppTypography.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  hasPhoto ? 'Tap to replace' : 'Required before handing over',
                  style: AppTypography.caption.copyWith(color: AppColors.ash),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.ash),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ScaleOnCard(
      child: Row(
        children: [
          Icon(icon, color: AppColors.gold),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: AppTypography.body.copyWith(color: AppColors.ash),
            ),
          ),
        ],
      ),
    );
  }
}
