import 'package:core/core.dart';
import 'package:customer_app/src/features/cart/cart_screen.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('checkout button disabled with shortfall message below minimum', (
    tester,
  ) async {
    // Setup cart with items below ₹99
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const product = ShopProduct(
      id: 'p1',
      name: 'Small item',
      pricePaise: 5000,
      stockStatus: 'available',
    );
    container.read(cartProvider.notifier).addProduct('shop1', product);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Button should be disabled
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Proceed to Checkout'),
    );
    expect(button.onPressed, isNull);

    // Shortfall message should be visible
    expect(find.textContaining('more to meet'), findsOneWidget);
  });

  testWidgets('checkout button enabled when above minimum', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const product = ShopProduct(
      id: 'p1',
      name: 'Big item',
      pricePaise: 15000,
      stockStatus: 'available',
    );
    container.read(cartProvider.notifier).addProduct('shop1', product);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const CartScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Proceed to Checkout'),
    );
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('more to meet'), findsNothing);
  });
}
