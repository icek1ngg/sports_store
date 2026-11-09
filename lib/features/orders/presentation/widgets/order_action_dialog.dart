import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:uuid/uuid.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/presentation_failure_message.dart';
import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/epoch_cache.dart';
import '../../../../core/state/session_scope.dart';
import '../../../../shared/widgets/feature_access_gate.dart';
import '../../domain/models/model_validators.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/order_command.dart';
import '../view_models/order_providers.dart';

/// Existing confirmation UI, backed by durable same-key command recovery.
class OrderActionDialog extends ConsumerStatefulWidget {
  const OrderActionDialog({
    required this.orderId,
    required this.operation,
    required this.isStillAllowed,
    required this.submittedScope,
    this.sourceCache,
    this.sourceResourcePrefix = 'orders/',
    this.onRefreshDecision,
    this.decisionChanges,
    this.decisionUnchanged,
    super.key,
  });
  final String orderId;
  final OrderOperation operation;
  final bool Function() isStillAllowed;
  final SessionScope submittedScope;

  /// Detail sheets can own a session-bound cache below the root Navigator.
  /// Observe the decision's cache without reparenting a live modal scope.
  final EpochCache? sourceCache;
  final String sourceResourcePrefix;
  final Future<void> Function()? onRefreshDecision;
  final ProviderListenable<Object?>? decisionChanges;

  /// Null means a read is still pending; it is not a server conflict.
  final bool? Function()? decisionUnchanged;

  @override
  ConsumerState<OrderActionDialog> createState() => _OrderActionDialogState();
}

class _OrderActionDialogState extends ConsumerState<OrderActionDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final SessionScope _submittedScope;
  AppFailure? _failure;
  bool _sourceInvalidated = false;
  bool _decisionPending = false;
  bool _busy = false;
  StableOrderCommand? _command;
  void Function()? _cancelPrivateData;
  ProviderSubscription<Object?>? _decisionSubscription;

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
    if (widget.decisionChanges != null) {
      _decisionSubscription = ref.listenManual(widget.decisionChanges!, (_, _) {
        final unchanged = widget.decisionUnchanged?.call();
        if (!mounted || _busy) return;
        scheduleMicrotask(() {
          if (!mounted || _busy) return;
          setState(() {
            _decisionPending = unchanged == null;
            if (unchanged == null) return;
            _sourceInvalidated = !unchanged;
            if (!unchanged) {
              _failure = const AppFailure(code: AppFailure.stateChanged);
            } else if (_failure?.code == AppFailure.stateChanged) {
              _failure = null;
            }
          });
        });
      });
    }
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
      } else if (mounted &&
          resource.startsWith(widget.sourceResourcePrefix) &&
          !_busy &&
          widget.decisionChanges == null) {
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
    _decisionSubscription?.close();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final scope = ref.read(featureSessionScopeProvider);
    final authorized =
        scope == _submittedScope &&
        _roles.contains(scope.role) &&
        ref.read(epochCacheProvider).canRead;
    if (!authorized ||
        (_command == null &&
            (_sourceInvalidated || !widget.isStillAllowed()))) {
      setState(
        () => _failure = AppFailure(
          code: !authorized
              ? AppFailure.forbiddenOrUnavailable
              : AppFailure.stateChanged,
        ),
      );
      return;
    }
    final controller = ref.read(orderCommandControllerProvider);
    if (controller == null) {
      setState(
        () => _failure = const AppFailure(
          code: AppFailure.externalDependencyUnavailable,
        ),
      );
      return;
    }
    _command ??= StableOrderCommand(
      orderId: widget.orderId,
      requestId: const Uuid().v4(),
      operation: widget.operation,
      reason: _requiresReason ? _reason.text : null,
    );
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      if (!widget.isStillAllowed()) {
        // A revoked capability permits lookup of an already dispatched intent,
        // never another business submission based on its historical snapshot.
        final result = await controller.resolve(_command!);
        if (result.isFailed) {
          _command = null;
          throw result.failure!;
        }
        if (!result.isCommitted) {
          throw const AppFailure(
            code: AppFailure.outcomeUnknownCode,
            outcomeUnknown: true,
          );
        }
      } else {
        await controller.execute(_command!);
      }
      if (!mounted ||
          ref.read(featureSessionScopeProvider) != _submittedScope) {
        return;
      }
      ref.read(epochCacheProvider).invalidatePrefix('orders/');
      ref.read(epochCacheProvider).invalidatePrefix('notifications/');
      ref.invalidate(orderListFoundationProvider);
      ref.invalidate(orderDetailsFoundationProvider);
      Navigator.of(context).pop();
    } catch (error) {
      if (error is AppFailure &&
          (error.code == AppFailure.stateChanged ||
              error.code == AppFailure.cancellationNotAllowed)) {
        final command = _command;
        if (command != null) {
          try {
            final result = await controller.resolve(command);
            if (result.isFailed) _command = null;
          } catch (_) {
            // Keep the original key until lookup proves a final outcome.
          }
        }
        await widget.onRefreshDecision?.call();
      }
      if (!mounted ||
          ref.read(featureSessionScopeProvider) != _submittedScope) {
        return;
      }
      setState(
        () => _failure = error is AppFailure
            ? error
            : const AppFailure(
                code: AppFailure.outcomeUnknownCode,
                outcomeUnknown: true,
                retryable: true,
              ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  enabled: !_busy && _command == null,
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
          if (widget.onRefreshDecision != null && _sourceInvalidated && !_busy)
            TextButton(
              onPressed: () async {
                await widget.onRefreshDecision!();
                if (mounted &&
                    ref.read(featureSessionScopeProvider) == _submittedScope) {
                  setState(() {
                    _sourceInvalidated = !widget.isStillAllowed();
                    _failure = _sourceInvalidated
                        ? const AppFailure(code: AppFailure.stateChanged)
                        : null;
                  });
                }
              },
              child: const Text('Làm mới quyền thao tác'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          FilledButton(
            key: const ValueKey('order-action-submit'),
            onPressed:
                !_busy &&
                    !_decisionPending &&
                    scope == _submittedScope &&
                    widget.operation.isClientOperation &&
                    ref.read(epochCacheProvider).canRead &&
                    (_command != null ||
                        (!_sourceInvalidated && widget.isStillAllowed()))
                ? _submit
                : null,
            child: Text(
              _busy
                  ? 'Đang xử lý…'
                  : _command != null && !widget.isStillAllowed()
                  ? 'Kiểm tra kết quả'
                  : 'Tiếp tục',
            ),
          ),
        ],
      ),
    );
  }
}
