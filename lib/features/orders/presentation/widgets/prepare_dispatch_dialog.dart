import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/state/foundation_providers.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/repositories/manager_dispatch_repository.dart';
import '../view_models/manager_dispatch_providers.dart';

enum DispatchDialogOutcome { unchanged, assigned, unresolved }

class PrepareDispatchDialog extends ConsumerStatefulWidget {
  const PrepareDispatchDialog({
    required this.orderId,
    required this.scope,
    required this.isStillAllowed,
    super.key,
  });
  final String orderId;
  final SessionScope scope;
  final bool Function() isStillAllowed;
  @override
  ConsumerState<PrepareDispatchDialog> createState() =>
      _PrepareDispatchDialogState();
}

class _PrepareDispatchDialogState extends ConsumerState<PrepareDispatchDialog> {
  late final String _requestId;
  late final PendingDispatchStore _pendingStore;
  List<DispatchShipper>? _shippers;
  String? _shipperId;
  String? _error;
  bool _prepared = false, _busy = false, _loading = true, _attempted = false;
  bool get _authorized =>
      ref.read(featureSessionScopeProvider) == widget.scope &&
      widget.scope.role == 'manager';
  @override
  void initState() {
    super.initState();
    _pendingStore = ref.read(pendingDispatchStoreProvider);
    final pending = _pendingStore.forOrder(widget.orderId);
    _requestId = pending?.requestId ?? const Uuid().v4();
    _shipperId = pending?.shipperId;
    _prepared = pending != null;
    _attempted = pending != null;
    _load();
  }

  Future<void> _load() async {
    if (!_authorized) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shippers = await ref
          .read(managerDispatchRepositoryProvider)
          .loadShippers();
      if (!mounted || !_authorized) return;
      setState(() => _shippers = shippers);
    } catch (_) {
      if (mounted && _authorized) {
        setState(
          () => _error = 'Không tải được danh sách shipper. Vui lòng thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_busy ||
        !_prepared ||
        _shipperId == null ||
        !_authorized ||
        !widget.isStillAllowed()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _attempted = true;
    });
    _pendingStore.remember(
      widget.orderId,
      PendingDispatch(_requestId, _shipperId!),
    );
    try {
      await ref
          .read(managerDispatchRepositoryProvider)
          .prepareAndAssign(
            orderId: widget.orderId,
            shipperId: _shipperId!,
            requestId: _requestId,
          );
      if (!mounted || !_authorized) return;
      _pendingStore.clear(widget.orderId);
      Navigator.of(context).pop(DispatchDialogOutcome.assigned);
    } catch (e) {
      if (e is DispatchFailure && !e.ambiguous) {
        _pendingStore.clear(widget.orderId);
      }
      if (!mounted || !_authorized) return;
      setState(
        () => _error = e is DispatchFailure ? e.message : 'Chưa rõ kết quả phân công. Vui lòng tải lại đơn trước khi thử lại.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid =
        ref.watch(featureSessionScopeProvider) == widget.scope &&
        widget.scope.role == 'manager';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Chuẩn bị hàng và phân công'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!valid)
                  const Text(
                    'Phiên làm việc đã thay đổi. Đóng hộp thoại và tải lại đơn.',
                  )
                else ...[
                  const Text(
                    'Quản lý kiểm đúng sản phẩm, số lượng và đóng gói trước khi bàn giao cho shipper.',
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_shippers != null &&
                      _shippers!.isEmpty &&
                      _shipperId == null)
                    const Text('Chưa có tài khoản shipper để phân công.')
                  else if (_shippers != null)
                    DropdownButtonFormField<String>(
                      initialValue: _shipperId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Shipper nhận hàng',
                      ),
                      items: [
                        if (_shipperId != null &&
                            !_shippers!.any((s) => s.id == _shipperId))
                          DropdownMenuItem(
                            value: _shipperId,
                            child: const Text(
                              'Shipper đã chọn (cần kiểm tra lại)',
                            ),
                          ),
                        for (final s in _shippers!)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy || _attempted
                          ? null
                          : (v) => setState(() => _shipperId = v),
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tôi đã kiểm đủ hàng và đóng gói xong'),
                    value: _prepared,
                    onChanged: _busy || _attempted
                        ? null
                        : (v) => setState(() => _prepared = v == true),
                  ),
                  const Text(
                    'Xác nhận thành công sẽ chuyển đơn sang Chờ lấy hàng. Shipper được chọn mới có thể nhận và bắt đầu giao.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_shippers == null && !_loading)
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tải lại shipper'),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pop(
                    _pendingStore.forOrder(widget.orderId) == null
                        ? DispatchDialogOutcome.unchanged
                        : DispatchDialogOutcome.unresolved,
                  ),
            child: const Text('Đóng'),
          ),
          FilledButton(
            onPressed:
                valid &&
                    !_busy &&
                    !_loading &&
                    _prepared &&
                    _shipperId != null &&
                    widget.isStillAllowed()
                ? _submit
                : null,
            child: Text(
              _busy
                  ? 'Đang phân công…'
                  : _attempted
                  ? 'Thử lại cùng yêu cầu'
                  : 'Xác nhận bàn giao',
            ),
          ),
        ],
      ),
    );
  }
}
