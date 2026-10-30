import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/cart_failure.dart';
import '../../domain/models/cart_item.dart';
import '../view_models/cart_state.dart';
import '../view_models/cart_providers.dart';
import '../widgets/cart_item_tile.dart';
import '../widgets/cart_notice.dart';
import '../../../catalog/presentation/widgets/catalog_formatters.dart';

/// MH06: customer cart.
///
/// Checkout is intentionally represented as a disabled action until MH16 is
/// integrated. Cart reads and mutations still use the shared CartViewModel;
/// this page never talks to Supabase directly.
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final hasData = cart.hasValue && cart.asData != null;

    return Scaffold(
      key: const ValueKey('cart-page'),
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        actions: [
          IconButton(
            key: const ValueKey('cart-refresh'),
            onPressed: () => unawaited(_refresh(ref)),
            tooltip: 'Làm mới giỏ hàng',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !hasData
          ? _buildAsyncState(context, ref, cart)
          : _buildData(
              context,
              ref,
              cart.asData!.value,
              isRefreshing: cart.isLoading,
            ),
    );
  }

  Widget _buildAsyncState(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<CartState> cart,
  ) {
    if (cart.isLoading) {
      return const Center(
        key: ValueKey('cart-loading'),
        child: CircularProgressIndicator(),
      );
    }

    final error = cart.error;
    return _ScrollableStateMessage(
      key: const ValueKey('cart-error'),
      icon: Icons.cloud_off_outlined,
      message: _cartErrorMessage(error),
      actionKey: const ValueKey('cart-load-retry'),
      actionLabel: 'Thử lại',
      onAction: () => unawaited(_refresh(ref)),
    );
  }

  Widget _buildData(
    BuildContext context,
    WidgetRef ref,
    CartState state, {
    required bool isRefreshing,
  }) {
    if (state.items.isEmpty) {
      return RefreshIndicator(
        key: const ValueKey('cart-empty-refresh'),
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            if (isRefreshing) const LinearProgressIndicator(),
            if (state.hasPendingMutation || state.mutationError != null) ...[
              _buildMutationNotice(ref, state),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 120),
            const Icon(Icons.shopping_bag_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              'Giỏ hàng đang trống',
              key: const ValueKey('cart-empty'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hãy khám phá sản phẩm và thêm món đồ bạn yêu thích vào đây.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('cart-browse'),
              onPressed: () => context.go('/customer/products'),
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Khám phá sản phẩm'),
            ),
          ],
        ),
      );
    }

    final mutationsEnabled = !state.isMutating && !state.hasPendingMutation;
    return RefreshIndicator(
      key: const ValueKey('cart-refresh-indicator'),
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          if (isRefreshing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          if (state.hasPendingMutation || state.mutationError != null) ...[
            _buildMutationNotice(ref, state),
            const SizedBox(height: 12),
          ],
          for (final item in state.items) ...[
            CartItemTile(
              key: ValueKey('cart-row-${item.variantId}'),
              item: item,
              mutationsEnabled: mutationsEnabled,
              onIncrease: () => _setQuantity(ref, item, item.quantity + 1),
              onDecrease: () => _setQuantity(ref, item, _decreaseTarget(item)),
              onRemove: () => _removeItem(ref, item),
            ),
            const SizedBox(height: 10),
          ],
          _CartSummary(state: state),
        ],
      ),
    );
  }

  _PendingMutationNotice _buildMutationNotice(WidgetRef ref, CartState state) {
    final hasPendingMutation = state.hasPendingMutation;
    return _PendingMutationNotice(
      error: state.mutationError,
      isMutating: state.isMutating,
      actionLabel: hasPendingMutation ? 'Thử lại thao tác' : 'Làm mới giỏ hàng',
      onAction: hasPendingMutation
          ? () => unawaited(_retryPendingMutation(ref))
          : () => unawaited(_refresh(ref)),
    );
  }

  static int _decreaseTarget(CartItem item) {
    final target = item.quantity - 1;
    final available = item.variant?.availableQuantity ?? 0;
    if (available <= 0) return target;
    return math.min(target, available);
  }

  Future<void> _refresh(WidgetRef ref) async {
    try {
      await ref.read(cartProvider.notifier).refresh();
    } catch (_) {
      // The provider owns the error state. Keeping this callback quiet lets a
      // pull-to-refresh gesture complete while the page renders that state.
    }
  }

  void _setQuantity(WidgetRef ref, CartItem item, int quantity) {
    if (quantity < 1) return;
    unawaited(
      ref
          .read(cartProvider.notifier)
          .setQuantity(variantId: item.variantId, quantity: quantity),
    );
  }

  void _removeItem(WidgetRef ref, CartItem item) {
    unawaited(ref.read(cartProvider.notifier).removeItem(item.variantId));
  }

  Future<void> _retryPendingMutation(WidgetRef ref) async {
    try {
      await ref.read(cartProvider.notifier).retryPendingMutation();
    } catch (_) {
      // CartViewModel maps operation failures to CartState.mutationError.
    }
  }

  static String _cartErrorMessage(Object? error) {
    if (error is CartFailure) return error.message;
    return 'Không tải được giỏ hàng. Vui lòng thử lại.';
  }
}

class _ScrollableStateMessage extends StatelessWidget {
  const _ScrollableStateMessage({
    required this.icon,
    required this.message,
    required this.actionKey,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async => onAction(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          Icon(icon, size: 50, color: scheme.error),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _PendingMutationNotice extends StatelessWidget {
  const _PendingMutationNotice({
    required this.error,
    required this.isMutating,
    required this.actionLabel,
    required this.onAction,
  });

  final CartFailure? error;
  final bool isMutating;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CartNotice(
              isError: true,
              icon: Icons.sync_problem_outlined,
              message: error?.message ?? 'Thao tác giỏ hàng chưa được xác nhận. Các nút chỉnh sửa đang tạm khóa.',
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                key: const ValueKey('cart-retry'),
                onPressed: isMutating ? null : onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({required this.state});

  final CartState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Tạm tính',
                    key: const ValueKey('cart-subtotal'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    formatVnd(state.subtotalVnd),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${state.totalQuantity} sản phẩm'),
            if (state.hasUnavailableItems) ...[
              const SizedBox(height: 6),
              const Text(
                'Dòng không còn khả dụng chưa được cộng vào tạm tính.',
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('cart-checkout'),
                onPressed: state.canCheckout
                    ? () => context.push('/customer/checkout')
                    : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Tiến hành đặt hàng'),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thanh toán khi nhận hàng. Phí giao hàng tại Hà Nội: 30.000 đ.',
              textAlign: TextAlign.center,
            ),
            if (state.items.any((item) => !item.canCheckout)) ...[
              const SizedBox(height: 4),
              Text(
                'Hãy xóa sản phẩm không còn bán hoặc điều chỉnh số lượng trước khi đặt hàng.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
