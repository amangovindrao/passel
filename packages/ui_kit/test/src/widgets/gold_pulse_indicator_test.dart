import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  Widget subject({required bool reducedMotion}) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData().copyWith(disableAnimations: reducedMotion),
        child: const Scaffold(body: GoldPulseIndicator()),
      ),
    );
  }

  testWidgets('GoldPulseIndicator shows a dot and animated ring', (
    tester,
  ) async {
    await tester.pumpWidget(subject(reducedMotion: false));

    expect(find.byKey(const ValueKey('gold-pulse-dot')), findsOneWidget);
    expect(find.byKey(const ValueKey('gold-pulse-ring')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('gold-pulse-ring')), findsOneWidget);
  });

  testWidgets('reduced motion freezes the pulse on the solid dot', (
    tester,
  ) async {
    await tester.pumpWidget(subject(reducedMotion: true));

    expect(find.byKey(const ValueKey('gold-pulse-dot')), findsOneWidget);
    expect(find.byKey(const ValueKey('gold-pulse-ring')), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('gold-pulse-ring')), findsNothing);
    expect(find.byKey(const ValueKey('gold-pulse-dot')), findsOneWidget);
  });
}
