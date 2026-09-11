import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// The three apps each had their own copy of this and each was missing
/// something different. These tests pin down the parts that were missing.
void main() {
  Widget host({
    required ValueChanged<String> onCompleted,
    String? errorText,
    bool enabled = true,
    GlobalKey<OtpCodeFieldState>? fieldKey,
  }) => MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(
      body: OtpCodeField(
        key: fieldKey,
        onCompleted: onCompleted,
        errorText: errorText,
        enabled: enabled,
        autofocus: false,
      ),
    ),
  );

  Finder box(int i) => find.byKey(ValueKey('otp-box-$i'));

  testWidgets('renders six boxes', (tester) async {
    await tester.pumpWidget(host(onCompleted: (_) {}));

    for (var i = 0; i < 6; i++) {
      expect(box(i), findsOneWidget);
    }
  });

  testWidgets('typing all six digits reports the code once', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    for (var i = 0; i < 6; i++) {
      await tester.enterText(box(i), '${i + 1}');
      await tester.pump();
    }

    expect(reported, ['123456']);
  });

  testWidgets('a completed code is reported exactly once, not per rebuild', (
    tester,
  ) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    for (var i = 0; i < 6; i++) {
      await tester.enterText(box(i), '9');
      await tester.pump();
    }
    // Extra frames must not re-submit; an auto-submitting screen would fire a
    // second verify request against a code the server has already consumed.
    await tester.pump();
    await tester.pump();

    expect(reported, hasLength(1));
  });

  testWidgets('pasting the whole code into the first box spreads it', (
    tester,
  ) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    // What an SMS autofill actually does.
    await tester.enterText(box(0), '123456');
    await tester.pump();

    expect(reported, ['123456']);
    expect(tester.widget<TextField>(box(0)).controller!.text, '1');
    expect(tester.widget<TextField>(box(5)).controller!.text, '6');
  });

  testWidgets('a pasted code with spacing is cleaned up', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    await tester.enterText(box(0), '12 34-56');
    await tester.pump();

    expect(reported, ['123456']);
  });

  testWidgets('retyping over a filled box replaces that digit only', (
    tester,
  ) async {
    await tester.pumpWidget(host(onCompleted: (_) {}));

    await tester.enterText(box(0), '1');
    await tester.pump();
    await tester.enterText(box(1), '2');
    await tester.pump();

    // Simulates the field arriving with the old digit still present.
    await tester.enterText(box(0), '19');
    await tester.pump();

    // The later digit wins for that box, and box 1 is untouched — treating this
    // as a paste would have wiped it.
    expect(tester.widget<TextField>(box(0)).controller!.text, '9');
    expect(tester.widget<TextField>(box(1)).controller!.text, '2');
  });

  testWidgets('an incomplete code reports nothing', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    for (var i = 0; i < 5; i++) {
      await tester.enterText(box(i), '1');
      await tester.pump();
    }

    expect(reported, isEmpty);
  });

  testWidgets('an error message is shown beneath the boxes', (tester) async {
    await tester.pumpWidget(
      host(onCompleted: (_) {}, errorText: "That code isn't right."),
    );

    expect(find.byKey(const ValueKey('otp-error')), findsOneWidget);
    expect(find.text("That code isn't right."), findsOneWidget);
  });

  testWidgets('clear empties every box and allows a fresh submission', (
    tester,
  ) async {
    final reported = <String>[];
    final key = GlobalKey<OtpCodeFieldState>();
    await tester.pumpWidget(host(onCompleted: reported.add, fieldKey: key));

    for (var i = 0; i < 6; i++) {
      await tester.enterText(box(i), '1');
      await tester.pump();
    }
    expect(reported, hasLength(1));

    key.currentState!.clear();
    await tester.pump();

    expect(tester.widget<TextField>(box(0)).controller!.text, '');
    expect(tester.widget<TextField>(box(5)).controller!.text, '');

    // And a retyped code submits again rather than being swallowed by the
    // once-only guard.
    for (var i = 0; i < 6; i++) {
      await tester.enterText(box(i), '2');
      await tester.pump();
    }
    expect(reported, ['111111', '222222']);
  });

  testWidgets('boxes are inert while a code is being checked', (tester) async {
    await tester.pumpWidget(host(onCompleted: (_) {}, enabled: false));

    // Otherwise the digits can change underneath the request verifying them.
    expect(tester.widget<TextField>(box(0)).enabled, isFalse);
  });

  testWidgets('non-digits are rejected', (tester) async {
    final reported = <String>[];
    await tester.pumpWidget(host(onCompleted: reported.add));

    await tester.enterText(box(0), 'a');
    await tester.pump();

    expect(tester.widget<TextField>(box(0)).controller!.text, '');
    expect(reported, isEmpty);
  });
}
