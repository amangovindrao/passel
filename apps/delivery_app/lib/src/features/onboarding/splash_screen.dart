import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Splash: the route guard. Re-runs on every launch and on resume.
///
/// The verification state is always re-read from the server rather than trusted
/// from cache — an approval or rejection can land while the app is closed,
/// and routing a rejected partner to the dashboard is worse than a slow start.
class RiderSplashScreen extends ConsumerStatefulWidget {
  const RiderSplashScreen({super.key});

  @override
  ConsumerState<RiderSplashScreen> createState() => _RiderSplashScreenState();
}

class _RiderSplashScreenState extends ConsumerState<RiderSplashScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, not during initState — reading the session is
    // synchronous, so on a fresh install the next statement navigates, and
    // navigating before the tree is mounted throws inside an unawaited Future
    // where nobody sees it. The symptom is a splash that never moves.
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      ref.invalidate(riderDataProvider);
    }
  }

  Future<void> _route() async {
    if (!mounted) return;
    final session = ref.read(supabaseProvider).auth.currentSession;
    if (session == null) {
      context.go('/phone');
      return;
    }

    final client = ref.read(apiClientProvider);
    final result = await client.get<Map<String, dynamic>>(
      '/api/v1/delivery-partners/me',
      fromJson: (d) => d as Map<String, dynamic>,
    );

    if (!mounted) return;
    result.when(
      success: (Map<String, dynamic> data) {
        final rider = RiderData.fromJson(data);
        if (!rider.exists) {
          context.go('/name');
        } else if (rider.needsKyc) {
          context.go('/kyc');
        } else if (rider.isRejected) {
          context.go('/kyc');
        } else if (rider.isPending) {
          context.go('/under-review');
        } else {
          context.go('/home');
        }
      },
      failure: (_) => context.go('/phone'),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const BrandSplash(wordmark: 'Paasel Rider');
}
