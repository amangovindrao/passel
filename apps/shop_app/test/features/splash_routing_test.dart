import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shop_app/src/features/onboarding/splash_screen.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show GoTrueClient, SupabaseClient;
import 'package:ui_kit/ui_kit.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

/// The splash has to actually leave. It stopped leaving when the artificial
/// delay was removed and `context.go` ended up running inside `initState`,
/// which throws into an unawaited Future and strands the app on its splash.
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
        GoRoute(path: '/', builder: (_, __) => const ShopSplashScreen()),
        GoRoute(
          path: '/phone',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('phone step'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: [supabaseProvider.overrideWithValue(client)],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    );
  }

  testWidgets('with no session the splash routes to phone entry', (
    tester,
  ) async {
    when(() => auth.currentSession).thenReturn(null);

    await tester.pumpWidget(subject());
    expect(find.byType(BrandSplash), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('phone step'), findsOneWidget);
  });
}
