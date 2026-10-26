// Scripted HTTP reads only; no manager write/completion API is simulated live.
import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cod/domain/models/cod_collection.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_providers.dart';
import 'package:sports_store/features/cod/presentation/view_models/cod_read_refresh.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/domain/models/operational_failure.dart';

import '../support/operational_supabase_fixture.dart';

const _order = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

class _RecoveringAccessFixture extends OperationalReadAccess {
  _RecoveringAccessFixture(super.client);
  MultiStreamController<OperationalSession>? listener;
  var retries = 0;
  @override
  Stream<OperationalSession> watchSession() => Stream.multi((controller) {
    listener = controller;
    controller.addError(
      const OperationalFailure(OperationalFailureCode.network),
    );
    controller.onCancel = () {
      listener = null;
    };
  });
  @override
  void refreshSession() {
    retries++;
    listener?.add(OperationalSession(userId: shipperA, generation: retries));
  }
}

void main() {
  test(
    'role retry recovers an upstream session error before checking profile',
    () async {
      var profiles = 0;
      final client = await fixtureClient((request) async {
        expect(request.url.path, endsWith('/profiles'));
        profiles++;
        return jsonResponse(request, [
          {'role': 'shipper'},
        ]);
      });
      final access = _RecoveringAccessFixture(client);
      final container = ProviderContainer(
        overrides: [operationalReadAccessProvider.overrideWithValue(access)],
      );
      final subscription = container.listen(codScreenRoleProvider, (_, _) {});
      addTearDown(() async {
        subscription.close();
        container.dispose();
        await access.dispose();
        await client.dispose();
      });
      await _until(
        container,
        () => container.read(codScreenRoleProvider).hasError,
      );
      expect(profiles, 0);
      container.read(retryCodScreenRoleProvider)();
      await _until(
        container,
        () => container.read(codScreenRoleProvider).asData?.value == 'shipper',
      );
      expect(access.retries, 1);
      expect(profiles, 1);
    },
  );
  test(
    'confirmed-write hook reloads real backing legacy and shipper providers',
    () async {
      var received = false;
      var reads = 0;
      final client = await fixtureClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return jsonResponse(request, [
            {'role': 'shipper'},
          ]);
        }
        expect(request.url.path, endsWith('/rpc/list_cod_collections'));
        reads++;
        final params = jsonDecode(request.body) as Map;
        final visible = !received || params['p_statuses'] == null;
        return jsonResponse(request, {
          'items': visible
              ? [
                  {
                    'order_id': _order,
                    'order_code': _order,
                    'order_code_source': 'order_uuid',
                    'shipper_id': shipperA,
                    'status': received ? 'received' : 'collected',
                    'expected_amount_vnd': 550000,
                    'collected_amount_vnd': 550000,
                    'received_amount_vnd': received ? 550000 : 0,
                    'collected_by': shipperA,
                    'received_by': received ? shipperB : null,
                    'collected_at': '2026-10-25T08:00:00Z',
                    'received_at': received ? '2026-10-25T09:00:00Z' : null,
                    'handed_over_at': null,
                    'created_at': '2026-10-25T07:00:00Z',
                    'updated_at': '2026-10-25T09:00:00Z',
                  },
                ]
              : [],
          'next_cursor': null,
          'filtered_total': visible ? 1 : 0,
          'counts': {
            'all': 1,
            'uncollected': 0,
            'collected': received ? 0 : 1,
            'received': received ? 1 : 0,
          },
          'outstanding_vnd': received ? 0 : 550000,
          'as_of': '2026-10-25T09:00:00Z',
        });
      });
      final container = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
      );
      final legacy = container.listen(codCollectionsProvider, (_, _) {});
      final current = container.listen(
        shipperCodViewModelProvider(null),
        (_, _) {},
      );
      addTearDown(() async {
        legacy.close();
        current.close();
        container.dispose();
        await client.dispose();
      });
      await _until(
        container,
        () =>
            container.read(codCollectionsProvider).hasValue &&
            container.read(shipperCodViewModelProvider(null)).heldTotalVnd ==
                550000,
      );
      final before = reads;
      received = true; // Explicit fixture change; not a successful write claim.
      final callback = Provider<void Function()>(
        (ref) =>
            () => refreshCodReadsAfterConfirmedWrite(ref),
      );
      container.read(callback)();
      await _until(
        container,
        () =>
            container
                    .read(codCollectionsProvider)
                    .asData
                    ?.value
                    .single
                    .status ==
                CodStatus.received &&
            container.read(shipperCodViewModelProvider(null)).heldTotalVnd == 0,
      );
      expect(reads, greaterThanOrEqualTo(before + 2));
      expect(container.read(shipperCodViewModelProvider(null)).items, isEmpty);
    },
  );
}

Future<void> _until(ProviderContainer container, bool Function() done) async {
  for (var index = 0; index < 100; index++) {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    if (done()) return;
  }
  fail('COD provider fixture did not settle');
}
