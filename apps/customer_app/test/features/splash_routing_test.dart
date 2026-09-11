import 'package:customer_app/src/features/onboarding/splash_screen.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

/// The splash has to actually leave.
///
/// It stopped leaving once the artificial 800ms delay was removed: reading the
/// session is synchronous, so with no session the very next statement was a
/// `context.go` running inside `initState`, before the tree was mounted. That
/// throws while looking up the router, the throw lands in an unawaited Future,
/// and the only visible symptom is an app that sits on its splash screen
/// forever. No existing test noticed, because none of them pumped the splash.
void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  Widget subject() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
        GoRoute(
          path: '/phone',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('phone step'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  testWidgets('with no session the splash routes to phone entry', (
    tester,
  ) async {
    when(() => auth.currentSession).thenReturn(null);

    await tester.pumpWidget(subject());
    // The splash paints first, then routing runs on the post-frame callback.
    expect(find.byType(BrandSplash), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('phone step'), findsOneWidget);
    expect(find.byType(BrandSplash), findsNothing);
  });

  testWidgets('the splash paints before it decides anything', (tester) async {
    when(() => auth.currentSession).thenReturn(null);

    await tester.pumpWidget(subject());

    // Deciding during initState is exactly the bug; the brand frame has to be
    // on screen first.
    expect(find.byType(BrandSplash), findsOneWidget);
    expect(find.text('phone step'), findsNothing);

    await tester.pumpAndSettle();
  });
}
