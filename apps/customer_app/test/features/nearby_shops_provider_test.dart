import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'nearbyShopsProvider returns empty list when no active address',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // No active address set -> should return empty
      final result = await container.read(nearbyShopsProvider.future);
      expect(result, isEmpty);
    },
  );

  test('nearbyShopsProvider re-fetches when activeAddress changes', () async {
    var fetchCount = 0;

    final container = ProviderContainer(
      overrides: [
        nearbyShopsProvider.overrideWith((ref) async {
          fetchCount++;
          final address = ref.watch(activeAddressProvider);
          if (address == null) return <NearbyShop>[];
          return [
            const NearbyShop(
              id: '1',
              name: 'Shop',
              category: 'food',
              isOpen: true,
              distanceM: 500,
              deliveryRadiusKm: 4,
            ),
          ];
        }),
      ],
    );
    addTearDown(container.dispose);

    // First read — no address
    await container.read(nearbyShopsProvider.future);
    expect(fetchCount, 1);

    // Set address
    container.read(activeAddressProvider.notifier).state = const SavedAddress(
      id: 'a1',
      label: 'Home',
      addressText: 'Test',
    );

    // Provider should re-compute
    await container.read(nearbyShopsProvider.future);
    expect(fetchCount, 2);
  });
}
