import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Splash: checks auth state and routes to appropriate screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState. Reading the session is
    // synchronous, so on a fresh install the very next statement is a
    // context.go — and navigating before the tree is mounted throws while
    // looking up the router. The throw lands in an unawaited Future and is
    // swallowed, which shows up as the splash never going anywhere.
    //
    // This costs one frame. The 800ms delay that used to sit here hid the
    // problem by yielding first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuthAndRoute());
  }

  Future<void> _checkAuthAndRoute() async {
    if (!mounted) return;
    try {
      await _decideRoute().timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          if (mounted) {
            context.go('/phone');
          }
        },
      );
    } on Object catch (e) {
      debugPrint('SplashScreen auth routing error: $e');
      if (mounted) {
        context.go('/phone');
      }
    }
  }

  Future<void> _decideRoute() async {
    if (!mounted) return;
    final session = ref.read(supabaseClientProvider).auth.currentSession;
    if (session == null) {
      context.go('/phone');
      return;
    }

    // Check profile
    final profileResult = await ref
        .read(customerRepositoryProvider)
        .getProfile();
    if (!mounted) return;

    CustomerProfile? profile;
    final isFailure = profileResult.when(
      success: (CustomerProfile p) {
        profile = p;
        return false;
      },
      failure: (AppError _) => true,
    );

    if (isFailure || profile == null) {
      context.go('/phone');
      return;
    }

    if (!profile!.exists) {
      context.go('/name');
      return;
    }

    // Check addresses
    final addressResult = await ref
        .read(addressRepositoryProvider)
        .listAddresses();
    if (!mounted) return;

    final addresses = addressResult.when(
      success: (List<SavedAddress> a) => a,
      failure: (AppError _) => <SavedAddress>[],
    );

    if (addresses.isEmpty) {
      context.go('/location-setup');
      return;
    }

    context.go('/home');
  }

  @override
  Widget build(BuildContext context) => const BrandSplash(wordmark: 'Passel');
}
