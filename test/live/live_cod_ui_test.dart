// Opt-in real-network widget integration; not part of the offline test suite.
//
// The live harness seeds the COD rows before this test starts.  This test
// deliberately signs in through the real Supabase client and renders the
// production CodRoutePage, rather than overriding repositories or inserting
// optimistic fixture data into Riverpod.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sports_store/app/theme/app_theme.dart';
import 'package:sports_store/core/supabase/supabase_providers.dart';
import 'package:sports_store/features/cod/presentation/pages/cod_route_page.dart';
import 'package:sports_store/features/cod/presentation/view_models/manager_cod_view_model.dart';
import 'package:sports_store/features/cod/presentation/view_models/shipper_cod_view_model.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

/// Transparent live transport used only for the opt-in lost-ACK check.
///
/// The first real `confirm_cod_received` response is fully consumed (so the
/// database transaction has committed) and then surfaced to the repository as
/// a client exception.  The subsequent retry therefore has to reuse the same
/// request body/idempotency key.  No headers, tokens, response data, or
/// credentials are retained or logged.
final class _LostAckHttpClient extends http.BaseClient {
  _LostAckHttpClient(this._inner);

  final http.Client _inner;
  final requestBodies = <List<int>>[];
  var injectLostAck = false;
  var _injected = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // A live widget test crosses fake-async and real-async zones. Do not reuse
    // a socket whose callbacks were registered in the other zone at login.
    request.persistentConnection = false;
    final isReceipt = request.url.path.endsWith(
      '/rest/v1/rpc/confirm_cod_received',
    );
    if (isReceipt && request is http.Request) {
      requestBodies.add(List<int>.from(request.bodyBytes));
    }
    final response = await _inner.send(request);
    if (!isReceipt || !injectLostAck || _injected) return response;

    // Drain the real response before failing.  This is intentionally a
    // post-commit transport fault, not a mocked or locally manufactured RPC.
    await response.stream.toBytes();
    _injected = true;
    throw http.ClientException(
      'live test lost ACK after real response',
      request.url,
    );
  }

  @override
  void close() => _inner.close();
}

