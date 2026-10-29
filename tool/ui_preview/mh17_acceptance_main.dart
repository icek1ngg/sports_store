import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'preview_app.dart';

/// Debug-only entrypoint reusing the existing labelled, noncanonical fixtures.
void main() {
  if (!kDebugMode) {
    throw UnsupportedError('UI preview chỉ được chạy trong debug mode.');
  }
  runApp(const UiPreviewApp());
}
