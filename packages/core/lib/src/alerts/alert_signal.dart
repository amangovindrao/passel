import 'dart:async';

import 'package:flutter/services.dart';

/// Plays the sound and vibration that accompany an in-app alert.
///
/// Only foreground alerts need this. When the app was backgrounded the OS
/// notification channel already made the noise.
abstract class AlertSignal {
  Future<void> play();

  /// Stops a repeating signal early — called when the user acts on the alert.
  Future<void> stop();
}

/// Platform sound plus haptics, repeated a few times.
///
/// A rider's phone is usually in a pocket or bar-mounted with the screen off,
/// so one short beep is easy to miss. Repeating gives the alert a fighting
/// chance without needing an audio package and a bundled asset.
///
/// Worth knowing about the ceiling here: on Android the genuinely loud,
/// ringtone-style alert comes from the *notification channel's* sound, set
/// natively, not from anything the Dart isolate can play. This covers the
/// foreground case properly; making the backgrounded case louder is a
/// channel-configuration job, not a code-in-this-file job.
class PlatformAlertSignal implements AlertSignal {
  PlatformAlertSignal({
    this.repeatCount = 3,
    this.gap = const Duration(milliseconds: 700),
  });

  final int repeatCount;
  final Duration gap;

  Timer? _timer;
  var _remaining = 0;

  @override
  Future<void> play() async {
    await stop();
    _remaining = repeatCount;
    await _pulse();
    if (repeatCount <= 1) return;

    _timer = Timer.periodic(gap, (timer) async {
      if (_remaining <= 0) {
        timer.cancel();
        return;
      }
      await _pulse();
    });
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _remaining = 0;
  }

  Future<void> _pulse() async {
    _remaining--;
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.heavyImpact();
  }
}

/// No-op signal. Used in tests and anywhere silence is the correct behaviour.
class SilentAlertSignal implements AlertSignal {
  const SilentAlertSignal();

  @override
  Future<void> play() async {}

  @override
  Future<void> stop() async {}
}
