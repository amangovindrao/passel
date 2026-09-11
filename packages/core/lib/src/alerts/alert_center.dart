import 'dart:async';

import 'package:core/src/alerts/alert_message.dart';
import 'package:core/src/alerts/alert_signal.dart';
import 'package:core/src/alerts/alert_transport.dart';

/// The dual-channel alert mechanism, in one place.
///
/// Both channels are needed because they fail in opposite ways:
///
/// * A foregrounded app gets the data message and can throw up a full-screen
///   interstitial immediately — but the OS shows no notification, so nothing
///   makes a sound unless the app does it. Hence the signal below.
/// * A backgrounded or killed app cannot be woken by anything the app itself
///   subscribes to. Only a high-priority notification reaches it, and tapping
///   that notification is what routes the user in.
///
/// Same payload, same [AlertMessage] type, same downstream handling. Only the
/// noise differs, which is exactly what [AlertDelivery] records.
class AlertCenter {
  AlertCenter({required AlertTransport transport, AlertSignal? signal})
    : _transport = transport,
      _signal = signal ?? const SilentAlertSignal();

  final AlertTransport _transport;
  final AlertSignal _signal;

  final _out = StreamController<AlertMessage>.broadcast();
  StreamSubscription<AlertMessage>? _sub;

  /// Alerts, after the signal has been played where appropriate.
  Stream<AlertMessage> get alerts => _out.stream;

  Future<void> start() async {
    if (_sub != null) return;
    _sub = _transport.messages.listen(_handle);
    await _transport.start();
  }

  /// Silences a repeating signal. Call this the moment the user acts on the
  /// alert — accepting, declining, or dismissing — so the phone stops buzzing
  /// at someone who is already dealing with it.
  Future<void> acknowledge() => _signal.stop();

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _signal.stop();
    await _transport.dispose();
    await _out.close();
  }

  void _handle(AlertMessage message) {
    if (message.delivery == AlertDelivery.foreground) {
      // Fire and forget: a failed haptic must never swallow the alert itself.
      _signal.play().ignore();
    }
    _out.add(message);
  }
}
