import 'package:delivery_app/src/features/onboarding/kyc_screen.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:delivery_app/src/services/document_uploader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/stubs.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Stands in for the real uploader. Subclasses it rather than defining a
/// parallel interface, so a signature change breaks compilation here.
class _StubUploader extends DocumentUploader {
  _StubUploader({this.url = 'https://storage.test/signed/id.jpg', this.throws})
    : super(client: _MockSupabaseClient());

  final String? url;
  final DocumentUploadFailure? throws;
  final picked = <DocumentKind>[];

  @override
  Future<String?> pickAndUpload({
    required DocumentKind kind,
    ImageSource source = ImageSource.camera,
  }) async {
    picked.add(kind);
    if (throws != null) throw throws!;
    return url;
  }
}

void main() {
  late _StubUploader uploader;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        documentUploaderProvider.overrideWithValue(uploader),
        apiClientProvider.overrideWithValue(
          stubApiClient(const {
            '/delivery-partners/kyc': StubResponse(200, {
              'status': 'pending',
              'kyc_status': 'pending',
            }),
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget subject(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(theme: AppTheme.dark(), home: const RiderKycScreen()),
  );

  Finder submitButton() => find.descendant(
    of: find.byKey(const ValueKey('kyc-submit')),
    matching: find.byType(FilledButton),
  );

  /// The form is a ListView, so on a default 800x600 surface the lower fields
  /// are never built and cannot be found. A tall viewport renders the whole
  /// thing, which is what these assertions are about.
  void useTallSurface(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1200, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  setUp(() => uploader = _StubUploader());

  testWidgets('submit stays disabled until a document is actually stored', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);

    // Payout details alone are not enough.
    await tester.enterText(
      find.widgetWithText(TextField, 'name@bank'),
      'rider@bank',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNull,
      reason: 'no ID proof uploaded yet',
    );
  });

  testWidgets('a failed upload does not mark the document as provided', (
    tester,
  ) async {
    uploader = _StubUploader(
      throws: const DocumentUploadFailure('Could not upload that photo'),
    );
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    await tester.tap(find.byKey(const ValueKey('upload-id-proof')));
    await tester.pumpAndSettle();

    expect(uploader.picked, [DocumentKind.idProof]);
    // The failure is surfaced, and the tile has not flipped to "added".
    expect(find.text('Could not upload that photo'), findsOneWidget);
    expect(find.text('ID proof added'), findsNothing);
    expect(find.text('Upload ID proof'), findsOneWidget);
  });

  testWidgets('a cancelled picker leaves the form untouched', (tester) async {
    uploader = _StubUploader(url: null);
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    await tester.tap(find.byKey(const ValueKey('upload-id-proof')));
    await tester.pumpAndSettle();

    // Backing out of the picker is normal, not an error.
    expect(find.text('ID proof added'), findsNothing);
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);
  });

  testWidgets('a stored document enables submit once payout details exist', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    await tester.tap(find.byKey(const ValueKey('upload-id-proof')));
    await tester.pumpAndSettle();
    expect(find.text('ID proof added'), findsOneWidget);

    // Bicycle needs no plate or licence, so this is the whole form.
    await tester.tap(find.text('Bicycle'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'name@bank'),
      'rider@bank',
    );
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNotNull);
  });

  testWidgets('bicycle hides the plate and licence fields outright', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    // Bike is the default, so both are present to begin with.
    expect(find.widgetWithText(TextField, 'e.g. KA01AB1234'), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-licence')), findsOneWidget);

    await tester.tap(find.text('Bicycle'));
    await tester.pumpAndSettle();

    // Gone entirely, not greyed out — a disabled field still reads as
    // something the rider is failing to fill in.
    expect(find.widgetWithText(TextField, 'e.g. KA01AB1234'), findsNothing);
    expect(find.byKey(const ValueKey('upload-licence')), findsNothing);
  });

  testWidgets('switching to bicycle discards an already-uploaded licence', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    await tester.tap(find.byKey(const ValueKey('upload-id-proof')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('upload-licence')));
    await tester.pumpAndSettle();
    expect(find.text('Licence added'), findsOneWidget);

    await tester.tap(find.text('Bicycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scooter'));
    await tester.pumpAndSettle();

    // Back on a motorised vehicle the licence is asked for again — the request
    // must not carry a licence the rider thinks they removed.
    expect(find.text('Licence added'), findsNothing);
    expect(find.text('Upload driving licence'), findsOneWidget);
  });

  testWidgets('a motorised vehicle needs both plate and licence', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(subject(container()));

    await tester.tap(find.byKey(const ValueKey('upload-id-proof')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'name@bank'),
      'rider@bank',
    );
    await tester.pumpAndSettle();

    // ID + payout but no plate, no licence.
    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. KA01AB1234'),
      'KA01AB1234',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(submitButton()).onPressed,
      isNull,
      reason: 'still no licence',
    );

    await tester.tap(find.byKey(const ValueKey('upload-licence')));
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(submitButton()).onPressed, isNotNull);
  });
}
