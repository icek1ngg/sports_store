import 'dart:convert';

import 'package:flutter/services.dart';

import 'supabase_config.dart';

/// Explicit build settings replace the entire default configuration.
/// Invalid or partial overrides never fall back to a different project.
Future<SupabaseConfig> loadSupabaseConfig({
  AssetBundle? bundle,
  SupabaseConfig? environment,
  bool? hasEnvironmentOverride,
}) async {
  final overridden =
      hasEnvironmentOverride ??
      (const bool.hasEnvironment('SUPABASE_URL') ||
          const bool.hasEnvironment('SUPABASE_PUBLISHABLE_KEY'));
  if (overridden) {
    final config = environment ?? SupabaseConfig.fromEnvironment();
    config.validate();
    return config;
  }

  final Object? values;
  try {
    values = jsonDecode(
      await (bundle ?? rootBundle).loadString('config/supabase.json'),
    );
  } on FormatException {
    throw const FormatException('Invalid Supabase configuration JSON.');
  }
  if (values is! Map<String, dynamic> ||
      values['SUPABASE_URL'] is! String ||
      values['SUPABASE_PUBLISHABLE_KEY'] is! String) {
    throw const FormatException('Missing Supabase configuration fields.');
  }
  final config = SupabaseConfig(
    url: values['SUPABASE_URL'] as String,
    publishableKey: values['SUPABASE_PUBLISHABLE_KEY'] as String,
  );
  config.validate();
  return config;
}
