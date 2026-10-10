import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../domain/models/model_validators.dart';
import '../../domain/models/order_status.dart';

/// Phase 2 dialog/validation only. Command persistence/transport is a later gate.
/// No request key is invented and no repository mutation is sent here.
class OrderActionDialog extends ConsumerStatefulWidget {
  const OrderActionDialog({
    required this.orderId,
    required this.operation,
    required this.isStillAllowed,
    required this.submittedScope,
    this.sourceCache,
    super.key,
  });
  final String orderId;
  final OrderOperation operation;
  final bool Function() isStillAllowed;
  final SessionScope submittedScope;

  /// Detail sheets can own a session-bound cache below the root Navigator.
  /// Observe the decision's cache without reparenting a live modal scope.
  final EpochCache? sourceCache;

  @override
  ConsumerState<OrderActionDialog> createState() => _OrderActionDialogState();
}

class _OrderActionDialogState extends ConsumerState<OrderActionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final SessionScope _submittedScope;
  AppFailure? _failure;
  bool _sourceInvalidated = false;
  void Function()? _cancelPrivateData;

  bool get _requiresReason =>
      widget.operation == OrderOperation.reject ||
      widget.operation == OrderOperation.managerCancel;
  Set<String> get _roles => widget.operation == OrderOperation.customerCancel
      ? const {'customer'}
      : const {'manager'};
  String get _title => switch (widget.operation) {
    OrderOperation.confirm => 'Xác nhận đơn hàng',
    OrderOperation.reject => 'Từ chối đơn hàng',
    OrderOperation.customerCancel ||
    OrderOperation.managerCancel => 'Hủy đơn hàng',
    OrderOperation.autoConfirm => 'Thao tác không khả dụng',
  };

  @override
  void initState() {
    super.initState();
    _submittedScope = widget.submittedScope;
    ref.listenManual(featureSessionScopeProvider, (_, next) {
      if (next != _submittedScope) {
        _reason.clear();
        _failure = null;
      }
    });
    final EpochCache cache =
        widget.sourceCache ?? ref.read<EpochCache>(epochCacheProvider);
    _cancelPrivateData = cache.listen((resource) {
      if (!cache.canRead && mounted) {
        _reason.clear();
        _failure = null;
      } else if (mounted && resource.startsWith('orders/')) {
        // The confirmation was opened from an older decision snapshot.
        // Reopen it from fresh data instead of owning another loader here.
        _sourceInvalidated = true;
        _failure = const AppFailure(code: AppFailure.stateChanged);
        scheduleMicrotask(() {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void dispose() {
    _cancelPrivateData?.call();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final scope = ref.read(featureSessionScopeProvider);
    final authorized =
        scope == _submittedScope &&
        _roles.contains(scope.role) &&
        ref.read(epochCacheProvider).canRead;
    setState(() {
      _failure = AppFailure(
        code: !authorized
            ? AppFailure.forbiddenOrUnavailable
            : _sourceInvalidated || !widget.isStillAllowed()
            ? AppFailure.stateChanged
            : AppFailure.externalDependencyUnavailable,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(featureSessionScopeProvider);
    if (scope != _submittedScope) {
      return AlertDialog(
        title: const Text('Không thể tiếp tục thao tác'),
        content: const Text(
          'Phiên đăng nhập đã thay đổi. Vui lòng mở lại đơn hàng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      );
    }
    return FeatureAccessGate(
      roles: _roles,
      child: AlertDialog(
        scrollable: true,
        title: Text(_title),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.orderId, softWrap: true),
              const SizedBox(height: 12),
              Text(
                widget.operation == OrderOperation.confirm
                    ? 'Xác nhận đơn để chuyển sang chuẩn bị hàng?'
                    : 'Thao tác sẽ giải phóng phần tồn đã giữ khi được hệ thống xác nhận.',
              ),
              if (_requiresReason) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('order-action-reason'),
                  controller: _reason,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Lý do',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final normalized = contractTrim(value ?? '');
                    if (normalized.isEmpty) {
                      return 'Vui lòng nhập lý do trước khi gửi.';
                    }
                    if (normalized.runes.length > 1000) {
                      return 'Lý do không vượt quá 1.000 ký tự.';
                    }
                    return null;
                  },
                ),
              ],
              if (_failure != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(failureMessage(_failure)),
                ),
              ],
            ],
          ),
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          FilledButton(
            key: const ValueKey('order-action-submit'),
            onPressed:
                scope == _submittedScope &&
                    widget.operation.isClientOperation &&
                    ref.read(epochCacheProvider).canRead &&
                    !_sourceInvalidated &&
                    widget.isStillAllowed()
                ? _submit
                : null,
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
  }
}
