import 'dart:async';

import 'package:core/core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Firebase-backed [AlertTransport] for the rider app.
///
/// Wires all three ways a push can reach the app:
///
/// * `onMessage` — app is open. No OS notification is shown, so [AlertCenter]
///   is the only thing that will make a sound.
/// * `onMessageOpenedApp` — app was backgrounded, user tapped the
///   notification. The OS already made noise.
/// * `getInitialMessage` — app was fully terminated and launched by the tap.
///   Easy to forget, and forgetting it means a rider who taps an offer
///   notification from a killed app lands on a blank dashboard.
class FcmAlertTransport implements AlertTransport {
  FcmAlertTransport({FirebaseMessaging? messaging})
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final _controller = StreamController<AlertMessage>.broadcast();
  final _subs = <StreamSubscription<RemoteMessage>>[];
  var _started = false;

  @override
  Stream<AlertMessage> get messages => _controller.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    await _messaging.requestPermission();

    _subs
      ..add(
        FirebaseMessaging.onMessage.listen(
          (m) => _forward(m, AlertDelivery.foreground),
        ),
      )
      ..add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          (m) => _forward(m, AlertDelivery.background),
        ),
      );

    final launchMessage = await _messaging.getInitialMessage();
    if (launchMessage != null) {
      _forward(launchMessage, AlertDelivery.background);
    }
  }

  /// The device token to register with the backend so it can target this rider.
  Future<String?> deviceToken() => _messaging.getToken();

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _controller.close();
  }

  void _forward(RemoteMessage message, AlertDelivery delivery) {
    final alert = AlertMessage.tryParse(message.data, delivery: delivery);
    if (alert != null) _controller.add(alert);
  }
}
