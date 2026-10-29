import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/common.dart';

const _credentialEnvelopeType = 'sports_store.acceptance_credentials.v1';
const _credentialKeys = <String>[
  'CATALOG_TEST_EMAIL',
  'CATALOG_TEST_PASSWORD',
  'CATALOG_TEST_SECONDARY_EMAIL',
  'CATALOG_TEST_SECONDARY_PASSWORD',
];

Future<void> main() async {
  FlutterDriver? driver;
  var passed = false;
  try {
    final credentials = _readRuntimeCredentials();
    if (credentials != null) {
      final connectedDriver = await FlutterDriver.connect(
        printCommunication: false,
        logCommunicationToFile: false,
        timeout: const Duration(minutes: 2),
      );
      driver = connectedDriver;

      final envelope = jsonEncode(<String, dynamic>{
        'type': _credentialEnvelopeType,
        'version': 1,
        'credentials': credentials,
      });
      var handoffAccepted = false;
      try {
        final handoffResult = await connectedDriver.requestData(
          envelope,
          timeout: const Duration(minutes: 2),
        );
        handoffAccepted = _isAccepted(handoffResult);
      } finally {
        credentials.clear();
      }

      if (handoffAccepted) {
        final resultJson = await connectedDriver.requestData(
          null,
          timeout: const Duration(minutes: 20),
        );
        final response = Response.fromJson(resultJson);
        passed = response.allTestsPassed;
      }
    }
  } catch (_) {
    passed = false;
  } finally {
    try {
      await driver?.close();
    } catch (_) {
      passed = false;
    }
  }

  stdout.writeln(
    passed
        ? 'Nghiệm thu danh mục và giỏ hàng đã đạt.'
        : 'Nghiệm thu danh mục và giỏ hàng chưa đạt.',
  );
  exitCode = passed ? 0 : 1;
}

Map<String, String>? _readRuntimeCredentials() {
  final credentials = <String, String>{};
  for (final key in _credentialKeys) {
    final value = Platform.environment[key];
    if (value == null || value.isEmpty) return null;
    credentials[key] = value;
  }
  return credentials;
}

bool _isAccepted(String source) {
  try {
    final decoded = jsonDecode(source);
    return decoded is Map && decoded['status'] == 'accepted';
  } catch (_) {
    return false;
  }
}
