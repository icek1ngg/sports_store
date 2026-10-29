import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'mh08_preview_app.dart';

/// Explicit debug entrypoint. The production main never imports preview code.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview chỉ được chạy trong debug mode.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Mh08PreviewApp(
      showControls: !bool.fromEnvironment('MH07_HIDE_CONTROLS'),
    ),
  );
}
