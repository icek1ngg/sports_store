import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadRetryPolicy {
  const ReadRetryPolicy({
    this.backoffs = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ],
    this.wait = Future<void>.delayed,
  });
  final List<Duration> backoffs;
  final Future<void> Function(Duration) wait;
}

final readRetryPolicyProvider = Provider<ReadRetryPolicy>(
  (ref) => const ReadRetryPolicy(),
);
