import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/config/auth_startup_options.dart';

void main() {
  test('startup auth does not restore sessions from device storage', () {
    expect(startupAuthClientOptions.persistSession, isFalse);
  });
}
