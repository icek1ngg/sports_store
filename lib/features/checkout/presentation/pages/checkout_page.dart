import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/storefront_theme.dart';
import '../../../../core/utils/display_formatters.dart'
    show formatHanoiDateTime;
import '../../../catalog/domain/models/product_variant.dart';

import '../../../catalog/presentation/widgets/catalog_formatters.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../domain/models/checkout_failure.dart';
import '../../presentation/view_models/checkout_providers.dart';
import '../../presentation/view_models/checkout_state.dart';
import '../view_models/checkout_address_editor_draft.dart';
import '../widgets/checkout_address_section.dart';
import '../widgets/checkout_design_widgets.dart';

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
  CheckoutAddressEditorDraft? _addressEditorDraft;

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
    return StorefrontTheme(
      child: Builder(
        builder: (context) => Scaffold(
          key: const ValueKey('checkout-page'),
          appBar: AppBar(
            title: const Text(
              'THANH TOÁN',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                key: const ValueKey('checkout-refresh'),
                tooltip: 'Làm mới',
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: checkout.isLoading
                    ? null
                    : () => unawaited(_refresh()),
              ),
            ],
          ),
          body: checkout.isLoading
              ? const Center(
                  key: ValueKey('checkout-loading'),
                  child: CircularProgressIndicator(),
                )
              : checkout.hasError
              ? _buildLoadError(context, checkout.error)
              : _buildData(context, checkout.requireValue),
        ),
      ),
    );
  }

  Widget _buildLoadError(BuildContext context, Object? error) {
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

  Widget _buildData(BuildContext context, CheckoutState state) {
    _syncPending(state);
    if (state.isSuccess) return _buildSuccess(context, state);
    if (state.items.isEmpty && !state.hasPendingPlacement) {
      return _buildEmpty(context);
    }

    final locked =
        state.hasPendingPlacement || state.isSubmitting || state.isRecovering;
    final mapTilesEnabled = ref.watch(checkoutMapTilesEnabledProvider);
    return Form(
      key: const ValueKey('checkout-form'),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 732),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    const CheckoutBrandStrip(),
                    const SizedBox(height: 14),
                    if (state.failure != null || state.hasPendingPlacement) ...[
                      _buildPendingNotice(context, state),
                      const SizedBox(height: 12),
                    ],
                    _buildRecipientForm(context, locked),
                    const SizedBox(height: 14),
                    _buildLocationSection(
                      context,
                      locked,
                      showTiles: mapTilesEnabled,
                    ),
                    const SizedBox(height: 14),
                    _buildCartSnapshot(context, state),
                    const SizedBox(height: 14),
                    _buildPaymentSummary(context, state),
                    const SizedBox(height: 14),
                    const CheckoutCodCard(),
                    const SizedBox(height: 16),
                    Text(
                      'Giá và tồn kho cuối cùng do máy chủ xác nhận khi đặt đơn.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: SizedBox(
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_outline, size: 20),
                          label: Text(
                            state.isSubmitting
                                ? 'Đang xác nhận đơn…'
                                : 'Đặt hàng COD • ${formatVnd(state.displayedTotalVnd)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartSnapshot(BuildContext context, CheckoutState state) {
    return CheckoutSection(
      title: 'TÓM TẮT ĐƠN HÀNG',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in state.items) ...[
            CheckoutProductRow(
              name: item.product?.name ?? 'Sản phẩm không còn khả dụng',
              variantLabel:
                  item.variant?.label ?? 'Biến thể không còn khả dụng',
              quantity: item.quantity,
              imagePath: item.variant?.imagePaths.isNotEmpty == true
                  ? item.variant!.imagePaths.first
                  : item.product?.imagePath,
              amountVnd: item.lineTotalVnd,
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
    );
  }

  Widget _buildRecipientForm(BuildContext context, bool locked) {
    return CheckoutSection(
      title: 'THÔNG TIN NGƯỜI NHẬN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: const ValueKey('name'),
            child: TextField(
              key: const ValueKey('checkout-name'),
              controller: _nameController,
              enabled: !locked,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                'Họ và tên người nhận',
                'Nguyễn Văn A',
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
              decoration: _fieldDecoration('Số điện thoại', '09xxxxxxxx'),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildLocationSection(
    BuildContext context,
    bool locked, {
    required bool showTiles,
  }) {
    return CheckoutAddressSection(
      enabled: !locked,
      showTiles: showTiles,
      restoreKey: _syncedPendingRequestId,
      initialEditorDraft: _addressEditorDraft,
      onEditorChanged: (draft) => _addressEditorDraft = draft,
      initialAddress: _addressController.text,
      initialLatitude: _latitude,
      initialLongitude: _longitude,
      onChanged: (draft) {
        if (!mounted) return;
        setState(() {
          _addressController.text = draft.addressDetail;
          _latitude = draft.latitude;
          _longitude = draft.longitude;
        });
      },
    );
  }

  Widget _buildPaymentSummary(BuildContext context, CheckoutState state) {
    return CheckoutSection(
      child: Column(
        children: [
          _amountRow(
            context,
            'Tạm tính',
            state.result?.subtotalVnd ?? state.subtotalVnd,
            key: 'checkout-subtotal',
          ),
          const SizedBox(height: 8),
          _amountRow(
            context,
            'Phí giao hàng',
            state.result?.deliveryFeeVnd ?? state.deliveryFeeVnd,
            key: 'checkout-delivery-fee',
          ),
          const Divider(height: 24),
          _amountRow(
            context,
            state.result == null ? 'Tổng COD dự kiến' : 'Tổng COD từ máy chủ',
            state.displayedTotalVnd,
            key: 'checkout-total',
            emphasized: true,
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, String hint) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: StorefrontTheme.ink),
      ),
    );
  }

  Widget _amountRow(
    BuildContext context,
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

  Widget _buildPendingNotice(BuildContext context, CheckoutState state) {
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

  Widget _buildEmpty(BuildContext context) {
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

  Widget _buildSuccess(BuildContext context, CheckoutState state) {
    final result = state.result!;
    final order = result.order;
    return KeyedSubtree(
      key: const ValueKey('checkout-success'),
      child: ListView(
        key: const ValueKey('success'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: StorefrontTheme.cloud,
                      child: Icon(
                        Icons.check_rounded,
                        size: 36,
                        color: StorefrontTheme.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'STRIDE RUNNING CO.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(letterSpacing: 2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ĐẶT HÀNG THÀNH CÔNG!',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cảm ơn bạn đã mua sắm cùng STRIDE. Đơn COD đã được ghi nhận.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 22),
                  CheckoutSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'MÃ ĐƠN HÀNG',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SelectableText(
                                order.id,
                                key: const ValueKey('checkout-order-id'),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('checkout-copy-order-id'),
                              tooltip: 'Sao chép mã đơn hàng',
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: order.id),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Đã sao chép mã đơn hàng.'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            Chip(
                              avatar: const Icon(
                                Icons.circle,
                                color: StorefrontTheme.success,
                                size: 8,
                              ),
                              label: Text(
                                _orderStatusLabel(order.status),
                                key: const ValueKey('checkout-order-status'),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Đặt lúc ${formatHanoiDateTime(order.placedAt)} (Hà Nội)',
                          key: const ValueKey('checkout-placed-at'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 24),
                        for (final item in result.items) ...[
                          CheckoutProductRow(
                            name: item.productName,
                            variantLabel: item.variantLabel,
                            quantity: item.quantity,
                            amountVnd: item.lineTotalVnd,
                            imagePath: ProductVariant(
                              id: item.variantId,
                              productId: item.productId,
                              sku: '',
                              label: item.variantLabel,
                              attributes: item.attributes,
                              priceVnd: item.unitPriceVnd,
                              availableQuantity: 0,
                            ).imagePaths.firstOrNull,
                          ),
                          if (item != result.items.last)
                            const Divider(height: 20),
                        ],
                        const Divider(height: 24),
                        _receiptRow(context, 'Người nhận', order.recipientName),
                        const SizedBox(height: 10),
                        _receiptRow(
                          context,
                          'Điện thoại',
                          order.recipientPhone,
                        ),
                        const SizedBox(height: 10),
                        _receiptRow(
                          context,
                          'Địa chỉ nhận',
                          order.addressDetail,
                        ),
                        const SizedBox(height: 10),
                        _receiptRow(
                          context,
                          'Phương thức',
                          'Thanh toán khi nhận hàng (COD)',
                        ),
                        const Divider(height: 24),
                        _amountRow(
                          context,
                          'Tiền hàng',
                          result.subtotalVnd,
                          key: 'checkout-receipt-subtotal',
                        ),
                        const SizedBox(height: 8),
                        _amountRow(
                          context,
                          'Phí giao hàng',
                          result.deliveryFeeVnd,
                          key: 'checkout-receipt-fee',
                        ),
                        const Divider(height: 24),
                        _amountRow(
                          context,
                          'Tổng thanh toán',
                          result.totalCodVnd,
                          key: 'checkout-receipt-total',
                          emphasized: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    key: const ValueKey('checkout-view-orders'),
                    onPressed: () => context.go('/customer/orders'),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Xem đơn hàng'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const ValueKey('checkout-continue-shopping'),
                    onPressed: () => context.go('/customer/products'),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Tiếp tục mua sắm'),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    key: const ValueKey('checkout-back-cart'),
                    onPressed: () => context.go('/customer/cart'),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Quay lại giỏ hàng'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(BuildContext context, String label, String value) {
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
    _addressEditorDraft = null;
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
          content: Text(
            'Vui lòng nhập đủ thông tin người nhận và xác nhận địa chỉ giao hàng.',
          ),
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
