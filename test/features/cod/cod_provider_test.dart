import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/operational_supabase_fixture.dart';

Map<String, dynamic> _row(String shipper, String order) => {
  'order_id': order,
  'order_code': order,
  'order_code_source': 'order_uuid',
  'shipper_id': shipper,
  'status': 'collected',
  'expected_amount_vnd': '550000',
  'collected_amount_vnd': 550000,
  'received_amount_vnd': 0,
  'collected_by': shipper,
  'received_by': null,
  'collected_at': '2026-10-23T10:00:00+07:00',
  'handed_over_at': null,
  'received_at': null,
  'created_at': '2026-10-23T03:00:00Z',
  'updated_at': '2026-10-23T03:00:00Z',
};

Future<void> _until(ProviderContainer container, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('COD provider did not reach expected state');
}

void main() {
  test('real COD provider clears A data before B loads and after logout', () async {
    final delayedB = Completer<http.Response>();
    late http.Request requestB;
    var rpcCalls = 0;
    const orderA = '11111111-1111-4111-8111-111111111111';
    const orderB = '22222222-2222-4222-8222-222222222222';
    final client = await fixtureClient((request) async {
      if (request.url.path.endsWith('/logout')) {
        return jsonResponse(request, {});
      }
      if (request.url.path.endsWith('/profiles')) {
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      }
      expect(request.url.path, endsWith('/rpc/list_cod_collections'));
      rpcCalls++;
      if (rpcCalls == 2) {
        requestB = request;
        return delayedB.future;
      }
      return jsonResponse(request, _page([_row(shipperA, orderA)]));
    });
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    final subscription = container.listen(
      codCollectionsProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.dispose();
    });
    await _until(
      container,
      () => container.read(codCollectionsProvider).hasValue,
    );
    expect(
      container
          .read(codCollectionsProvider)
          .requireValue
          .single
          .outstandingAmountVnd,
      550000,
    );
    await recoverFixtureSession(client, shipperB);
    await _until(
      container,
      () => container.read(codCollectionsProvider).isLoading,
    );
    expect(container.read(codCollectionsProvider).asData, isNull);
    // Ensure B's SDK request has actually reached the injected test transport.
    await Future<void>.delayed(Duration.zero);
    delayedB.complete(jsonResponse(requestB, _page([_row(shipperB, orderB)])));
    await _until(
      container,
      () => container.read(codCollectionsProvider).hasValue,
    );
    expect(
      container.read(codCollectionsProvider).requireValue.single.orderId,
      orderB,
    );
    await client.auth.signOut(scope: SignOutScope.local);
    await _until(
      container,
      () => container.read(codCollectionsProvider).hasError,
    );
    expect(container.read(codCollectionsProvider).asData, isNull);
    expect(
      (container.read(codCollectionsProvider).error! as OperationalFailure)
          .code,
      OperationalFailureCode.sessionExpired,
    );
  });

  test(
    'COD provider preserves typed permission/network errors without success',
    () async {
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        return jsonResponse(request, {
          'code': '42501',
          'message': 'private evidence',
        }, status: 403);
      });
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      final subscription = container.listen(
        codCollectionsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await client.dispose();
      });
      await _until(
        container,
        () => container.read(codCollectionsProvider).hasError,
      );
      final state = container.read(codCollectionsProvider);
      expect(state.asData, isNull);
      expect(
        (state.error! as OperationalFailure).code,
        OperationalFailureCode.permissionDenied,
      );
      expect(state.error.toString(), isNot(contains('private evidence')));
    },
  );
}

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'items': items,
  'next_cursor': null,
  'filtered_total': items.length,
  'counts': {
    'all': items.length,
    'uncollected': 0,
    'collected': items.length,
    'received': 0,
  },
  'outstanding_vnd': items.length * 550000,
  'as_of': '2026-10-25T08:00:00Z',
};
