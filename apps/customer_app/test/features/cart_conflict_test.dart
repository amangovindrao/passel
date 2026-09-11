import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wouldConflict returns true when adding from a different shop', () {
    final notifier = CartNotifier();

    // Add item from shop A
    const productA = ShopProduct(
      id: 'p1',
      name: 'Product A',
      pricePaise: 5000,
      stockStatus: 'available',
    );
    notifier.addProduct('shop_a', productA);

    // Should conflict when trying to add from shop B
    expect(notifier.wouldConflict('shop_b'), isTrue);
    expect(notifier.wouldConflict('shop_a'), isFalse);
  });

  test('clearAndAdd replaces cart with new shop product', () {
    final notifier = CartNotifier();

    const productA = ShopProduct(
      id: 'p1',
      name: 'Product A',
      pricePaise: 5000,
      stockStatus: 'available',
    );
    const productB = ShopProduct(
      id: 'p2',
      name: 'Product B',
      pricePaise: 3000,
      stockStatus: 'available',
    );

    notifier.addProduct('shop_a', productA);
    expect(notifier.state.shopId, 'shop_a');

    notifier.clearAndAdd('shop_b', productB);
    expect(notifier.state.shopId, 'shop_b');
    expect(notifier.state.items.length, 1);
    expect(notifier.state.items['p2']!.product.name, 'Product B');
  });

  test('cart computes subtotal correctly', () {
    final notifier = CartNotifier();
    const product = ShopProduct(
      id: 'p1',
      name: 'Chai',
      pricePaise: 2000,
      stockStatus: 'available',
    );

    notifier
      ..addProduct('shop_a', product)
      ..addProduct('shop_a', product)
      ..addProduct('shop_a', product);

    expect(notifier.state.itemCount, 3);
    expect(notifier.state.subtotalPaise, 6000);
  });
}
