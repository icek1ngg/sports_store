import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth configuration for a new app process.
///
/// A session is kept in memory after a successful sign-in, but it is not
/// restored from device storage when the process starts again. This keeps the
/// entry flow on the login screen for every fresh app launch.
const startupAuthClientOptions = FlutterAuthClientOptions(
  persistSession: false,
);
