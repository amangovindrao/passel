import 'package:customer_app/src/features/onboarding/location_setup_screen.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:customer_app/src/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ui_kit/ui_kit.dart';

/// Stands in for the platform. Subclasses the real service so a signature
/// change breaks compilation here rather than diverging quietly.
class _StubLocationService extends CustomerLocationService {
  _StubLocationService({this.position, this.denial, this.described});

  final Position? position;
  final LocationDenial? denial;

  /// What reverse geocoding returns. Null models the platform having nothing to
  /// say, which is common enough to be the default here.
  final String? described;

  int calls = 0;
  int settingsOpened = 0;

  @override
  Future<Position> current() async {
    calls++;
    final failure = denial;
    if (failure != null) throw LocationUnavailable(failure);
    return position!;
  }

  @override
  Future<String?> describe(Position position) async => described;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

Position fixAt(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.now(),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// The screen this replaces never asked the OS for anything: it waited a
/// second, wrote a placeholder on screen, and saved Bengaluru city centre for
/// every customer. So the cases that matter are that permission is genuinely
/// requested, that a refusal is explained rather than swallowed, and that the
/// saved address carries the real fix.
void main() {
  Widget subject(_StubLocationService service) => ProviderScope(
    overrides: [locationServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const LocationSetupScreen(),
    ),
  );

  testWidgets('the explainer comes before any permission request', (
    tester,
  ) async {
    final service = _StubLocationService(position: fixAt(12.9, 77.6));

    await tester.pumpWidget(subject(service));

    expect(find.byKey(const ValueKey('location-explainer')), findsOneWidget);
    expect(find.text('Where do you want delivery?'), findsOneWidget);
    // Nothing asked yet — an unannounced OS dialog is the most refused moment
    // in an app like this.
    expect(service.calls, 0);
  });

  testWidgets('tapping allow actually asks the platform', (tester) async {
    final service = _StubLocationService(position: fixAt(12.9, 77.6));
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
  });

  testWidgets('the confirm step shows the real coordinates', (tester) async {
    final service = _StubLocationService(position: fixAt(19.07283, 72.88261));
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('location-confirm')), findsOneWidget);
    // Mumbai, not the hardcoded Bengaluru point the old screen always saved.
    final readout = tester.widget<Text>(
      find.byKey(const ValueKey('detected-coordinates')),
    );
    expect(readout.data, '19.07283, 72.88261');
  });

  testWidgets('a refusal is explained and can be retried', (tester) async {
    final service = _StubLocationService(denial: LocationDenial.denied);
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('location-denied')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const ValueKey('location-confirm')), findsNothing);
  });

  testWidgets('a permanent block offers Settings rather than a dead retry', (
    tester,
  ) async {
    final service = _StubLocationService(denial: LocationDenial.deniedForever);
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    // Asking again is a no-op once the OS has stopped prompting, so offering
    // "Try again" here would be a button that can never work.
    expect(find.byKey(const ValueKey('open-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('allow-location')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();
    expect(service.settingsOpened, 1);
  });

  testWidgets('location switched off device-wide says so', (tester) async {
    final service = _StubLocationService(
      denial: LocationDenial.serviceDisabled,
    );
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    expect(find.textContaining('turned off'), findsOneWidget);
    expect(find.text('Location settings'), findsOneWidget);
  });

  testWidgets('the address field is prefilled with the fix and is editable', (
    tester,
  ) async {
    final service = _StubLocationService(position: fixAt(12.97160, 77.59460));
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(field).controller!.text,
      '12.97160, 77.59460',
    );

    await tester.enterText(field, 'Flat 3B, Rose Apartments');
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text,
      'Flat 3B, Rose Apartments',
    );
  });

  testWidgets('a resolved street address is used instead of coordinates', (
    tester,
  ) async {
    final service = _StubLocationService(
      position: fixAt(12.97160, 77.59460),
      described: 'MG Road, Shivaji Nagar, Bengaluru',
    );
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    // Far more use to a rider than six decimal places.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'MG Road, Shivaji Nagar, Bengaluru',
    );
  });

  testWidgets('coordinates still show when geocoding has nothing to say', (
    tester,
  ) async {
    final service = _StubLocationService(position: fixAt(12.97160, 77.59460));
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    // A usable fallback beats an empty field.
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '12.97160, 77.59460',
    );
  });

  testWidgets('going back to the explainer re-asks for a position', (
    tester,
  ) async {
    final service = _StubLocationService(position: fixAt(12.9, 77.6));
    await tester.pumpWidget(subject(service));

    await tester.tap(find.byKey(const ValueKey('allow-location')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use a different location'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('location-explainer')), findsOneWidget);
  });
}
