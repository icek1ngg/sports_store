import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/data/repositories/supabase_redelivery_repository.dart';
import 'package:sports_store/features/deliveries/domain/models/redelivery_command.dart';

import '../support/operational_supabase_fixture.dart';

void main() {
  for (final failure in ['timeout', 'denied', 'stale', 'malformed']) {
    test(
      'redelivery $failure never fabricates success; retry preserves envelope',
      () async {
        final requests = <Map<String, dynamic>>[];
        final client = await fixtureClient((r) async {
          if (r.url.path.endsWith('/profiles')) {
            return jsonResponse(r, [
              {'role': 'shipper'},
            ]);
          }
          expect(r.url.path, endsWith('/rpc/complete_redelivery'));
          requests.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (failure == 'timeout') {
            throw TimeoutException('test transport timeout');
          }
          if (failure == 'malformed') {
            return jsonResponse(r, {'task_status': 'delivered'});
          }
          return jsonResponse(r, {
            'code': failure == 'denied' ? '42501' : 'PT409',
            'message': failure == 'denied'
                ? 'PERMISSION_DENIED'
                : 'STATE_CONFLICT',
          }, status: failure == 'denied' ? 403 : 409);
        });
        final access = OperationalReadAccess(client);
        await Future<void>.delayed(Duration.zero);
        final command = RedeliveryCommand.complete(
          taskId: '11111111-1111-4111-8111-111111111111',
          requestId: '22222222-2222-4222-8222-222222222222',
          returnRequestId: '33333333-3333-4333-8333-333333333333',
          orderId: '44444444-4444-4444-8444-444444444444',
        );
        try {
          final repo = SupabaseRedeliveryRepository(access: access);
          await expectLater(repo.execute(command), throwsA(isA<Object>()));
          await expectLater(repo.execute(command), throwsA(isA<Object>()));
          expect(requests.length, 2);
          expect(requests[0], requests[1]);
          expect(requests.first, {
            'p_task_id': command.taskId,
            'p_request_id': command.requestId,
            'p_received_all_items': true,
          });
        } finally {
          await access.dispose();
          await client.dispose();
        }
      },
    );
  }
}
