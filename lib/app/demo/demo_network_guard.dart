import 'dart:io';

/// Defense in depth for this entrypoint only: even an accidental HTTP-backed
/// dependency cannot send a request. Production main never installs this guard.
class DemoNetworkGuard extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const DemoNetworkDisabled();
}

class DemoNetworkDisabled implements Exception {
  const DemoNetworkDisabled();
  @override
  String toString() => 'Demo local: kết nối mạng đã bị khóa.';
}
