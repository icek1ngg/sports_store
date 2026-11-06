import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/widgets/catalog_formatters.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../domain/models/checkout_failure.dart';
import '../../presentation/view_models/checkout_providers.dart';
import '../../presentation/view_models/checkout_state.dart';
import '../widgets/checkout_location_picker.dart';

/// MH16 — đặt hàng COD cho khách tại Hà Nội.
class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  double? _latitude;
  double? _longitude;
  String? _syncedPendingRequestId;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final checkout = ref.watch(checkoutProvider);
    return Scaffold(
      key: const ValueKey('checkout-page'),
      appBar: AppBar(
        title: const Text('Đặt hàng — Sports Store'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            icon: const Icon(Icons.refresh),
            onPressed: checkout.isLoading ? null : () => unawaited(_refresh()),
          ),
        ],
      ),
      body: checkout.isLoading
          ? const Center(
              key: ValueKey('checkout-loading'),
              child: CircularProgressIndicator(),
            )
          : checkout.hasError
          ? _buildLoadError(checkout.error)
          : _buildData(checkout.requireValue),
    );
  }

  Widget _buildLoadError(Object? error) {
    return ListView(
      key: const ValueKey('checkout-error'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),
        Icon(
          Icons.cloud_off_outlined,
          size: 52,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 14),
        Text(_messageFor(error), textAlign: TextAlign.center, softWrap: true),
        const SizedBox(height: 18),
        FilledButton.tonal(
          key: const ValueKey('checkout-retry'),
          onPressed: () => unawaited(_refresh()),
          child: const Text('Thử lại'),
        ),
      ],
    );
  }

  Widget _buildData(CheckoutState state) {
    _syncPending(state);
    if (state.isSuccess) return _buildSuccess(state);
    if (state.items.isEmpty && !state.hasPendingPlacement) return _buildEmpty();

    final locked =
        state.hasPendingPlacement || state.isSubmitting || state.isRecovering;
    final mapTilesEnabled = ref.watch(checkoutMapTilesEnabledProvider);
    return Form(
      child: ListView(
        key: const ValueKey('checkout-form'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 34),
        children: [
          if (state.failure != null || state.hasPendingPlacement) ...[
            _buildPendingNotice(state),
            const SizedBox(height: 12),
          ],
          _buildCartSnapshot(state),
          const SizedBox(height: 14),
          _buildRecipientForm(locked),
          const SizedBox(height: 14),
          _buildLocationSection(locked, showTiles: mapTilesEnabled),
          const SizedBox(height: 14),
          _buildPaymentSummary(state),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: KeyedSubtree(
              key: const ValueKey('submit'),
              child: FilledButton.icon(
                key: const ValueKey('checkout-submit'),
                onPressed: state.canSubmit ? _submit : null,
                icon: state.isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_outline),
                label: Text(
                  state.isSubmitting ? 'Đang xác nhận đơn…' : 'Đặt hàng COD',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Giá và tồn kho cuối cùng do máy chủ xác nhận khi đặt đơn.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildCartSnapshot(CheckoutState state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sản phẩm trong giỏ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final item in state.items) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${item.product?.name ?? 'Sản phẩm không còn khả dụng'} × ${item.quantity}',
                    softWrap: true,
                  ),
                  if (item.variant != null) Text(item.variant!.label),
                  const SizedBox(height: 6),
                  Text(
                    item.lineTotalVnd == null
                        ? '—'
                        : formatVnd(item.lineTotalVnd!),
                    textAlign: TextAlign.end,
                  ),
                ],
              ),
              if (item != state.items.last) const Divider(height: 20),
            ],
            if (state.hasUnavailableItems) ...[
              const SizedBox(height: 10),
              Text(
                'Có sản phẩm không còn khả dụng. Hãy quay lại giỏ hàng để điều chỉnh.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientForm(bool locked) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thông tin người nhận',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const ValueKey('name'),
              child: TextField(
                key: const ValueKey('checkout-name'),
                controller: _nameController,
                enabled: !locked,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Họ và tên người nhận',
                  hintText: 'Nguyễn Văn A',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const ValueKey('phone'),
              child: TextField(
                key: const ValueKey('checkout-phone'),
                controller: _phoneController,
                enabled: !locked,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: '09xxxxxxxx',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const ValueKey('address'),
              child: TextField(
                key: const ValueKey('checkout-address'),
                controller: _addressController,
                enabled: !locked,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ chi tiết',
                  hintText: 'Số nhà, đường, phường/xã, quận/huyện',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection(bool locked, {required bool showTiles}) {
    final selected = _latitude != null && _longitude != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vị trí giao hàng',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Bắt buộc ghim tọa độ để máy chủ kiểm tra vùng giao hàng.',
            ),
            const SizedBox(height: 12),
            CheckoutLocationPicker(
              key: const ValueKey('location'),
              buttonKey: const ValueKey('checkout-location'),
              enabled: !locked,
              showTiles: showTiles,
              initialLatitude: _latitude ?? 21.0285,
              initialLongitude: _longitude ?? 105.8542,
              onPicked: (value) => setState(() {
                _latitude = value.latitude;
                _longitude = value.longitude;
              }),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InputDecorator(
                    key: const ValueKey('latitude'),
                    decoration: const InputDecoration(
                      labelText: 'Vĩ độ',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      selected ? _latitude!.toStringAsFixed(6) : 'Chưa chọn',
                      softWrap: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    key: const ValueKey('longitude'),
                    decoration: const InputDecoration(
                      labelText: 'Kinh độ',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      selected ? _longitude!.toStringAsFixed(6) : 'Chưa chọn',
                      softWrap: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSummary(CheckoutState state) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _amountRow('Tạm tính', state.subtotalVnd, key: 'checkout-subtotal'),
            const SizedBox(height: 8),
            _amountRow(
              'Phí giao hàng',
              state.deliveryFeeVnd,
              key: 'checkout-delivery-fee',
            ),
            const Divider(height: 24),
            _amountRow(
              state.result == null ? 'Tổng COD dự kiến' : 'Tổng COD từ máy chủ',
              state.displayedTotalVnd,
              key: 'checkout-total',
              emphasized: true,
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Thanh toán khi nhận hàng (COD)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountRow(
    String label,
    int amount, {
    required String key,
    bool emphasized = false,
  }) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            formatVnd(amount),
            key: ValueKey(key),
            textAlign: TextAlign.end,
            style: style?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingNotice(CheckoutState state) {
    final failure = state.failure;
    final message = state.recoveryNotFound
        ? 'Chưa xác minh được đơn hàng. Hãy thử lại để kiểm tra hoặc tiếp tục yêu cầu đang chờ.'
        : failure?.userMessage ??
              'Đang xác minh đơn hàng. Thông tin được giữ nguyên để tránh đặt trùng.';
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, softWrap: true),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: KeyedSubtree(
                key: const ValueKey('retry'),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('checkout-retry'),
                  onPressed: state.isSubmitting
                      ? null
                      : state.hasPendingPlacement
                      ? () => unawaited(_retryPending())
                      : () => context.go('/customer/cart'),
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    state.hasPendingPlacement
                        ? 'Xác minh / thử lại cùng yêu cầu'
                        : 'Kiểm tra lại giỏ hàng',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      key: const ValueKey('checkout-empty'),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.shopping_bag_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          'Giỏ hàng đang trống',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Hãy quay lại Sports Store để chọn sản phẩm trước khi đặt hàng.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => context.go('/customer/products'),
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Xem sản phẩm'),
        ),
      ],
    );
  }

  Widget _buildSuccess(CheckoutState state) {
    final result = state.result!;
    return KeyedSubtree(
      key: const ValueKey('checkout-success'),
      child: ListView(
        key: const ValueKey('success'),
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 34),
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Đặt hàng thành công',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Sports Store đã ghi nhận đơn COD của bạn.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _receiptRow('Mã đơn hàng', result.order.id),
                  const SizedBox(height: 10),
                  _receiptRow(
                    'Trạng thái',
                    _orderStatusLabel(result.order.status),
                  ),
                  const SizedBox(height: 10),
                  _receiptRow('Tổng COD', formatVnd(result.totalCodVnd)),
                  const SizedBox(height: 10),
                  Text(
                    'Giá trên phiếu này là tổng tiền máy chủ đã xác nhận.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => context.go('/customer/products'),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Tiếp tục mua sắm'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/customer/cart'),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text('Quay lại giỏ hàng'),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, softWrap: true)),
      ],
    );
  }

  void _syncPending(CheckoutState state) {
    final pending = state.pendingRequest;
    if (pending == null || _syncedPendingRequestId == pending.requestId) return;
    _syncedPendingRequestId = pending.requestId;
    _nameController.text = pending.recipientName;
    _phoneController.text = pending.recipientPhone;
    _addressController.text = pending.addressDetail;
    _latitude = pending.latitude;
    _longitude = pending.longitude;
  }

  Future<void> _submit() async {
    final latitude = _latitude;
    final longitude = _longitude;
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _addressController.text.trim().isEmpty ||
        latitude == null ||
        longitude == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đủ thông tin và ghim vị trí giao hàng.'),
        ),
      );
      return;
    }
    await ref
        .read(checkoutProvider.notifier)
        .placeOrder(
          recipientName: _nameController.text,
          recipientPhone: _phoneController.text,
          addressDetail: _addressController.text,
          latitude: latitude,
          longitude: longitude,
        );
  }

  Future<void> _retryPending() async {
    try {
      await ref.read(checkoutProvider.notifier).retryPending();
    } catch (_) {
      // The provider owns the rendered failure state.
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(checkoutProvider.notifier).refresh();
    } catch (_) {
      // AsyncNotifier exposes the failure to this page.
    }
  }

  static String _messageFor(Object? error) {
    if (error is CheckoutFailure) return error.userMessage;
    return 'Không tải được thông tin đặt hàng. Vui lòng thử lại.';
  }
}

String _orderStatusLabel(OrderStatus status) => switch (status) {
  OrderStatus.pendingConfirmation => 'Chờ cửa hàng xác nhận',
  OrderStatus.preparing => 'Đang chuẩn bị hàng',
  OrderStatus.awaitingPickup => 'Chờ bàn giao cho nhân viên giao hàng',
  OrderStatus.delivering => 'Đang giao hàng',
  OrderStatus.awaitingRedelivery => 'Chờ giao lại',
  OrderStatus.awaitingStoreReturn => 'Chờ hàng giao thất bại về cửa hàng',
  OrderStatus.delivered => 'Đã giao hàng',
  OrderStatus.cancelled => 'Đã hủy',
  OrderStatus.rejected => 'Đã từ chối',
  OrderStatus.undeliverableReturned => 'Đã trả về cửa hàng',
};
