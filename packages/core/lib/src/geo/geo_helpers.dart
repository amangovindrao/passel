import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Geolocation helpers for permission handling and position streaming.
class GeoHelpers {
  GeoHelpers._();

  /// Checks and requests location permissions.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  static Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Returns the current device position.
  ///
  /// Throws if permissions are not granted.
  static Future<Position> currentPosition() async {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Streams position updates.
  static Stream<Position> positionStream({
    int distanceFilter = 10,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    );
  }
}
