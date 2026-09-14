import 'package:core/core.dart';
import 'package:customer_app/src/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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
  }, appRunner: () => runApp(const ProviderScope(child: PaaselApp())));
});

class PaaselApp extends StatelessWidget {
  const PaaselApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Passel',
      theme: PaaselTheme.light,
      darkTheme: PaaselTheme.dark,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
