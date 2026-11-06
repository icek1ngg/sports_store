import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One uncertain outcome at a time. Server locks remain authoritative.
final outboundResultGateProvider =
    NotifierProvider.family<OutboundResultGate, Object?, String>(
      OutboundResultGate.new,
    );

class OutboundResultGate extends Notifier<Object?> {
  OutboundResultGate(this.taskId);
  final String taskId;
  @override
  Object? build() => null;
  bool acquire(Object owner) {
    if (state != null && !identical(state, owner)) return false;
    state = owner;
    return true;
  }

  void release(Object owner) {
    if (!ref.mounted) return;
    if (identical(state, owner)) state = null;
  }
}
