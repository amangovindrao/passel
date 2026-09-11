/// Centralized environment configuration injected via --dart-define.
///
/// Fails fast with a clear error message if any required variable is missing.
class EnvConfig {
  EnvConfig._();

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static const String flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  /// True when crash reporting is configured. An empty DSN disables Sentry's
  /// SDK rather than failing, so this is informational, not a gate.
  static bool get hasSentry => sentryDsn.isNotEmpty;

  /// True when the Maps SDK has a key. Without one, map tiles render blank and
  /// every other feature is unaffected.
  static bool get hasMaps => googleMapsApiKey.isNotEmpty;

  /// Validates that the variables the app genuinely cannot start without are
  /// set. Throws [StateError] if any are missing.
  ///
  /// Only these three are required, and each because the app is not merely
  /// degraded without it but unusable: no API means every screen is an error
  /// state, and no Supabase URL or key means nobody can even log in.
  ///
  /// SENTRY_DSN and GOOGLE_MAPS_API_KEY are deliberately *not* required. They
  /// used to be, and the effect was worse than the problem: this runs before
  /// `runApp` in every app, so a build with no Sentry project — which is every
  /// local and CI build — threw here and the user got a white screen with no
  /// message anywhere on the device. A missing observability key must never be
  /// able to stop the app from starting. Sentry disables itself on an empty DSN
  /// and an absent Maps key costs one blank tile; check [hasSentry] and
  /// [hasMaps] if a caller needs to know.
  static void validate() {
    final missing = <String>[];

    if (apiBaseUrl.isEmpty) missing.add('API_BASE_URL');
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required --dart-define variables: ${missing.join(', ')}.\n'
        'Please provide them via --dart-define or your IDE launch config.',
      );
    }
  }
}
