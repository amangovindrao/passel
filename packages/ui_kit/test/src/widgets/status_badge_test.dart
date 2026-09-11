import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  Widget subject(StatusBadgeState status) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: StatusBadge(status: status)),
    );
  }

  testWidgets('StatusBadge renders the matching order-state label', (
    tester,
  ) async {
    const cases = <StatusBadgeState, String>{
      StatusBadgeState.preparing: 'Preparing',
      StatusBadgeState.readyForPickup: 'Ready for pickup',
      StatusBadgeState.outForDelivery: 'Out for delivery',
      StatusBadgeState.delivered: 'Delivered',
      StatusBadgeState.cancelled: 'Cancelled',
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(subject(entry.key));
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('Out for delivery includes the live pulse', (tester) async {
    await tester.pumpWidget(subject(StatusBadgeState.outForDelivery));

    expect(find.byType(GoldPulseIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('gold-pulse-ring')), findsOneWidget);
  });
}
