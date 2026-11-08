import 'dart:io';

import 'package:flutter/material.dart';

import 'app/demo/demo_network_guard.dart';
import 'app/dev/dev_app.dart';

/// Device-only full application. No Cloud configuration or SDK initialization.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = DemoNetworkGuard();
  runApp(const FullDevApp());
}
