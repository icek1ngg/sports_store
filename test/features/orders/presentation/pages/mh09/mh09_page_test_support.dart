import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/state/foundation_providers.dart';
import 'package:sports_store/core/state/read_retry_policy.dart';
import 'package:sports_store/core/state/session_scope.dart';
import 'package:sports_store/features/orders/domain/models/order_details.dart';
import 'package:sports_store/features/orders/domain/repositories/order_repository.dart';
import 'package:sports_store/features/orders/presentation/pages/manager_order_details_page.dart';
import 'package:sports_store/features/orders/presentation/view_models/order_providers.dart';

import 'mh09_page_test_fixtures.dart';

export 'mh09_page_test_fixtures.dart';

const mh09ManagerScope = SessionScope(
  userId: fixtureManagerId,
  role: 'manager',
  generation: 1,
);
const mh09CustomerScope = SessionScope(
  userId: fixtureCustomerId,
  role: 'customer',
  generation: 2,
);

final mh09TestSessionProvider = Provider<SessionScope>(
  (ref) => mh09ManagerScope,
);

class Mh09PageOrders implements OrderRepository {
  Mh09PageOrders(this.result);

  FutureOr<OrderDetails> Function()? result;
  int detailCalls = 0;

  @override
  Future<OrderDetails> getOrderDetails(String orderId) async {
    detailCalls++;
    final value = result?.call();
    if (value is Future<OrderDetails>) return value;
    return value as OrderDetails;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Mutation/list is outside this page test.');
}

Widget mh09PageHost({
  required Mh09PageOrders repository,
  SessionScope scope = mh09ManagerScope,
  bool largeText = false,
  Widget? pageOverride,
  ValueChanged<String>? onOpenCod,
  ValueChanged<String>? onOpenReturn,
  ValueChanged<String>? onOpenChat,
  ValueChanged<String>? onCallRecipient,
}) {
  return ProviderScope(
    overrides: [
      mh09TestSessionProvider.overrideWithValue(scope),
      featureSessionScopeProvider.overrideWith(
        (ref) => ref.watch(mh09TestSessionProvider),
      ),
      orderRepositoryProvider.overrideWithValue(repository),
      readRetryPolicyProvider.overrideWithValue(
        const ReadRetryPolicy(backoffs: []),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(320, 900),
          textScaler: largeText ? TextScaler.linear(2) : TextScaler.noScaling,
        ),
        child:
            pageOverride ??
            ManagerOrderDetailsPage(
              orderId: fixtureOrderId,
              onOpenCod: onOpenCod,
              onOpenReturn: onOpenReturn,
              onOpenChat: onOpenChat,
              onCallRecipient: onCallRecipient,
              enablePolling: false,
            ),
      ),
    ),
  );
}
