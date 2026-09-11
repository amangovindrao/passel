import 'package:go_router/go_router.dart';

import 'package:shop_app/src/features/catalog/catalog_screen.dart';
import 'package:shop_app/src/features/catalog/product_form_screen.dart';
import 'package:shop_app/src/features/dashboard/dashboard_screen.dart';
import 'package:shop_app/src/features/onboarding/kyc_screen.dart';
import 'package:shop_app/src/features/onboarding/name_entry_screen.dart';
import 'package:shop_app/src/features/onboarding/otp_screen.dart';
import 'package:shop_app/src/features/onboarding/pending_screen.dart';
import 'package:shop_app/src/features/onboarding/phone_entry_screen.dart';
import 'package:shop_app/src/features/onboarding/shop_details_screen.dart';
import 'package:shop_app/src/features/onboarding/splash_screen.dart';
import 'package:shop_app/src/features/orders/order_detail_screen.dart';
import 'package:shop_app/src/features/orders/orders_screen.dart';
import 'package:shop_app/src/features/subscription/subscription_screen.dart';

final shopRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const ShopSplashScreen()),
    GoRoute(path: '/phone', builder: (_, __) => const ShopPhoneScreen()),
    GoRoute(
      path: '/otp',
      builder: (_, state) =>
          ShopOtpScreen(phone: state.uri.queryParameters['phone'] ?? ''),
    ),
    GoRoute(path: '/name', builder: (_, __) => const ShopNameScreen()),
    GoRoute(path: '/kyc', builder: (_, __) => const KycScreen()),
    GoRoute(
      path: '/shop-details',
      builder: (_, __) => const ShopDetailsScreen(),
    ),
    GoRoute(path: '/pending', builder: (_, __) => const PendingScreen()),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(
      path: '/catalog/:shopId',
      builder: (_, state) =>
          CatalogScreen(shopId: state.pathParameters['shopId']!),
    ),
    GoRoute(
      path: '/product/new/:shopId',
      builder: (_, state) =>
          ProductFormScreen(shopId: state.pathParameters['shopId']!),
    ),
    GoRoute(
      path: '/orders/:shopId',
      builder: (_, state) =>
          OrdersScreen(shopId: state.pathParameters['shopId']!),
    ),
    // Carries the shop id as well as the order id: every order endpoint is
    // scoped to a shop, and reaching for it from a provider here would mean a
    // second request before this screen could render anything.
    GoRoute(
      path: '/order/:shopId/:orderId',
      builder: (_, state) => ShopOrderDetailScreen(
        shopId: state.pathParameters['shopId']!,
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: '/subscription',
      builder: (_, __) => const SubscriptionScreen(),
    ),
  ],
);