void main() {
  _LiveBinding();
  final env = Platform.environment;

  testWidgets('real Auth → MH12 COD list, receipt, and account isolation', (
    tester,
  ) async {
    SupabaseClient? client;
    _LostAckHttpClient? transport;
    ProviderContainer? container;

    Future<void> waitFor(bool Function() done, String description) async {
      for (var i = 0; i < 300; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (done()) return;
      }
      fail('Live COD state did not settle: $description');
    }

    Future<void> reveal(Finder finder, {double delta = 500}) async {
      await tester.scrollUntilVisible(
        finder,
        delta,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
    }

    Future<void> clearManagerFilters() async {
      final clear = find.byKey(const ValueKey('manager-cod-clear'));
      await reveal(clear, delta: -1000);
      await tester.tap(clear);
    }

    Future<void> signIn(String email, String password) async {
      await tester.runAsync(() async {
        await client!.auth.signOut().timeout(const Duration(seconds: 20));
        await client!.auth
            .signInWithPassword(email: email, password: password)
            .timeout(const Duration(seconds: 20));
      });
      await tester.pump();
    }

    try {
      await tester.runAsync(() async {
        final io = HttpClient();
        final ip = env['LIVE_SUPABASE_IP'];
        if (ip != null && InternetAddress.tryParse(ip) != null) {
          final host = Uri.parse(env['LIVE_SUPABASE_URL']!).host;
          io.connectionFactory = (uri, proxyHost, proxyPort) async {
            final task = await Socket.startConnect(
              proxyHost ?? (uri.host == host ? InternetAddress(ip) : uri.host),
              proxyPort ?? uri.port,
            );
            if (uri.scheme == 'https' && proxyHost == null) {
              return ConnectionTask.fromSocket<Socket>(
                task.socket.then<Socket>(
                  (socket) => SecureSocket.secure(socket, host: uri.host),
                ),
                task.cancel,
              );
            }
            return task;
          };
        }
        // HttpClient still verifies TLS against the original URI/SNI host.
        transport = _LostAckHttpClient(IOClient(io));
        client = SupabaseClient(
          env['LIVE_SUPABASE_URL']!,
          env['LIVE_PUBLISHABLE_KEY']!,
          httpClient: transport,
        );
        await client!.auth.signInWithPassword(
          email: env['LIVE_TEST_EMAIL']!,
          password: env['LIVE_TEST_PASSWORD']!,
        );
      });

      final liveClient = client!;
      debugPrint('LIVE P06 UI: real shipper login complete');
      final liveContainer = ProviderContainer(
        overrides: [supabaseClientProvider.overrideWithValue(liveClient)],
      );
      container = liveContainer;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: liveContainer,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: CodRoutePage()),
          ),
        ),
      );

      // Shipper: the route must expose only the shipper branch and its own
      // server-computed outstanding total.  The seeded data contains 101
      // 130,000 VND collected rows plus the real 550,000 VND primary order;
      // one separate 130,000 VND row is already reconciled and one is
      // uncollected, so neither belongs in the outstanding total.
      await waitFor(
        () =>
            find
                .byKey(const ValueKey('cod-held-total'))
                .evaluate()
                .isNotEmpty &&
            liveContainer.read(shipperCodViewModelProvider(null)).isLoading ==
                false,
        'shipper initial COD list',
      );
      expect(find.byKey(const ValueKey('manager-cod-panel')), findsNothing);
      expect(find.byKey(const ValueKey('manager-cod-open')), findsNothing);
      expect(find.text('13.680.000 đ'), findsOneWidget);

      var shipperState = liveContainer.read(shipperCodViewModelProvider(null));
      expect(shipperState.filteredTotal, 102);
      expect(shipperState.counts?.collected, 102);
      expect(shipperState.items, hasLength(100));
      expect(shipperState.hasMore, isTrue);

      // The first request is page-sized.  Load-more must use the server cursor
      // and finish with all 101 fixture rows plus the primary order, without
      // changing the authoritative held total.
      final shipperLoadMore = find.byKey(const ValueKey('cod-load-more'));
      await reveal(shipperLoadMore);
      await tester.tap(shipperLoadMore);
      await tester.pump();
      await waitFor(
        () =>
            (shipperState = liveContainer.read(
              shipperCodViewModelProvider(null),
            )).items.length ==
            102,
        'shipper COD load-more page',
      );
      expect(shipperState.hasMore, isFalse);
      debugPrint('LIVE P06 UI: shipper pagination complete');
      expect(shipperState.heldTotalVnd, 13680000);
      expect(
        shipperState.items.any((item) => item.orderId == env['LIVE_ORDER_ID']),
        isTrue,
      );
      await reveal(
        find.byKey(ValueKey('cod-record-${env['LIVE_ORDER_ID']}')),
        delta: -600,
      );
      expect(
        find.byKey(ValueKey('cod-record-${env['LIVE_ORDER_ID']}')),
        findsWidgets,
      );

      // The reconciled tab is explicit; it must not be folded into the
      // unreconciled count or held-money total.
      final shipperReconciled = find.byKey(const ValueKey('cod-reconciled'));
      await reveal(shipperReconciled, delta: -1000);
      await tester.tap(shipperReconciled);
      await tester.pump();
      await waitFor(
        () =>
            liveContainer.read(shipperCodViewModelProvider(null)).group ==
                ShipperCodGroup.reconciled &&
            !liveContainer.read(shipperCodViewModelProvider(null)).isLoading,
        'shipper reconciled group',
      );
      shipperState = liveContainer.read(shipperCodViewModelProvider(null));
      expect(shipperState.filteredTotal, 1);
      expect(shipperState.counts?.received, 1);
      expect(
        find.byKey(ValueKey('cod-record-${env['LIVE_ORDER_ID']}')),
        findsNothing,
      );

      final shipperUnreconciled = find.byKey(
        const ValueKey('cod-unreconciled'),
      );
      await reveal(shipperUnreconciled, delta: -1000);
      await tester.tap(shipperUnreconciled);
      await tester.pump();
      await waitFor(
        () =>
            liveContainer.read(shipperCodViewModelProvider(null)).group ==
            ShipperCodGroup.unreconciled,
        'shipper return to unreconciled group',
      );

      // Switch to the manager using the same authenticated Supabase client.
      // No manager repository or role provider is overridden in this test.
      await signIn(env['LIVE_MANAGER_EMAIL']!, env['LIVE_MANAGER_PASSWORD']!);
      debugPrint('LIVE P06 UI: real manager login complete');
      await waitFor(
        () => find
            .byKey(const ValueKey('manager-cod-panel'))
            .evaluate()
            .isNotEmpty,
        'manager role branch',
      );
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.heldTotalVnd != null &&
            state.heldTotalVnd! >= 13810000 &&
            state.filteredTotal != null &&
            state.filteredTotal! >= 103;
      }, 'manager global COD list');
      var managerState = liveContainer.read(managerCodViewModelProvider(null));
      expect(managerState.filteredTotal, greaterThanOrEqualTo(103));
      expect(managerState.heldTotalVnd, greaterThanOrEqualTo(13810000));
      expect(managerState.items, hasLength(100));
      expect(find.byKey(const ValueKey('manager-cod-panel')), findsOneWidget);

      final primaryOrderId = env['LIVE_ORDER_ID']!;
      final shipperId = env['LIVE_SHIPPER_ID']!;
      final otherShipperId = env['LIVE_OTHER_SHIPPER_ID']!;

      // Both UUID filters are sent to the production RPC.  First verify the
      // shipper scope, then combine it with the order UUID so the query cannot
      // be satisfied by client-side filtering of the first page.
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        shipperId,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-apply')));
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.filteredTotal == 102 &&
            state.heldTotalVnd == 13680000;
      }, 'manager shipper UUID filter');

      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        primaryOrderId,
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        shipperId,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-apply')));
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.filteredTotal == 1 &&
            state.items.length == 1 &&
            state.items.single.orderId.toLowerCase() ==
                primaryOrderId.toLowerCase();
      }, 'manager UUID order/shipper filter');
      managerState = liveContainer.read(managerCodViewModelProvider(null));
      expect(managerState.heldTotalVnd, 550000);
      debugPrint('LIVE P06 UI: combined manager filters complete');
      await reveal(find.byKey(ValueKey('manager-cod-record-$primaryOrderId')));
      expect(
        find.byKey(ValueKey('manager-cod-record-$primaryOrderId')),
        findsOneWidget,
      );

      // A valid but incompatible UUID combination returns an empty server
      // result; the clear action restores the unfiltered scope.
      await clearManagerFilters();
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.filteredTotal != null &&
            state.filteredTotal! >= 103 &&
            state.heldTotalVnd != null &&
            state.heldTotalVnd! >= 13810000;
      }, 'manager clear filters');
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        primaryOrderId,
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        otherShipperId,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-apply')));
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading && state.filteredTotal == 0;
      }, 'manager empty incompatible filter');
      await reveal(find.byKey(const ValueKey('manager-cod-empty')));
      expect(find.byKey(const ValueKey('manager-cod-empty')), findsOneWidget);

      // Re-select the primary collected row for the real full-amount receipt.
      await clearManagerFilters();
      await tester.pump();
      await waitFor(
        () =>
            !liveContainer.read(managerCodViewModelProvider(null)).isLoading &&
            liveContainer
                    .read(managerCodViewModelProvider(null))
                    .filteredTotal !=
                null &&
            liveContainer
                    .read(managerCodViewModelProvider(null))
                    .filteredTotal! >=
                103,
        'manager restore before receipt',
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        primaryOrderId,
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        shipperId,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-apply')));
      await tester.pump();
      await waitFor(
        () =>
            !liveContainer.read(managerCodViewModelProvider(null)).isLoading &&
            liveContainer
                    .read(managerCodViewModelProvider(null))
                    .filteredTotal ==
                1,
        'manager primary row before receipt',
      );

      final openPrimary = find.byKey(
        ValueKey('manager-cod-open-$primaryOrderId'),
      );
      await reveal(openPrimary);
      await tester.tap(openPrimary);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('manager-cod-confirm-amount')),
        findsOneWidget,
      );
      expect(find.text('550.000 đ'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manager-cod-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-received-full')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('manager-cod-confirm')),
            )
            .onPressed,
        isNotNull,
      );

      // The dialog closes before the money-moving request is sent.  A second
      // tap cannot pop CodRoutePage or submit another request ID.
      final confirm = find.byKey(const ValueKey('manager-cod-confirm'));
      transport!.injectLostAck = true;
      debugPrint('LIVE P06 UI: confirming full receipt with lost ACK test');
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('manager-cod-panel')), findsOneWidget);

      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isSubmitting &&
            state.pendingCommand != null &&
            state.actionError != null;
      }, 'lost-ACK receipt retry state');
      expect(transport!.requestBodies, hasLength(1));
      debugPrint('LIVE P06 UI: committed receipt ACK intentionally lost');

      final retry = find.byKey(const ValueKey('manager-cod-action-retry'));
      await reveal(retry, delta: -500);
      await tester.tap(retry);
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isSubmitting &&
            state.pendingCommand == null &&
            state.filteredTotal == 0 &&
            state.heldTotalVnd == 0;
      }, 'idempotent receipt retry after lost ACK');
      expect(transport!.requestBodies, hasLength(2));
      debugPrint('LIVE P06 UI: exact-key receipt retry complete');
      expect(
        transport!.requestBodies[0],
        orderedEquals(transport!.requestBodies[1]),
      );

      // Refresh the global manager scope and verify the server-side held
      // totals/counts changed, while the reconciled group contains the newly
      // received primary row.
      await clearManagerFilters();
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.heldTotalVnd != null &&
            state.heldTotalVnd! >= 13260000 &&
            state.filteredTotal != null &&
            state.filteredTotal! >= 102;
      }, 'manager post-receipt global totals smoke check');

      // Use the shipper UUID scope for deterministic post-receipt totals; a
      // shared manager account may legitimately see unrelated COD rows.
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-order-filter')),
        '',
      );
      await tester.enterText(
        find.byKey(const ValueKey('manager-cod-shipper-filter')),
        shipperId,
      );
      await tester.tap(find.byKey(const ValueKey('manager-cod-apply')));
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading &&
            state.filteredTotal == 101 &&
            state.heldTotalVnd == 13130000;
      }, 'manager shipper-scoped post-receipt totals');
      final managerReconciled = find.byKey(
        const ValueKey('manager-cod-reconciled'),
      );
      await reveal(managerReconciled, delta: -1000);
      await tester.tap(managerReconciled);
      await tester.pump();
      await waitFor(() {
        final state = liveContainer.read(managerCodViewModelProvider(null));
        return !state.isLoading && state.filteredTotal == 2;
      }, 'manager reconciled group after receipt');
      await reveal(find.byKey(ValueKey('manager-cod-record-$primaryOrderId')));
      expect(
        find.byKey(ValueKey('manager-cod-record-$primaryOrderId')),
        findsOneWidget,
      );

      // Account switching on the same client must clear the previous role's
      // cache and never expose shipper A's primary order to shipper B.
      await signIn(env['LIVE_TEST_EMAIL']!, env['LIVE_TEST_PASSWORD']!);
      await waitFor(
        () =>
            find.byKey(const ValueKey('cod-held-total')).evaluate().isNotEmpty,
        'shipper A after account switch',
      );
      await waitFor(() {
        final state = liveContainer.read(shipperCodViewModelProvider(null));
        return !state.isLoading && state.heldTotalVnd == 13130000;
      }, 'shipper A post-receipt held total');
      expect(find.byKey(ValueKey('cod-record-$primaryOrderId')), findsNothing);
      final switchedShipperReconciled = find.byKey(
        const ValueKey('cod-reconciled'),
      );
      await reveal(switchedShipperReconciled, delta: -1000);
      await tester.tap(switchedShipperReconciled);
      await tester.pump();
      await waitFor(
        () =>
            !liveContainer.read(shipperCodViewModelProvider(null)).isLoading &&
            liveContainer.read(shipperCodViewModelProvider(null)).group ==
                ShipperCodGroup.reconciled &&
            !liveContainer.read(shipperCodViewModelProvider(null)).isLoading,
        'shipper A primary row in reconciled group',
      );
      await reveal(find.byKey(ValueKey('cod-record-$primaryOrderId')));

      await signIn(env['LIVE_OTHER_EMAIL']!, env['LIVE_OTHER_PASSWORD']!);
      await waitFor(
        () =>
            find.byKey(const ValueKey('cod-held-total')).evaluate().isNotEmpty,
        'shipper B after account switch',
      );
      await waitFor(() {
        final state = liveContainer.read(shipperCodViewModelProvider(null));
        return !state.isLoading && state.heldTotalVnd == 130000;
      }, 'shipper B isolated held total');
      expect(find.byKey(ValueKey('cod-record-$primaryOrderId')), findsNothing);
      expect(find.byKey(const ValueKey('manager-cod-panel')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      if (client != null) {
        await tester.runAsync(() => client!.dispose());
      }
      transport?.close();
    }
  }, skip: env['LIVE_COD_UI'] != '1');
}
