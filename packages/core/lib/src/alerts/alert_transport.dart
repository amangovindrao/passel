import 'dart:async';

import 'package:core/src/alerts/alert_message.dart';

/// Source of push alerts.
///
/// Deliberately abstract and free of any Firebase import: `core` stays
/// Firebase-free, each app supplies its own concrete transport, and tests get
/// to drive the whole alert path without a platform channel in sight.
abstract class AlertTransport {
  /// Alerts as they arrive, foreground and background alike.
  Stream<AlertMessage> get messages;

  /// Requests permission, registers the device, and starts listening.
  /// Safe to call more than once.
  Future<void> start();

  Future<void> dispose();
}

/// Transport backed by a plain stream, for tests and previews.
class InMemoryAlertTransport implements AlertTransport {
  final _controller = StreamController<AlertMessage>.broadcast();
  var _started = false;

  bool get isStarted => _started;

  @override
  Stream<AlertMessage> get messages => _controller.stream;

  @override
  Future<void> start() async => _started = true;

  /// Pushes an alert as if it had arrived from the network.
  void emit(AlertMessage message) => _controller.add(message);

  @override
  Future<void> dispose() async => _controller.close();
}
