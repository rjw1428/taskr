import 'package:flutter/foundation.dart';

/// Build-time configuration. Values come from `--dart-define-from-file=.env`
/// (see README) and are compiled in as constants, so nothing is read from an
/// asset at runtime and no config file ships in the web bundle.
///
/// Only *public* identifiers belong here: OAuth client IDs and a search-only
/// Algolia key. Anything secret (Gemini, parking) lives behind a Cloud
/// Function or is exchanged for a Firebase ID token.
class Env {
  Env._();

  /// Test seam: when set, values are read from here instead of the compiled
  /// constants. Cleared by the test harness between tests.
  @visibleForTesting
  static Map<String, String>? overrides;

  static String _get(String key, String compiled) => overrides?[key] ?? compiled;

  static String get webClientId => _get('WEB_CLIENT_ID', const String.fromEnvironment('WEB_CLIENT_ID'));
  static String get calendarWebClientId =>
      _get('CALENDAR_WEB_CLIENT_ID', const String.fromEnvironment('CALENDAR_WEB_CLIENT_ID'));
  static String get algoliaAppId => _get('ALGOLIA_APP_ID', const String.fromEnvironment('ALGOLIA_APP_ID'));
  static String get algoliaSearchKey =>
      _get('ALGOLIA_SEARCH_KEY', const String.fromEnvironment('ALGOLIA_SEARCH_KEY'));
}
