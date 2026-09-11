import 'package:core/core.dart';
import 'package:customer_app/src/features/discovery/home_screen.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('Shop list renders open shops before closed shops', (
    tester,
  ) async {
    // Arrange: provide mock data via overrides
    final mockShops = [
      const NearbyShop(
        id: '1',
        name: 'Closed Shop',
        category: 'grocery',
        isOpen: false,
        distanceM: 500,
        deliveryRadiusKm: 4,
      ),
      const NearbyShop(
        id: '2',
        name: 'Open Shop',
        category: 'grocery',
        isOpen: true,
        distanceM: 800,
        deliveryRadiusKm: 4,
      ),
      const NearbyShop(
        id: '3',
        name: 'Another Open',
        category: 'food',
        isOpen: true,
        distanceM: 1200,
        deliveryRadiusKm: 5,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nearbyShopsProvider.overrideWith((ref) async => mockShops),
          activeAddressProvider.overrideWith(
            (ref) => const SavedAddress(
              id: 'addr1',
              label: 'Home',
              addressText: '123 Test St',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          // The shop cards carry a GoldPulseIndicator, which repeats forever —
          // pumpAndSettle would wait for an animation that never ends. The
          // indicator stops its controller under reduced motion, which is the
          // escape hatch it was built with.
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: HomeScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Find shop name texts
    final openShop = find.text('Open Shop');
    final anotherOpen = find.text('Another Open');
    final closedShop = find.text('Closed Shop');

    expect(openShop, findsOneWidget);
    expect(anotherOpen, findsOneWidget);
    expect(closedShop, findsOneWidget);

    // Open shops should appear before closed shops in the render tree
    final openPos = tester.getTopLeft(openShop).dy;
    final closedPos = tester.getTopLeft(closedShop).dy;
    expect(openPos, lessThan(closedPos));
  });
}
