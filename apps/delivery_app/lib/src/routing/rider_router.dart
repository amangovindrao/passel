import 'package:delivery_app/src/features/home/active_delivery_screen.dart';
import 'package:delivery_app/src/features/home/home_screen.dart';
import 'package:delivery_app/src/features/onboarding/kyc_screen.dart';
import 'package:delivery_app/src/features/onboarding/name_entry_screen.dart';
import 'package:delivery_app/src/features/onboarding/otp_screen.dart';
import 'package:delivery_app/src/features/onboarding/phone_entry_screen.dart';
import 'package:delivery_app/src/features/onboarding/splash_screen.dart';
import 'package:delivery_app/src/features/onboarding/under_review_screen.dart';
import 'package:go_router/go_router.dart';

final riderRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const RiderSplashScreen()),
    GoRoute(path: '/phone', builder: (_, __) => const RiderPhoneScreen()),
    GoRoute(
      path: '/otp',
      builder: (_, state) =>
          RiderOtpScreen(phone: state.uri.queryParameters['phone'] ?? ''),
    ),
    GoRoute(path: '/name', builder: (_, __) => const RiderNameScreen()),
    GoRoute(path: '/kyc', builder: (_, __) => const RiderKycScreen()),
    GoRoute(
      path: '/under-review',
      builder: (_, __) => const UnderReviewScreen(),
    ),
    GoRoute(path: '/home', builder: (_, __) => const RiderHomeScreen()),
    GoRoute(
      path: '/active-delivery',
      builder: (_, __) => const ActiveDeliveryScreen(),
    ),
  ],
);
