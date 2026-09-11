import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

/// Splash: route-guards based on auth + kyc + shop status.
class ShopSplashScreen extends ConsumerStatefulWidget {
  const ShopSplashScreen({super.key});

  @override
  ConsumerState<ShopSplashScreen> createState() => _ShopSplashScreenState();
}

class _ShopSplashScreenState extends ConsumerState<ShopSplashScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, not during initState — reading the session is
    // synchronous, so on a fresh install the next statement navigates, and
    // navigating before the tree is mounted throws inside an unawaited Future
    // where nobody sees it. The symptom is a splash that never moves.
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    if (!mounted) return;
    final session = ref.read(supabaseProvider).auth.currentSession;
    if (session == null) {
      context.go('/phone');
      return;
    }

    // Check shop status
    final client = ref.read(apiClientProvider);
    final result = await client.get<Map<String, dynamic>>(
      '/api/v1/shops/mine',
      fromJson: (d) => d as Map<String, dynamic>,
    );

    if (!mounted) return;
    result.when(
      success: (Map<String, dynamic> data) {
        final shopData = ShopData.fromJson(data);
        if (!shopData.exists) {
          final kyc = shopData.kycStatus ?? 'none';
          if (kyc == 'none') {
            context.go('/name');
          } else if (kyc == 'pending') {
            context.go('/pending');
          } else if (kyc == 'rejected') {
            context.go('/kyc');
          } else {
            context.go('/shop-details');
          }
        } else if (!shopData.isApproved) {
          context.go('/pending');
        } else {
          context.go('/dashboard');
        }
      },
      failure: (_) => context.go('/phone'),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const BrandSplash(wordmark: 'Paasel Shop');
}
