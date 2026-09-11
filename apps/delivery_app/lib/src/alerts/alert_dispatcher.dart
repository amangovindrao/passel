import 'dart:async';

import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Alert kinds the rider app understands.
abstract final class RiderAlertKind {
  /// A brand new delivery offer, 35-second window.
  static const offerFresh = 'offer_fresh';

  /// A mid-trip detour offer, 20-second window.
  static const offerBatchDetour = 'offer_batch_detour';

  /// Tier 1: another order at the same shop joined this trip. No consent asked.
  static const batchAdded = 'batch_added';

  /// The order status moved, e.g. after the shop handed over.
  static const orderStatus = 'order_status';
}

/// Routes incoming alerts into state.
///
/// Kept out of the widget tree so the mapping from wire payload to app state is
/// testable on its own, without pumping a single widget.
class AlertDispatcher {
  AlertDispatcher(this._ref);

  final Ref _ref;
  StreamSubscription<AlertMessage>? _sub;

  Future<void> start() async {
    final center = _ref.read(alertCenterProvider);
    _sub ??= center.alerts.listen(handle);
    await center.start();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Applies one alert. Public so tests can drive it directly.
  void handle(AlertMessage alert) {
    switch (alert.kind) {
      case RiderAlertKind.offerFresh:
      case RiderAlertKind.offerBatchDetour:
        _ref.read(currentOfferProvider.notifier).state =
            RiderOffer.fromAlert(alert);

      case RiderAlertKind.batchAdded:
        _applyBatchAdded(alert);

      case RiderAlertKind.orderStatus:
        _applyOrderStatus(alert);
    }
  }

  void _applyBatchAdded(AlertMessage alert) {
    final notifier = _ref.read(activeAssignmentProvider.notifier);
    final current = notifier.state;
    final total = alert.intOf('orders_on_trip');

    if (current != null) {
      notifier.state = current.copyWith(
        ordersOnTrip: total ?? current.ordersOnTrip + 1,
      );
    }

    final position = total ?? (current?.ordersOnTrip ?? 1);
    _ref.read(batchAddedNoticeProvider.notifier).state =
        'Order #$position added to your pickup here';
  }

  void _applyOrderStatus(AlertMessage alert) {
    final status = alert['status'];
    if (status == null) return;

    final notifier = _ref.read(activeAssignmentProvider.notifier);
    final current = notifier.state;
    if (current == null || current.orderId != alert['order_id']) return;

    const finished = {
      'DELIVERED',
      'COMPLETED',
      'CANCELLED_BY_CUSTOMER',
      'CANCELLED_BY_SHOP',
      'CANCELLED_ITEM_UNAVAILABLE',
    };
    notifier.state = finished.contains(status)
        ? null
        : current.copyWith(orderStatus: status);
  }
}

final alertDispatcherProvider = Provider<AlertDispatcher>((ref) {
  final dispatcher = AlertDispatcher(ref);
  ref.onDispose(dispatcher.stop);
  return dispatcher;
});
