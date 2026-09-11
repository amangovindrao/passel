import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  Widget subject(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('PrimaryButton invokes its callback when enabled', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      subject(PrimaryButton(label: 'Place order', onPressed: () => presses++)),
    );

    await tester.tap(find.text('Place order'));
    expect(presses, 1);
  });

  testWidgets('PrimaryButton does not invoke callback when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(const PrimaryButton(label: 'Place order', onPressed: null)),
    );

    await tester.tap(find.text('Place order'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PrimaryButton loading state replaces label and is disabled', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      subject(
        PrimaryButton(
          label: 'Place order',
          loading: true,
          onPressed: () => presses++,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('button-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('Place order'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(presses, 0);
  });
}
