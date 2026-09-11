import 'package:customer_app/src/features/cart/cart_screen.dart';
import 'package:customer_app/src/features/checkout/checkout_screen.dart';
import 'package:customer_app/src/features/checkout/order_confirmation_screen.dart';
import 'package:customer_app/src/features/discovery/home_screen.dart';
import 'package:customer_app/src/features/onboarding/location_setup_screen.dart';
import 'package:customer_app/src/features/onboarding/name_entry_screen.dart';
import 'package:customer_app/src/features/onboarding/otp_screen.dart';
import 'package:customer_app/src/features/onboarding/phone_entry_screen.dart';
import 'package:customer_app/src/features/onboarding/splash_screen.dart';
import 'package:customer_app/src/features/orders/order_detail_screen.dart';
import 'package:customer_app/src/features/orders/order_history_screen.dart';
import 'package:customer_app/src/features/shop_detail/shop_detail_screen.dart';
import 'package:customer_app/src/features/tracking/live_tracking_screen.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/phone', builder: (_, __) => const PhoneEntryScreen()),
    GoRoute(
      path: '/otp',
      builder: (_, state) =>
          OtpScreen(phone: state.uri.queryParameters['phone'] ?? ''),
    ),
    GoRoute(path: '/name', builder: (_, __) => const NameEntryScreen()),
    GoRoute(
      path: '/location-setup',
      builder: (_, __) => const LocationSetupScreen(),
    ),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/shop/:id',
      builder: (_, state) =>
          ShopDetailScreen(shopId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/cart', builder: (_, __) => const CartScreen()),
    GoRoute(path: '/checkout', builder: (_, __) => const CheckoutScreen()),
    GoRoute(
      path: '/order-confirmation/:id',
      builder: (_, state) =>
          OrderConfirmationScreen(orderId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/orders', builder: (_, __) => const OrderHistoryScreen()),
    GoRoute(
      path: '/order-detail/:id',
      builder: (_, state) =>
          OrderDetailScreen(orderId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/tracking/:id',
      builder: (_, state) =>
          LiveTrackingScreen(orderId: state.pathParameters['id']!),
    ),
  ],
);
