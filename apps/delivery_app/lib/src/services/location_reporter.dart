import 'dart:async';

import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Raised when reporting is asked to start without background-capable access.
class LocationPermissionRequired implements Exception {
  const LocationPermissionRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reports the rider's position for as long as they are online.
///
/// Two things matter about the lifecycle, and both are deliberate:
///
/// * It is tied to `is_online`, never to app foreground/background state. The
///   entire point is that it keeps running while backgrounded — a rider with
///   the phone in a pocket is the normal case, not the exception.
/// * It stops the instant `is_online` goes false. Background location that
///   outlives the shift is both a battery complaint and, on iOS, an App Review
///   problem: the justification for "Always" is a delivery in progress, so when
///   there is no delivery the service genuinely must be off rather than idle.
class LocationReporter {
  LocationReporter({
    required ApiClient client,
    Duration interval = const Duration(seconds: 7),
  }) : _client = client,
       _interval = interval;

  final ApiClient _client;

  /// Ping cadence. The spec window is 5-10s; the server treats a partner with
  /// no ping for 90s as unreachable, so this leaves room for several misses.
  final Duration _interval;

  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  Position? _last;
  var _running = false;

  bool get isRunning => _running;

  /// Most recent fix, for the reassurance map on the dashboard.
  Position? get lastPosition => _last;

  /// Starts the stream and the ping loop.
  ///
  /// Throws [LocationPermissionRequired] when background-capable permission is
  /// missing, so the caller can refuse to go online rather than reporting a
  /// rider as available while nothing is actually tracking them.
  Future<void> start() async {
    if (_running) return;

    final access = await currentAccess();
    if (!access.canGoOnline) {
      throw const LocationPermissionRequired(
        'Allow background location to go online',
      );
    }

    _running = true;
    _sub = Geolocator.getPositionStream(locationSettings: _backgroundSettings())
        .listen(
          (position) => _last = position,
          onError: (_) {
            // A dropped fix is normal (tunnels, parking garages). Keep the
            // loop alive and let the last position stand until a new one lands.
          },
        );

    // Send one immediately so the rider becomes visible to matching without
    // waiting out a full interval.
    await _push();
    _ticker = Timer.periodic(_interval, (_) => _push());
  }

  Future<void> stop() async {
    _running = false;
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
  }

  /// Reads the current permission state, distinguishing "always" from
  /// "while in use" because only the former can survive a screen lock.
  Future<LocationAccess> currentAccess() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.denied;
    }
    return _classify(await Geolocator.checkPermission());
  }

  /// Prompts for permission. Call this only after the explainer card has been
  /// shown — the OS "Always allow" dialog reads as alarming without context.
  Future<LocationAccess> request() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.denied;
    }
    return _classify(await Geolocator.requestPermission());
  }

  /// Deep-links to OS settings, the only route out of a denied or
  /// foreground-only grant.
  Future<void> openSettings() => Geolocator.openAppSettings();

  static LocationAccess _classify(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always => LocationAccess.always,
        LocationPermission.whileInUse => LocationAccess.whileInUseOnly,
        LocationPermission.denied ||
        LocationPermission.deniedForever => LocationAccess.denied,
        LocationPermission.unableToDetermine => LocationAccess.unknown,
      };

  /// Platform settings that keep location flowing with the app backgrounded.
  ///
  /// On Android the foreground-service notification is not decoration: a
  /// persistent ongoing notification is what the platform requires for reliable
  /// background location, and it is also the honest signal to the rider that
  /// something is still running on their behalf.
  static LocationSettings _backgroundSettings() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Passel Rider',
            notificationText: "You're online and available",
            enableWakeLock: true,
          ),
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
          activityType: ActivityType.automotiveNavigation,
          showBackgroundLocationIndicator: true,
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        );
    }
  }

  Future<void> _push() async {
    if (!_running) return;
    final position = _last ?? await _safeCurrentPosition();
    if (position == null) return;

    await _client.post<Map<String, dynamic>>(
      '/api/v1/delivery-partners/location',
      data: {'lat': position.latitude, 'lng': position.longitude},
      fromJson: (d) => d as Map<String, dynamic>,
    );
  }

  Future<Position?> _safeCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition();
    } on Exception {
      return null;
    }
  }
}
