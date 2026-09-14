import 'package:core/core.dart';
import 'package:delivery_app/src/alerts/alert_dispatcher.dart';
import 'package:delivery_app/src/alerts/fcm_alert_transport.dart';
import 'package:delivery_app/src/features/offers/offer_screen.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:delivery_app/src/routing/rider_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

void main() => bootstrap(() async {
  EnvConfig.validate();

  // Push is the only way to reach a backgrounded phone, but a missing or
  // misconfigured Firebase setup must not lock a rider out of the app
  // entirely — they can still work from a foregrounded screen. So this
  // degrades rather than crashes, and the app is told which it got.
  final pushAvailable = await _initFirebase();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  await SentryFlutter.init(
    (options) {
      options
        ..dsn = EnvConfig.sentryDsn
        ..environment = EnvConfig.flavor;
    },
    appRunner: () => runApp(
      ProviderScope(
        overrides: [
          // The real transport lives here rather than in the provider so `core`
          // stays Firebase-free and tests can swap in an in-memory one.
          alertCenterProvider.overrideWith((ref) {
            final center = AlertCenter(
              transport: pushAvailable
                  ? FcmAlertTransport()
                  : InMemoryAlertTransport(),
              signal: PlatformAlertSignal(),
            );
            ref.onDispose(center.dispose);
            return center;
          }),
        ],
        child: const PaaselRiderApp(),
      ),
    ),
  );
});

/// Returns whether push is usable.
///
/// On Android this needs `android/app/google-services.json`, read at build time
/// by the `com.google.gms.google-services` Gradle plugin. With no Firebase
/// project wired up, initialisation throws — and that is a configuration gap,
/// not a reason to refuse to start.
Future<bool> _initFirebase() async {
  try {
    return await Firebase.initializeApp()
        .then((_) => true)
        .timeout(const Duration(milliseconds: 300), onTimeout: () => false);
  } on Object catch (_) {
    return false;
  }
}

class PaaselRiderApp extends ConsumerStatefulWidget {
  const PaaselRiderApp({super.key});

  @override
  ConsumerState<PaaselRiderApp> createState() => _PaaselRiderAppState();
}

class _PaaselRiderAppState extends ConsumerState<PaaselRiderApp> {
  @override
  void initState() {
    super.initState();
    try {
      ref.read(alertDispatcherProvider).start();
      ref.read(offerPollerProvider);
    } on Object catch (e) {
      debugPrint('PaaselRiderApp startup listener warning: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Passel Rider',
      theme: PaaselTheme.light,
      darkTheme: PaaselTheme.dark,
      // Riders work at night and often one-handed on a bright street; the dark
      // face is the product here, not a preference.
      themeMode: ThemeMode.dark,
      routerConfig: riderRouter,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => OfferHost(child: child),
    );
  }
}

/// Puts the offer surface above whatever screen the rider is on.
///
/// An offer can arrive at any moment — on the dashboard, mid-trip, anywhere —
/// and both the fresh and detour flows need to interrupt without disturbing the
/// navigation stack underneath. Overlaying beats pushing a route: nothing to
/// unwind afterwards, and the screen behind is exactly as it was.
class OfferHost extends ConsumerWidget {
  const OfferHost({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(currentOfferProvider);

    return Stack(
      children: [
        child ?? const SizedBox.shrink(),
        if (offer != null) _OfferLayer(offer: offer),
      ],
    );
  }
}

class _OfferLayer extends StatelessWidget {
  const _OfferLayer({required this.offer});

  final RiderOffer offer;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: AppColors.ink,
        child: OfferScreen(key: ValueKey(offer.assignmentId), offer: offer),
      ),
    );
  }
}
