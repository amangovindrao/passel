import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location could not be read, and what the user can do about it.
enum LocationDenial {
  /// Location is switched off for the whole device.
  serviceDisabled,

  /// Refused this time. Asking again is allowed.
  denied,

  /// Refused permanently. Only Settings can undo it.
  deniedForever,

  /// Permission was granted but no fix arrived.
  noFix;

  String get message => switch (this) {
    LocationDenial.serviceDisabled =>
      'Location is turned off on this phone. Switch it on and try again.',
    LocationDenial.denied =>
      'Paasel needs your location to find shops that deliver to you.',
    LocationDenial.deniedForever =>
      'Location is blocked for Paasel. Open Settings to allow it.',
    LocationDenial.noFix =>
      "Couldn't get a fix. Step outside or near a window and try again.",
  };

  /// Whether the only way forward is the OS settings screen.
  bool get needsSettings => this == LocationDenial.deniedForever;
}

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.denial);

  final LocationDenial denial;

  String get message => denial.message;

  @override
  String toString() => message;
}

/// Reads the customer's position, for one purpose: pinning a delivery address.
///
/// This replaces a stub that waited a second, wrote "Detected address
/// placeholder" on screen and then saved Bengaluru city centre for everybody.
/// The permission dialog never appeared, which is what a user notices — but the
/// worse half was silent: every saved address had the same coordinates, so
/// delivery distances and fees were computed against a point nobody lived at.
///
/// Foreground only, unlike the rider app. A customer's position is needed
/// while they are on this screen and never again, so asking for "always" would
/// be both unjustifiable and a review risk.
class CustomerLocationService {
  const CustomerLocationService();

  /// Asks for permission if needed, then returns a position.
  ///
  /// Throws [LocationUnavailable] with a reason worth showing. Call it only
  /// from a button the user pressed, after the explainer — the OS dialog is
  /// alarming without context.
  Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationDenial.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // The actual OS prompt. The old screen never got here.
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        throw const LocationUnavailable(LocationDenial.denied);
      case LocationPermission.deniedForever:
        throw const LocationUnavailable(LocationDenial.deniedForever);
      case LocationPermission.unableToDetermine:
        throw const LocationUnavailable(LocationDenial.noFix);
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // A city address does not need a satellite lock. Falling back to the
          // last known fix beats spinning indefinitely indoors.
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on Exception {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      throw const LocationUnavailable(LocationDenial.noFix);
    }
  }

  /// A street address for [position], or null if the platform cannot name it.
  ///
  /// Best-effort by design. Reverse geocoding needs a network round trip and
  /// can simply have nothing to say about a location, so the caller falls back
  /// to the coordinates rather than blocking on it — a delivery address reading
  /// "12.97160, 77.59460" is usable, and one that never appears is not.
  Future<String?> describe(Position position) async {
    try {
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (places.isEmpty) return null;

      final p = places.first;
      // Street then locality: enough for a rider to find the building, without
      // the country and postcode noise the platform also returns.
      final parts = <String?>[
        p.name,
        p.subLocality,
        p.locality,
      ].where((s) => s != null && s.trim().isNotEmpty).toSet().toList();

      return parts.isEmpty ? null : parts.join(', ');
    } on Exception {
      return null;
    }
  }

  Future<void> openSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
