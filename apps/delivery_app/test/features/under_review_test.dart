import 'package:delivery_app/src/features/onboarding/under_review_screen.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

ProviderContainer _container(RiderData rider) {
  final c = ProviderContainer(
    overrides: [riderDataProvider.overrideWith((ref) async => rider)],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _subject(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: AppTheme.dark(),
    home: const UnderReviewScreen(),
  ),
);

void main() {
  testWidgets('a pending application waits, with no rejection surface', (
    tester,
  ) async {
    final c = _container(
      const RiderData(exists: true, name: 'Ravi', kycStatus: 'pending'),
    );

    await tester.pumpWidget(_subject(c));
    await tester.pump();

    expect(find.text('Under review'), findsOneWidget);
    expect(find.byKey(const ValueKey('kyc-rejection-reason')), findsNothing);
    expect(find.text('Update documents'), findsNothing);
  });

  testWidgets("a rejection shows the reviewer's actual words", (tester) async {
    final c = _container(
      const RiderData(
        exists: true,
        name: 'Ravi',
        kycStatus: 'rejected',
        kycRejectionReason: 'Driving licence has expired',
      ),
    );

    await tester.pumpWidget(_subject(c));
    await tester.pump();

    expect(find.text('We could not verify you'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('kyc-rejection-reason')),
      findsOneWidget,
    );
    // The specific reason, not a generic apology — this is what tells the rider
    // which document to fix.
    expect(find.text('Driving licence has expired'), findsOneWidget);
    expect(find.text('Update documents'), findsOneWidget);
  });

  testWidgets('a rejection with no reason still offers a way forward', (
    tester,
  ) async {
    final c = _container(
      const RiderData(exists: true, kycStatus: 'rejected'),
    );

    await tester.pumpWidget(_subject(c));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('kyc-rejection-reason')),
      findsOneWidget,
    );
    expect(
      find.textContaining('did not check out'),
      findsOneWidget,
      reason: 'falls back rather than showing an empty card',
    );
    expect(find.text('Update documents'), findsOneWidget);
  });
}
