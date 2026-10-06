import 'dart:convert';

/// Client-safe Supabase connection settings.
///
/// Values are read from compile-time environment variables by
/// [SupabaseConfig.fromEnvironment]. The publishable key may be included in
/// a client build; service-role and secret keys are rejected.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  factory SupabaseConfig.fromEnvironment() {
    return const SupabaseConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String url;
  final String publishableKey;

  /// Validates the client configuration without exposing either credential.
  void validate() {
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      throw ArgumentError('Supabase URL is required.');
    }
    if (normalizedUrl != url) {
      throw ArgumentError(
        'Supabase URL must not contain surrounding whitespace.',
      );
    }

    final parsedUrl = Uri.tryParse(normalizedUrl);
    if (parsedUrl == null ||
        parsedUrl.scheme.toLowerCase() != 'https' ||
        parsedUrl.host.isEmpty) {
      throw ArgumentError('Supabase URL must be a valid HTTPS URL.');
    }

    final normalizedKey = publishableKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('Supabase publishable key is required.');
    }
    if (normalizedKey != publishableKey) {
      throw ArgumentError(
        'Supabase publishable key must not contain surrounding whitespace.',
      );
    }

    final lowerCaseKey = normalizedKey.toLowerCase();
    if (lowerCaseKey.contains('service_role') ||
        lowerCaseKey.contains('sb_secret')) {
      throw ArgumentError('Supabase key must be a publishable or anon key.');
    }

    if (_isPublishableKey(normalizedKey) || _isAnonJwt(normalizedKey)) {
      return;
    }

    throw ArgumentError('Supabase key must be a publishable or anon key.');
  }

  static const _publishablePrefix = 'sb_publishable_';

  static bool _isPublishableKey(String key) {
    return key.startsWith(_publishablePrefix) &&
        key.length > _publishablePrefix.length;
  }

  static bool _isAnonJwt(String key) {
    final segments = key.split('.');
    if (segments.length != 3 || segments.any((segment) => segment.isEmpty)) {
      return false;
    }

    try {
      final header = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[0]))),
      );
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );

      return header is Map<String, dynamic> &&
          payload is Map<String, dynamic> &&
          payload['role'] == 'anon';
    } on FormatException {
      return false;
    } on JsonUnsupportedObjectError {
      return false;
    }
  }
}
