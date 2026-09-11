import 'package:delivery_app/src/features/home/widgets/position_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

Position _at(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime.utc(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 1,
);

Widget subject({required bool isOnline, Position? position}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: PositionCard(isOnline: isOnline, position: position),
  ),
);

void main() {
  testWidgets('with no fix yet it says so instead of showing a blank map', (
    tester,
  ) async {
    await tester.pumpWidget(subject(isOnline: true));

    expect(find.text('Finding your position'), findsOneWidget);
    expect(find.text('No fix yet'), findsOneWidget);
    // An empty grey square would be ambiguous; the placeholder is not.
    expect(find.byType(GoogleMap), findsNothing);
  });

  testWidgets('a fix renders the map and the coordinates together', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(isOnline: true, position: _at(12.97160, 77.59460)),
    );

    expect(find.byKey(const ValueKey('rider-position-map')), findsOneWidget);
    // Coordinates stay visible: they are unambiguous even when tiles have not
    // loaded, or when the Maps key is missing entirely.
    expect(find.text('12.97160, 77.59460'), findsOneWidget);
    expect(find.text('Finding your position'), findsNothing);
  });

  testWidgets('the map is reassurance only, with every gesture disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(isOnline: true, position: _at(12.9716, 77.5946)),
    );

    final map = tester.widget<GoogleMap>(
      find.byKey(const ValueKey('rider-position-map')),
    );

    expect(map.scrollGesturesEnabled, isFalse);
    expect(map.zoomGesturesEnabled, isFalse);
    expect(map.rotateGesturesEnabled, isFalse);
    expect(map.tiltGesturesEnabled, isFalse);
    expect(map.zoomControlsEnabled, isFalse);
    expect(map.myLocationButtonEnabled, isFalse);
    expect(map.markers, hasLength(1));
  });

  testWidgets('offline says the location is idle and drops the pulse', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(isOnline: false, position: _at(12.9716, 77.5946)),
    );

    expect(find.text('Location idle'), findsOneWidget);
    expect(find.text('Sharing your location'), findsNothing);
    expect(find.byType(GoldPulseIndicator), findsNothing);
  });

  testWidgets('online says it is sharing, with the live pulse', (tester) async {
    await tester.pumpWidget(
      subject(isOnline: true, position: _at(12.9716, 77.5946)),
    );

    expect(find.text('Sharing your location'), findsOneWidget);
    expect(find.byType(GoldPulseIndicator), findsOneWidget);
  });
}
