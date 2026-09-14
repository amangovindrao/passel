import 'package:customer_app/src/features/orders/group_order_screen.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Group Order & Private Cart Privacy Mode Unit Tests', () {
    test('default behavior has private_cart_mode OFF', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final groupState = container.read(groupOrderStateProvider);
      expect(groupState.session, isNotNull);
      expect(groupState.isPrivateCartMode, isFalse);
      expect(groupState.session!.privateCartMode, isFalse);
    });

    test('any member can activate Private Cart Mode immediately', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(groupOrderStateProvider.notifier);
      await notifier.togglePrivacy(enable: true);

      final updatedState = container.read(groupOrderStateProvider);
      expect(updatedState.isPrivateCartMode, isTrue);
      expect(updatedState.session!.privateCartMode, isTrue);
      expect(container.read(isPrivateCartModeActiveProvider), isTrue);
    });

    test('disabling Private Cart Mode without confirmation is rejected', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(groupOrderStateProvider.notifier);
      // Turn ON first
      await notifier.togglePrivacy(enable: true);
      expect(container.read(isPrivateCartModeActiveProvider), isTrue);

      // Attempt to turn OFF without confirmDisable
      await notifier.togglePrivacy(enable: false, confirmDisable: false);
      final state = container.read(groupOrderStateProvider);
      expect(state.isPrivateCartMode, isTrue); // Remained protected!
      expect(state.errorMessage, contains('confirmation'));
    });

    test('disabling Private Cart Mode with explicit confirmation succeeds', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(groupOrderStateProvider.notifier);
      await notifier.togglePrivacy(enable: true);
      expect(container.read(isPrivateCartModeActiveProvider), isTrue);

      await notifier.togglePrivacy(enable: false, confirmDisable: true);
      final state = container.read(groupOrderStateProvider);
      expect(state.isPrivateCartMode, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('locked group order session freezes privacy settings', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(groupOrderStateProvider.notifier);
      await notifier.togglePrivacy(enable: true);

      // Lock the session
      notifier.lockSession();
      final lockedState = container.read(groupOrderStateProvider);
      expect(lockedState.isLocked, isTrue);

      // Attempt to toggle privacy after lock
      await notifier.togglePrivacy(enable: false, confirmDisable: true);
      final finalState = container.read(groupOrderStateProvider);
      expect(finalState.isPrivateCartMode, isTrue); // Stays private!
      expect(finalState.errorMessage, contains('locked'));
    });
  });

  group('GroupOrderScreen Widget Tests', () {
    testWidgets('renders Private Cart toggle, aggregate stats, and user cart', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GroupOrderScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Header society name
      expect(find.text('Palm Heights Tower B'), findsOneWidget);

      // 2. Private Cart toggle card
      expect(find.text('🔒 Private Cart'), findsOneWidget);
      expect(find.text('Keep your shopping private from the group.'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);

      // 3. Aggregate progress stats
      expect(find.text('joined'), findsOneWidget);
      expect(find.text('shops'), findsOneWidget);
      expect(find.text('paid'), findsOneWidget);
      expect(find.text('delivery'), findsOneWidget);

      // 4. User personal items section
      expect(find.text('My Items'), findsOneWidget);
      expect(find.text('Amul Gold Milk 500ml'), findsOneWidget);
      expect(find.text('Harvest Brown Bread'), findsOneWidget);

      // 5. Group members section
      expect(find.text('Group Members'), findsOneWidget);
      expect(find.text('Riya'), findsOneWidget);
      expect(find.text('Vikram'), findsOneWidget);
    });

    testWidgets('toggling switch in UI activates Private Mode and displays confirmation snackbar', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: GroupOrderScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      // Tap the switch to enable Private Cart Mode
      await tester.tap(switchFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // Verify active badge appears
      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('🔒 Private'), findsOneWidget);
      expect(find.text('Carts Protected'), findsOneWidget);

      // Verify snackbar appears with required explanation
      expect(find.textContaining('Private Cart Enabled 🔒'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });
  });
}
