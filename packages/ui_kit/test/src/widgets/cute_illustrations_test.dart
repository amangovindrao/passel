import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  group('Cute Illustrations & Micro-interactions', () {
    testWidgets('CuteShoppingMascot renders properly in static mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CuteShoppingMascot(
              size: 100,
              animated: false,
              mood: MascotMood.celebrating,
            ),
          ),
        ),
      );
      expect(find.byType(CuteShoppingMascot), findsOneWidget);
    });

    testWidgets('SmilingGroceryIllustration renders properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SmilingGroceryIllustration(size: 90),
          ),
        ),
      );
      expect(find.byType(SmilingGroceryIllustration), findsOneWidget);
    });

    testWidgets('CuteEmptyCartIllustration renders properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CuteEmptyCartIllustration(size: 100),
          ),
        ),
      );
      expect(find.byType(CuteEmptyCartIllustration), findsOneWidget);
    });

    testWidgets('CuteDeliveryScooter renders properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CuteDeliveryScooter(size: 60),
          ),
        ),
      );
      expect(find.byType(CuteDeliveryScooter), findsOneWidget);
    });

    testWidgets('TinyFloatingHeartButton renders and triggers callback', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TinyFloatingHeartButton(
              isFav: false,
              isEnabled: true,
              onToggle: () => toggled = true,
            ),
          ),
        ),
      );

      expect(find.byType(TinyFloatingHeartButton), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      expect(toggled, isTrue);
    });

    testWidgets('WalletCelebrationDialog displays dialog contents', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => WalletCelebrationDialog.show(
                  context,
                  title: 'Cashback Celebration! ✨',
                  subtitle: '5% bonus credited',
                  amountText: '\u20b925.00',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Cashback Celebration! ✨'), findsOneWidget);
      expect(find.text('\u20b925.00'), findsOneWidget);
      expect(find.text('5% bonus credited'), findsOneWidget);

      await tester.tap(find.text('Awesome!'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(WalletCelebrationDialog), findsNothing);
    });
  });
}
