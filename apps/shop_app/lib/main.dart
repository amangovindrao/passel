import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shop_app/src/routing/shop_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

void main() => bootstrap(() async {
  EnvConfig.validate();

  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  await SentryFlutter.init((options) {
    options
      ..dsn = EnvConfig.sentryDsn
      ..environment = EnvConfig.flavor;
  }, appRunner: () => runApp(const ProviderScope(child: PaaselShopApp())));
});

class PaaselShopApp extends StatelessWidget {
  const PaaselShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Paasel Shop',
      theme: PaaselTheme.light,
      darkTheme: PaaselTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: shopRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
