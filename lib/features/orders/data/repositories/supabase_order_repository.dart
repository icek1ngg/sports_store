import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/wire_parsing.dart';
import '../../../../core/state/session_scope.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_command.dart';
import '../../domain/models/order_details.dart';
import '../../domain/models/order_mutation_receipt.dart';
import '../../domain/models/order_page.dart';
import '../../domain/models/order_query.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/operation_result.dart';
import '../../domain/repositories/order_repository.dart';
import '../models/order_dto.dart';

typedef _ReadScope = ({SessionScope scope, Session sdk});

/// Canonical Orders aggregate and transactional command transport.
/// Auth and cache lifecycle remain owned by the shared production composition.
/// Commands accept only server receipts; no raw status writes are performed.
class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository({required this.client, required this.readSession});

  final SupabaseClient client;
  final SessionScope Function() readSession;

  _ReadScope _capture(Set<String> roles) {
    final SessionScope scope;
    final Session? sdk;
    try {
      scope = readSession();
      sdk = client.auth.currentSession;
    } catch (_) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    if (!scope.canReadPrivateData ||
        sdk == null ||
        sdk.expiresAt == null ||
        sdk.isExpired ||
        sdk.user.id != scope.userId) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    if (!roles.contains(scope.role)) {
      throw const AppFailure(code: AppFailure.forbiddenOrUnavailable);
    }
    try {
      requiredUuid({'id': scope.userId}, 'id');
    } catch (_) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
    return (scope: scope, sdk: sdk);
  }

  void _assertCurrent(_ReadScope request) {
    final current = _capture({'customer', 'manager'});
    if (current.scope != request.scope ||
        !identical(current.sdk, request.sdk)) {
      throw const AppFailure(code: AppFailure.unauthenticated);
    }
  }

  Future<T> _read<T>(
    String rpc,
    Map<String, Object?> params,
    Set<String> roles,
    T Function(Map<String, Object?>, _ReadScope) decode,
  ) async {
    final request = _capture(roles);
    try {
      final raw = await client
          .rpc(rpc, params: params)
          .setHeader('Authorization', 'Bearer ${request.sdk.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 10));
      _assertCurrent(request);
      if (raw is! Map) {
        throw const AppFailure(code: AppFailure.unsupportedData);
      }
      final result = decodeOrderRpcEnvelope(
        Map<String, Object?>.from(raw),
        (data) => decode(data, request),
      );
      _assertCurrent(request);
      return result;
    } catch (error) {
      // Reject errors as well as successful data from a superseded session.
      _assertCurrent(request);
      throw _failure(error);
    }
  }

  void _checkOrder(Order order, _ReadScope request) {
    if (request.scope.role == 'customer' &&
        order.customerId != request.scope.userId) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
  }

  Future<OrderPage> _page(String rpc, String role, OrderQuery query) =>
      _read(rpc, query.toRpcParams(), {role}, (json, request) {
        final page = OrderListResponseDto.fromJson(json).domain;
        if (page.items.length > query.limit ||
            (page.nextCursor?.length ?? 0) > 2048) {
          throw const AppFailure(code: AppFailure.unsupportedData);
        }
        Order? previous;
        for (final summary in page.items) {
          final order = summary.order;
          _checkOrder(order, request);
          if (query.statuses.isNotEmpty &&
              !query.statuses.contains(order.status)) {
            throw const AppFailure(code: AppFailure.unsupportedData);
          }
          if (previous != null &&
              (order.placedAt.isAfter(previous.placedAt) ||
                  (order.placedAt == previous.placedAt &&
                      order.id.compareTo(previous.id) >= 0))) {
            throw const AppFailure(code: AppFailure.unsupportedData);
          }
          previous = order;
        }
        final relevantCounts = query.statuses.isEmpty
            ? page.statusCounts.values
            : query.statuses.map((status) => page.statusCounts[status]!);
        if (relevantCounts.fold<int>(0, (sum, count) => sum + count) !=
            page.totalCount) {
          throw const AppFailure(code: AppFailure.unsupportedData);
        }
        return page;
      });

  @override
  Future<OrderPage> getCustomerOrders(OrderQuery query) =>
      _page('get_customer_orders', 'customer', query);

  @override
  Future<OrderPage> getManagerOrders(OrderQuery query) =>
      _page('get_manager_orders', 'manager', query);

  @override
  Future<OrderDetails> getOrderDetails(String orderId) {
    final String id;
    try {
      id = requiredUuid({'id': orderId}, 'id');
    } catch (_) {
      return Future.error(const AppFailure(code: AppFailure.invalidArgument));
    }
    return _read(
      'get_order_details',
      {'p_order_id': id},
      {'customer', 'manager'},
      (json, request) {
        final details = OrderDetailsDto.fromJson(json).domain;
        _checkOrder(details.order, request);
        if (details.order.id != id) {
          throw const AppFailure(code: AppFailure.unsupportedData);
        }
        return details;
      },
    );
  }

  void _checkReceipt(
    OrderMutationReceipt receipt,
    String requestId,
    String orderId,
    OrderOperation operation,
    _ReadScope request,
  ) {
    _checkOrder(receipt.order, request);
    final expectedStatus = switch (operation) {
      OrderOperation.confirm => OrderStatus.preparing,
      OrderOperation.reject => OrderStatus.rejected,
      OrderOperation.customerCancel ||
      OrderOperation.managerCancel => OrderStatus.cancelled,
      _ => throw const AppFailure(code: AppFailure.invalidArgument),
    };
    if (receipt.requestId != requestId ||
        receipt.order.id != orderId ||
        receipt.operation != operation ||
        receipt.order.status != expectedStatus) {
      throw const AppFailure(code: AppFailure.unsupportedData);
    }
  }

  Future<OrderMutationReceipt> _mutate(
    String rpc,
    OrderOperation operation,
    StableOrderCommand command,
  ) async {
    if (command.operation != operation) {
      throw const AppFailure(code: AppFailure.invalidArgument);
    }
    final request = _capture({
      operation == OrderOperation.customerCancel ? 'customer' : 'manager',
    });
    try {
      final raw = await client
          .rpc(
            rpc,
            params: {
              'p_order_id': command.orderId,
              'p_request_id': command.requestId,
              if (operation == OrderOperation.reject ||
                  operation == OrderOperation.managerCancel)
                'p_reason': command.reason,
            },
          )
          .setHeader('Authorization', 'Bearer ${request.sdk.accessToken}')
          .retry(enabled: false, requestTimeout: const Duration(seconds: 15));
      _assertCurrent(request);
      if (raw is! Map) throw const AppFailure(code: AppFailure.unsupportedData);
      final receipt = decodeOrderRpcEnvelope(
        Map<String, Object?>.from(raw),
        (data) => OrderMutationReceiptDto.fromJson(data).domain,
      );
      _checkReceipt(
        receipt,
        command.requestId,
        command.orderId,
        operation,
        request,
      );
      _assertCurrent(request);
      return receipt;
    } catch (error) {
      _assertCurrent(request);
      final failure = _failure(error);
      // A lost or malformed ACK does not prove the transaction rolled back.
      if (failure.code == AppFailure.network ||
          failure.code == AppFailure.unsupportedData) {
        throw const AppFailure(
          code: AppFailure.outcomeUnknownCode,
          messageKey: 'MSG-10',
          retryable: true,
          outcomeUnknown: true,
        );
      }
      throw failure;
    }
  }

  @override
  Future<OrderMutationReceipt> confirm(StableOrderCommand command) =>
      _mutate('confirm_order', OrderOperation.confirm, command);
  @override
  Future<OrderMutationReceipt> reject(StableOrderCommand command) =>
      _mutate('reject_order', OrderOperation.reject, command);
  @override
  Future<OrderMutationReceipt> cancelCustomer(StableOrderCommand command) =>
      _mutate('cancel_customer_order', OrderOperation.customerCancel, command);
  @override
  Future<OrderMutationReceipt> cancelManager(StableOrderCommand command) =>
      _mutate('cancel_manager_order', OrderOperation.managerCancel, command);
  @override
  Future<OperationResult> getOperationResult({
    required String requestId,
    required String orderId,
    required OrderOperation operation,
  }) {
    try {
      requestId = requiredUuid({'id': requestId}, 'id');
      orderId = requiredUuid({'id': orderId}, 'id');
      if (!operation.isClientOperation) throw const FormatException();
    } catch (_) {
      return Future.error(const AppFailure(code: AppFailure.invalidArgument));
    }
    return _read(
      'get_order_operation_result',
      {
        'p_request_id': requestId,
        'p_order_id': orderId,
        'p_operation': operation.wireValue,
      },
      {operation == OrderOperation.customerCancel ? 'customer' : 'manager'},
      (json, request) {
        final result = OperationResultDto.fromJson(json).value;
        if (result.receipt != null) {
          _checkReceipt(
            result.receipt!,
            requestId,
            orderId,
            operation,
            request,
          );
        }
        return result;
      },
    );
  }

  static AppFailure _failure(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return const AppFailure(code: AppFailure.network, retryable: true);
    }
    if (error is PostgrestException) {
      final code = error.code;
      if ({'401', 'PGRST301', 'PGRST302', 'PGRST303'}.contains(code)) {
        return const AppFailure(code: AppFailure.unauthenticated);
      }
      if ({'403', '42501'}.contains(code)) {
        return const AppFailure(code: AppFailure.forbiddenOrUnavailable);
      }
      if ({
        'PGRST202',
        'PGRST204',
        'PGRST205',
        '42883',
        '42P01',
        '42703',
      }.contains(code)) {
        return const AppFailure(code: AppFailure.externalDependencyUnavailable);
      }
      if ({'22023', '22P02'}.contains(code)) {
        return const AppFailure(code: AppFailure.invalidArgument);
      }
      if ({'23503', '23505', '23514'}.contains(code)) {
        return const AppFailure(code: AppFailure.dataIntegrity);
      }
      final status = int.tryParse(code ?? '') ?? 0;
      if ((status >= 500 && status <= 599) ||
          {
            'PGRST000',
            'PGRST001',
            'PGRST002',
            'PGRST003',
            '40001',
            '40P01',
            '57014',
          }.contains(code)) {
        return const AppFailure(code: AppFailure.network, retryable: true);
      }
      return const AppFailure(code: AppFailure.unsupportedData);
    }
    if (error is AuthException) {
      return error is AuthRetryableFetchException
          ? const AppFailure(code: AppFailure.network, retryable: true)
          : const AppFailure(code: AppFailure.unauthenticated);
    }
    if (error is FormatException || error is Error) {
      return const AppFailure(code: AppFailure.unsupportedData);
    }
    return const AppFailure(code: AppFailure.network, retryable: true);
  }
}
